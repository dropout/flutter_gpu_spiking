import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'experiment.dart';
import 'params.dart';

/// A flutter_scene particle experiment: a sparkler under the pointer.
///
/// Press (or, with "Emit on hover", just move) to throw sparks from the
/// pointer. The pieces, all on flutter_scene's built-in CPU particle system:
///
///  * Sparks: a [ParticleSystem] drawn as velocity-stretched additive
///    billboards. Custom [ParticleModule]s add the edge repulsion, the
///    cooling color ramp / glitter flicker, and the afterglow emission.
///  * Trails: every spark drops short-lived, fading dots along its path into a
///    second particle system, so a moving spark leaves a comet tail.
///  * Glow: the scene's built-in bloom, fed by HDR spark colors.
///
/// The world is the z = 0 plane seen through an orthographic camera that is two
/// units tall, so the screen edges sit at y = +-1 and x = +-aspect.
class SparklerExperiment extends LabExperiment {
  const SparklerExperiment();

  @override
  String get name => 'Scene: sparkler';

  @override
  String get description =>
      'flutter_scene particles. Press to throw sparks from the pointer; they '
      'are pushed away from the screen edges and leave fading trails, with '
      'bloom on top.';

  @override
  List<LabParam> get params => const [
    FloatParam('rate', 'Sparks per second', min: 50, max: 2500, initial: 700),
    FloatParam('speed', 'Spark speed', min: 0.2, max: 4, initial: 1.4),
    FloatParam('life', 'Spark life (s)', min: 0.2, max: 3, initial: 1.1),
    FloatParam('size', 'Spark size', min: 0.004, max: 0.06, initial: 0.018),
    FloatParam('stretch', 'Streak length', min: 0, max: 0.15, initial: 0.04),
    FloatParam('gravity', 'Gravity', min: 0, max: 3, initial: 0.7),
    FloatParam('drag', 'Air drag', min: 0, max: 5, initial: 1.6),
    FloatParam('edgeForce', 'Edge repulsion', min: 0, max: 40, initial: 18),
    FloatParam('edgeMargin', 'Edge reach', min: 0.05, max: 0.8, initial: 0.3),
    FloatParam('trail', 'Trail density', min: 0, max: 1, initial: 0.5),
    FloatParam(
      'trailLife',
      'Trail length (s)',
      min: 0.05,
      max: 1.2,
      initial: 0.4,
    ),
    FloatParam('brightness', 'Brightness', min: 0.5, max: 10, initial: 3),
    FloatParam('bloom', 'Bloom', min: 0, max: 1.5, initial: 0.5),
    FloatParam('threshold', 'Bloom threshold', min: 0, max: 3, initial: 0.8),
    BoolParam('hover', 'Emit on hover'),
    ColorParam('core', 'Hot color', initial: Color(0xFFFFF4D6)),
    ColorParam('ember', 'Cool color', initial: Color(0xFFFF6A1A)),
  ];

  @override
  Widget buildView(BuildContext context, LabContext lab) =>
      _SparklerView(key: const ValueKey('sparkler'), lab: lab);
}

/// sRGB [Color] to a linear-light RGB vector.
vm.Vector3 _linear(Color c) => vm.Vector3(
  math.pow(c.r, 2.2).toDouble(),
  math.pow(c.g, 2.2).toDouble(),
  math.pow(c.b, 2.2).toDouble(),
);

/// Spawns every particle at [origin], heading in a random direction in the
/// z = 0 plane. The system scales the unit direction by its start speed.
class _SparklerShape extends EmitterShape {
  _SparklerShape();

  final vm.Vector3 origin = vm.Vector3.zero();

  @override
  void sample(ParticleStorage s, int i) {
    final angle = s.randomFor(i, 20) * 2 * math.pi;
    s.posX[i] = origin.x;
    s.posY[i] = origin.y;
    s.posZ[i] = 0;
    s.velX[i] = math.cos(angle);
    s.velY[i] = math.sin(angle);
    s.velZ[i] = 0;
  }
}

/// Pushes particles back from the screen edges.
///
/// Within [margin] of an edge a particle feels an inward acceleration that
/// grows quadratically toward the edge, so fast sparks slow, turn and drift
/// away instead of bouncing. A hard reflect at the edge itself is a safety net
/// for the rare spark that is fast enough to get through anyway.
class _EdgeRepulsion extends ParticleModule {
  double halfWidth = 1;
  double halfHeight = 1;
  double margin = 0.3;
  double strength = 18;

  @override
  void update(ParticleStorage s, double dt) {
    final n = s.aliveCount;
    for (var i = 0; i < n; i++) {
      var ax = 0.0, ay = 0.0;

      final right = halfWidth - s.posX[i];
      final left = s.posX[i] + halfWidth;
      final top = halfHeight - s.posY[i];
      final bottom = s.posY[i] + halfHeight;

      if (right < margin) ax -= _push(right);
      if (left < margin) ax += _push(left);
      if (top < margin) ay -= _push(top);
      if (bottom < margin) ay += _push(bottom);

      s.velX[i] += ax * dt;
      s.velY[i] += ay * dt;

      // Safety net: never leave the screen.
      if (right < 0) {
        s.posX[i] = halfWidth;
        s.velX[i] = -s.velX[i].abs() * 0.5;
      } else if (left < 0) {
        s.posX[i] = -halfWidth;
        s.velX[i] = s.velX[i].abs() * 0.5;
      }
      if (top < 0) {
        s.posY[i] = halfHeight;
        s.velY[i] = -s.velY[i].abs() * 0.5;
      } else if (bottom < 0) {
        s.posY[i] = -halfHeight;
        s.velY[i] = s.velY[i].abs() * 0.5;
      }
    }
  }

  double _push(double distance) {
    final t = ((margin - distance) / margin).clamp(0.0, 1.5);
    return strength * t * t;
  }
}

/// Cooling color ramp (hot core to ember to nothing), glitter flicker and
/// shrinking size, all as a function of the spark's age.
class _SparkLook extends ParticleModule {
  vm.Vector3 core = vm.Vector3(1, 1, 1);
  vm.Vector3 ember = vm.Vector3(1, 0.3, 0.05);
  double brightness = 3;

  @override
  void update(ParticleStorage s, double dt) {
    final n = s.aliveCount;
    for (var i = 0; i < n; i++) {
      final life = s.lifetime[i];
      final t = life > 0 ? (s.age[i] / life).clamp(0.0, 1.0) : 1.0;

      // Glitter: each spark pulses at its own phase.
      final flicker = 0.7 + 0.3 * math.sin(s.age[i] * 48 + s.random01[i] * 100);
      final fade = (1 - t) * (1 - t);
      final k = brightness * fade * flicker;

      final heat = (1 - t * 1.6).clamp(0.0, 1.0); // white-hot only when young
      s.colorR[i] = (ember.x + (core.x - ember.x) * heat) * k;
      s.colorG[i] = (ember.y + (core.y - ember.y) * heat) * k;
      s.colorB[i] = (ember.z + (core.z - ember.z) * heat) * k;
      s.colorA[i] = fade;
      s.size[i] = s.baseSize[i] * (1 - 0.6 * t);
    }
  }
}

/// Drops afterglow dots into [trails] along every live spark's path.
///
/// Runs once per fixed step, after [_SparkLook] so the dots inherit the
/// spark's current color. The trail system itself has no spawner of its own.
class _TrailSource extends ParticleModule {
  _TrailSource(this.trails);

  final ParticleStorage trails;
  final math.Random _random = math.Random(7);

  /// Probability per spark per step of leaving a dot (0..1).
  double density = 0.5;
  double trailLife = 0.4;

  @override
  void update(ParticleStorage s, double dt) {
    if (density <= 0) return;
    final n = s.aliveCount;
    for (var i = 0; i < n; i++) {
      if (_random.nextDouble() > density) continue;
      final j = trails.spawn();
      if (j < 0) return; // pool full

      trails.posX[j] = s.posX[i];
      trails.posY[j] = s.posY[i];
      trails.posZ[j] = s.posZ[i];
      trails.velX[j] = 0;
      trails.velY[j] = 0;
      trails.velZ[j] = 0;
      trails.age[j] = 0;
      trails.lifetime[j] = trailLife * (0.5 + 0.5 * _random.nextDouble());
      trails.random01[j] = _random.nextDouble();
      trails.rotation[j] = 0;
      trails.angularVelocity[j] = 0;
      trails.frame[j] = 0;
      final size = s.size[i] * 0.8;
      trails.size[j] = size;
      trails.baseSize[j] = size;
      trails.colorR[j] = s.colorR[i] * 0.5;
      trails.colorG[j] = s.colorG[i] * 0.5;
      trails.colorB[j] = s.colorB[i] * 0.5;
      trails.colorA[j] = s.colorA[i];
    }
  }
}

/// Fades and shrinks afterglow dots toward the end of their life.
class _TrailFade extends ParticleModule {
  @override
  void update(ParticleStorage s, double dt) {
    final n = s.aliveCount;
    for (var i = 0; i < n; i++) {
      final life = s.lifetime[i];
      // Exponential-ish decay that lands near zero by the end of life.
      final decay = math.max(0.0, 1 - 5.0 * dt / life);
      s.colorR[i] *= decay;
      s.colorG[i] *= decay;
      s.colorB[i] *= decay;
      final t = life > 0 ? (s.age[i] / life).clamp(0.0, 1.0) : 1.0;
      s.size[i] = s.baseSize[i] * (1 - 0.7 * t);
    }
  }
}

class _SparklerView extends StatefulWidget {
  const _SparklerView({super.key, required this.lab});

  final LabContext lab;

  @override
  State<_SparklerView> createState() => _SparklerViewState();
}

class _SparklerViewState extends State<_SparklerView> {
  static const String _errorKey = 'scene:sparkler';

  /// +1 or -1: whether screen-right is world +X or -X for this camera setup.
  static const double _screenRightSign = 1;

  /// Seconds of extra-dense emission left after a press, for the initial puff.
  static const double _burstSeconds = 0.08;
  static const double _burstRate = 3000;

  final Scene _scene = Scene();
  final OrthographicCamera _camera = OrthographicCamera(
    projection: OrthographicProjection(size: const OrthographicSize.height(2)),
    position: vm.Vector3(0, 0, -5),
    target: vm.Vector3.zero(),
  );

  final _SparklerShape _shape = _SparklerShape();
  final _EdgeRepulsion _edges = _EdgeRepulsion();
  final _SparkLook _look = _SparkLook();
  final _TrailFade _trailFade = _TrailFade();

  late final ParticleSystem _sparks;
  late final ParticleSystem _trails;
  late final _TrailSource _trailSource;
  ParticleEmitterComponent? _sparkEmitter;

  bool _ready = false;
  bool _wasPressed = false;
  double _burst = 0;
  double _aspect = 1;

  @override
  void initState() {
    super.initState();
    Scene.initializeStaticResources().then((_) {
      try {
        _build();
        widget.lab.errors.clear(_errorKey);
      } catch (e) {
        widget.lab.errors.report(_errorKey, '$e');
      }
      if (mounted) setState(() {});
    });
  }

  void _build() {
    _trails = ParticleSystem(
      maxParticles: 24000,
      shape: PointEmitterShape(),
      spawner: Spawner(rate: 0),
      modules: [_trailFade],
    );
    _trailSource = _TrailSource(_trails.storage);

    _sparks = ParticleSystem(
      maxParticles: 3000,
      shape: _shape,
      spawner: Spawner(rate: 0),
      modules: [_edges, LinearDragModule(1.6), _look, _trailSource],
      gravity: vm.Vector3(0, -0.7, 0),
    );

    final sparkMaterial = SpriteMaterial(colorTexture: _dotTexture())
      ..blendMode = SpriteBlendMode.additive;
    final trailMaterial = SpriteMaterial(colorTexture: _dotTexture())
      ..blendMode = SpriteBlendMode.additive;

    // Trails first so sparks draw on top.
    _scene.add(
      Node()..addComponent(
        ParticleEmitterComponent(system: _trails, material: trailMaterial),
      ),
    );

    final sparkEmitter = ParticleEmitterComponent(
      system: _sparks,
      material: sparkMaterial,
    )..facing = BillboardFacing.velocityStretched;
    _sparkEmitter = sparkEmitter;
    _scene.add(Node()..addComponent(sparkEmitter));

    // An opaque background is required: additive sprites write alpha 0, and
    // the resolve pass multiplies the color by the pixel's alpha, so over the
    // default transparent clear they would be invisible.
    _scene.skybox = Skybox(
      GradientSkySource(
        zenithColor: vm.Vector3(0.002, 0.004, 0.012),
        horizonColor: vm.Vector3(0.010, 0.016, 0.040),
        groundColor: vm.Vector3(0.010, 0.016, 0.040),
        sunColor: vm.Vector3.zero(),
      ),
    );
    _scene.postProcess.bloom.enabled = true;
  }

  /// A soft round dot, white with a quadratic falloff. Premultiplied so it
  /// works whichever way the sprite shader treats alpha.
  Texture2D _dotTexture() {
    const size = 64;
    final pixels = Uint8List(size * size * 4);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final dx = (x + 0.5) / size * 2 - 1;
        final dy = (y + 0.5) / size * 2 - 1;
        final r = math.sqrt(dx * dx + dy * dy);
        final a = (1 - r).clamp(0.0, 1.0);
        final v = (a * a * 255).round();
        final o = (y * size + x) * 4;
        pixels[o] = v;
        pixels[o + 1] = v;
        pixels[o + 2] = v;
        pixels[o + 3] = v;
      }
    }
    return Texture2D.fromPixels(pixels, size, size);
  }

  @override
  void dispose() {
    _scene.dispose();
    super.dispose();
  }

  /// Copies the panel values into the particle systems, once per frame.
  void _onTick(double dt) {
    final emitter = _sparkEmitter;
    if (!_ready || emitter == null) return;
    final v = widget.lab.values;

    final speed = v.getFloat('speed');
    final size = v.getFloat('size');
    _sparks.lifetime = UniformFloat(
      v.getFloat('life') * 0.5,
      v.getFloat('life'),
    );
    _sparks.startSpeed = UniformFloat(speed * 0.25, speed);
    _sparks.startSize = UniformFloat(size * 0.5, size);
    _sparks.gravity.setValues(0, -v.getFloat('gravity'), 0);
    (_sparks.modules[1] as LinearDragModule).coefficient = v.getFloat('drag');
    emitter.velocityStretch = v.getFloat('stretch');

    _edges
      ..halfWidth = _aspect
      ..halfHeight = 1
      ..margin = v.getFloat('edgeMargin')
      ..strength = v.getFloat('edgeForce');
    _look
      ..core = _linear(v.getColor('core'))
      ..ember = _linear(v.getColor('ember'))
      ..brightness = v.getFloat('brightness');
    _trailSource
      ..density = v.getFloat('trail')
      ..trailLife = v.getFloat('trailLife');

    final bloom = _scene.postProcess.bloom;
    bloom.enabled = v.getFloat('bloom') > 0;
    bloom.intensity = v.getFloat('bloom');
    bloom.threshold = v.getFloat('threshold');

    // Pointer to world space.
    final mouse = widget.lab.mouse.value;
    _shape.origin
      ..x = (mouse.uv.dx * 2 - 1) * _aspect * _screenRightSign
      ..y = 1 - mouse.uv.dy * 2;

    final emitting = mouse.pressed || v.getBool('hover');
    if (mouse.pressed && !_wasPressed) _burst = _burstSeconds;
    _wasPressed = mouse.pressed;
    _burst = math.max(0, _burst - dt);

    _sparks.spawner.rate =
        (emitting ? v.getFloat('rate') : 0) + (_burst > 0 ? _burstRate : 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      // Set after the first successful build.
      _ready = _sparkEmitter != null;
    }
    if (_sparkEmitter == null) {
      return const SizedBox.expand(
        child: Center(child: Text('Loading scene...')),
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          radius: 1.1,
          colors: [Color(0xFF0B1020), Color(0xFF020308)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxHeight > 0) {
            _aspect = constraints.maxWidth / constraints.maxHeight;
          }
          return SceneView(
            _scene,
            camera: _camera,
            onTick: (elapsed, dt) => _onTick(dt),
          );
        },
      ),
    );
  }
}
