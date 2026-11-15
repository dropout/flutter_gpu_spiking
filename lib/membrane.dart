import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'app/color_swatch_row.dart';
import 'app/controls.dart';
import 'app/idea_view.dart';
import 'app/orbit_camera.dart';
import 'app/scene_math.dart';

/// A vibrating square membrane, clamped at its edges.
///
/// The membrane is a lattice of coupled oscillators: every node is pulled
/// towards the average of its four neighbours. That is the 2D wave equation,
/// stepped with a leapfrog scheme,
///
///     uₙ₊₁ = uₙ + (1−d)(uₙ − uₙ₋₁) + C²·(Σneighbours − 4uₙ)
///
/// where C is the Courant number (wave speed per step) and d is the damping.
/// Tap the membrane to pluck it, excite a single normal mode (n, m) to watch a
/// pure standing wave, or switch on the driver and sweep its frequency to find
/// the resonances.
///
/// The nodes are one [InstancedMesh] of cubes, like the disco floor.
class MembranePage extends StatelessWidget {
  const MembranePage({super.key});

  @override
  Widget build(BuildContext context) => IdeaView(
    create: (scene, _) => _Membrane(scene),
    camera: const CameraPose(azimuth: 45, elevation: 40, distance: 12, fov: 40),
    background: (const Color(0xFF0D2430), const Color(0xFF02070B)),
  );
}

class _Membrane extends Idea {
  _Membrane(Scene scene) {
    scene.add(Node()..addComponent(InstancedMeshComponent(_cubes)));
    _allocate(nodes.value);
    _exciteMode();
  }

  /// Edge length of the membrane in world units.
  static const double side = 8;

  /// Simulation steps per second of simulated time at time scale 1.
  static const double stepsPerSecond = 240;
  static const double _dt = 1 / stepsPerSecond;

  /// Cap on steps per frame, so a slow frame cannot snowball.
  static const int _maxStepsPerFrame = 16;

  /// Neutral color at rest, linear RGBA.
  static final _rest = vm.Vector4(0.05, 0.09, 0.16, 1);

  /// Normal mode used by "Excite mode" and the driver's tuning.
  final modeN = IntKnob('n', 2, min: 1, max: 10);
  final modeM = IntKnob('m', 3, min: 1, max: 10);

  /// Size of a pluck, in world units and displacement.
  final pluckRadius = FloatKnob('Radius', 0.6, min: 0.2, max: 2, digits: 2);
  final pluckAmplitude = FloatKnob('Amplitude', 1, min: -2, max: 2, digits: 2);

  /// A sinusoidal force on one node, at [driveHz] in simulation time.
  final drive = BoolKnob('Drive a point', false);
  final driveHz = FloatKnob('Frequency (Hz)', 3, min: 0.2, max: 30, digits: 2);
  final driveAmplitude = FloatKnob('Force', 0.01, min: 0.001, max: 0.05);

  /// Courant number: how far a wave travels per step, in grid cells. The 2D
  /// scheme is stable up to 1/√2, so the slider stops just short of it.
  final courant = FloatKnob(
    'Wave speed (Courant)',
    0.18,
    min: 0.1,
    max: 0.7,
    digits: 2,
  );

  /// Fraction of velocity lost per step.
  final damping = FloatKnob('Damping', 0.01, min: 0, max: 0.01, digits: 4);

  /// Simulation speed relative to real time.
  final timeScale = FloatKnob('Time scale', 0.1, min: 0.1, max: 3, digits: 2);

  /// Nodes along one edge of the membrane.
  final nodes = IntKnob('Nodes per edge', 48, min: 16, max: 96, step: 8);

  /// World units of height per unit of displacement.
  final gain = FloatKnob('Height gain', 0.8, min: 0.1, max: 3, digits: 2);

  static const _cyan = Color.from(alpha: 1, red: 0, green: 0.8, blue: 1);
  static const _pink = Color.from(alpha: 1, red: 1, green: 0.1, blue: 0.5);
  static const _swatches = [_cyan, _pink, ...ColorSwatchRow.defaultSwatches];
  final crestColor = ColorKnob('Crest', _cyan, swatches: _swatches);
  final troughColor = ColorKnob('Trough', _pink, swatches: _swatches);

  double get _modeHz => frequencyHz(modeN.value, modeM.value);

  @override
  late final List<Control> controls = [
    Section('Normal mode'),
    modeN,
    modeM,
    Note(() => 'Natural frequency: ${_modeHz.toStringAsFixed(2)} Hz'),
    Buttons({'Excite mode': _exciteMode, 'Still': _clear}),
    Section('Pluck (tap the membrane)'),
    pluckRadius,
    pluckAmplitude,
    Section('Driver'),
    drive,
    driveHz,
    driveAmplitude,
    Buttons({'Tune to mode': () => driveHz.value = _modeHz}),
    Section('Medium'),
    courant,
    damping,
    timeScale,
    nodes,
    gain,
    Section('Colors'),
    crestColor,
    troughColor,
  ];

  @override
  Map<String, String> get stats => {
    'Nodes': '${_size * _size}',
    'Sim time': '${(_stepCount * _dt).toStringAsFixed(1)} s',
    'Peak': _peak.toStringAsFixed(3),
    'Mode': '(${modeN.value}, ${modeM.value}) ${_modeHz.toStringAsFixed(2)} Hz',
    if (drive.value) 'Driver': '${driveHz.value.toStringAsFixed(2)} Hz',
  };

  final InstancedMesh _cubes = InstancedMesh(
    geometry: CuboidGeometry(vm.Vector3(1, 0.25, 1)),
    material: PhysicallyBasedMaterial()
      ..metallicFactor = 0.2
      ..roughnessFactor = 0.4,
  );

  int _size = 0;
  Float64List _u = Float64List(0);
  Float64List _prev = Float64List(0);
  Float64List _next = Float64List(0);

  double _peak = 0;
  double _stepAccumulator = 0;
  int _stepCount = 0;

  double get _pitch => side / (_size - 1);

  void _allocate(int n) {
    _size = n;
    _u = Float64List(n * n);
    _prev = Float64List(n * n);
    _next = Float64List(n * n);
    _stepCount = 0;
    _stepAccumulator = 0;
    _cubes.clearInstances();
    final identity = vm.Matrix4.identity();
    for (var i = 0; i < n * n; i++) {
      _cubes.addInstance(identity);
    }
  }

  /// Stills the membrane.
  void _clear() {
    _u.fillRange(0, _u.length, 0);
    _prev.fillRange(0, _prev.length, 0);
    _stepCount = 0;
  }

  /// Plucks the membrane where the tap's ray meets its resting plane (y = 0).
  @override
  void onTap(vm.Ray ray) {
    final hit = hitPlane(ray, vm.Vector3(0, 1, 0));
    if (hit != null) _pluck(hit.x, hit.z);
  }

  /// Displaces the membrane in a Gaussian bump around world point (x, z) and
  /// lets go.
  void _pluck(double x, double z) {
    final half = side / 2;
    if (x.abs() > half || z.abs() > half) return;
    final sigma = pluckRadius.value;
    final pitch = _pitch;
    for (var j = 1; j < _size - 1; j++) {
      for (var i = 1; i < _size - 1; i++) {
        final dx = (i * pitch - half) - x;
        final dz = (j * pitch - half) - z;
        final bump =
            pluckAmplitude.value *
            math.exp(-(dx * dx + dz * dz) / (2 * sigma * sigma));
        _u[j * _size + i] += bump;
        _prev[j * _size + i] += bump; // released from rest
      }
    }
  }

  /// Resets the membrane to a pure standing wave in mode (n, m).
  void _exciteMode() {
    final n = modeN.value;
    final m = modeM.value;
    final omega = _omega(n, m);
    final last = _size - 1;
    for (var j = 0; j < _size; j++) {
      for (var i = 0; i < _size; i++) {
        final shape =
            math.sin(n * math.pi * i / last) * math.sin(m * math.pi * j / last);
        _u[j * _size + i] = shape;
        // One step back along the exact discrete solution, so the mode starts
        // as an undisturbed standing wave.
        _prev[j * _size + i] = shape * math.cos(omega * _dt);
      }
    }
    _stepCount = 0;
  }

  /// Angular frequency of mode (n, m) on this lattice, in rad/s, including the
  /// slight slowing of short waves that the discretisation causes.
  double _omega(int n, int m) {
    final last = _size - 1;
    final sn = math.sin(n * math.pi / (2 * last));
    final sm = math.sin(m * math.pi / (2 * last));
    final s = (courant.value * math.sqrt(sn * sn + sm * sm)).clamp(0.0, 1.0);
    return 2 / _dt * math.asin(s);
  }

  /// Natural frequency of mode (n, m) in Hz of simulation time.
  double frequencyHz(int n, int m) => _omega(n, m) / (2 * math.pi);

  void _step() {
    final n = _size;
    final c2 = courant.value * courant.value;
    final keep = 1 - damping.value;
    final u = _u;
    final prev = _prev;
    final next = _next;

    for (var j = 1; j < n - 1; j++) {
      for (var i = 1; i < n - 1; i++) {
        final k = j * n + i;
        final lap = u[k - 1] + u[k + 1] + u[k - n] + u[k + n] - 4 * u[k];
        next[k] = u[k] + keep * (u[k] - prev[k]) + c2 * lap;
      }
    }
    // The edges stay clamped at zero. Next has not touched them.

    if (drive.value) {
      final k = (n * 0.43).round() * n + (n * 0.31).round();
      next[k] +=
          driveAmplitude.value *
          math.sin(2 * math.pi * driveHz.value * _stepCount * _dt);
    }

    _prev = u;
    _u = next;
    _next = prev;
    _stepCount++;
  }

  @override
  void update(double dt) {
    if (nodes.value != _size) {
      _allocate(nodes.value);
      _exciteMode();
    }

    _stepAccumulator += dt * timeScale.value * stepsPerSecond;
    var steps = _stepAccumulator.floor().clamp(0, _maxStepsPerFrame);
    _stepAccumulator -= _stepAccumulator.floorToDouble();
    while (steps-- > 0) {
      _step();
    }

    final n = _size;
    final pitch = _pitch;
    final half = side / 2;
    final footprint = pitch * 0.92;
    final color = vm.Vector4.zero();
    var maxAbs = 0.0;

    _cubes.updateInstanceTransforms((transforms) {
      for (var j = 0; j < n; j++) {
        for (var i = 0; i < n; i++) {
          final k = j * n + i;
          final u = _u[k];
          maxAbs = math.max(maxAbs, u.abs());
          transforms[k].setScaleTranslation(
            footprint,
            1,
            footprint,
            i * pitch - half,
            u * gain.value,
            j * pitch - half,
          );

          // Tinted towards the crest or trough color by the displacement.
          final t = (u.abs() * 1.5).clamp(0.0, 1.0);
          final tint = u >= 0 ? crestColor.value : troughColor.value;
          color.setValues(
            _rest.x + (tint.r - _rest.x) * t,
            _rest.y + (tint.g - _rest.y) * t,
            _rest.z + (tint.b - _rest.z) * t,
            1,
          );
          _cubes.setInstanceColor(k, color);
        }
      }
    }, recomputeWinding: false);
    _peak = maxAbs;
  }
}
