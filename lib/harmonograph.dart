import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/material.dart' as material show Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'disco_floor.dart' show CameraParams;

/// A 3D harmonograph: every axis is the sum of two damped sine waves,
///
///     x(t) = ½·(sin(a·ωt + φ₁) + sin((a + δ)·ωt + φ₂))·e^(−d·t)
///
/// and likewise for y and z with their own frequency ratios. When the ratios
/// are whole numbers the figure is a closed Lissajous knot; the small detune δ
/// makes it precess, and the damping makes it spiral in towards the origin.
///
/// The pen's trail is a fixed number of spheres in one [InstancedMesh]. Each
/// frame the trail is evaluated straight from the formula at times behind the
/// current one, so there is no history to store.
class HarmonographPage extends StatefulWidget {
  const HarmonographPage({super.key});

  @override
  State<HarmonographPage> createState() => _HarmonographPageState();
}

class _HarmonographPageState extends State<HarmonographPage> {
  final Scene scene = Scene();
  final HarmonographParams params = HarmonographParams();
  final CameraParams camera = CameraParams()
    ..set(azimuth: 30, elevation: 25, distance: 9, fov: 45);
  final ValueNotifier<HarmonographStats> stats = ValueNotifier(
    const HarmonographStats(),
  );
  _Pen? pen;
  bool _panelOpen = false;
  double _lastScale = 1;

  Duration _lastTick = Duration.zero;
  Duration _lastStatsUpdate = Duration.zero;
  int _framesSinceStats = 0;

  @override
  void initState() {
    super.initState();
    Scene.initializeStaticResources().then((_) {
      if (!mounted) return;
      setState(() => pen = _Pen(scene, params));
    });
  }

  @override
  void dispose() {
    params.dispose();
    camera.dispose();
    stats.dispose();
    scene.dispose();
    super.dispose();
  }

  void _onTick(_Pen pen, Duration elapsed) {
    final dt = _seconds(elapsed - _lastTick).clamp(0.0, 1 / 20);
    _lastTick = elapsed;
    if (params.autoOrbit) {
      camera.set(azimuth: camera.azimuth + dt * params.orbitSpeed);
    }
    pen.update(dt);

    _framesSinceStats++;
    final window = _seconds(elapsed - _lastStatsUpdate);
    if (window >= 0.25) {
      stats.value = HarmonographStats(
        fps: _framesSinceStats / window,
        frameMs: window * 1000 / _framesSinceStats,
        points: pen.count,
        time: pen.time,
        amplitude: pen.amplitude,
      );
      _lastStatsUpdate = elapsed;
      _framesSinceStats = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pen = this.pen;
    if (pen == null) {
      return const SizedBox.expand(
        child: Center(child: Text('Loading scene...')),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          radius: 1.1,
          colors: [Color(0xFF14102B), Color(0xFF03020A)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                camera.zoomBy(math.exp(event.scrollDelta.dy * 0.001));
              }
            },
            child: GestureDetector(
              onScaleStart: (_) => _lastScale = 1,
              onScaleUpdate: (details) {
                camera.orbitBy(details.focalPointDelta);
                if (details.pointerCount > 1) {
                  camera.zoomBy(_lastScale / details.scale);
                  _lastScale = details.scale;
                }
              },
              child: SceneView(
                scene,
                onTick: (elapsed, _) => _onTick(pen, elapsed),
                cameraBuilder: (elapsed) => camera.build(),
              ),
            ),
          ),
          material.Material(
            type: MaterialType.transparency,
            child: SafeArea(
              child: Stack(
                children: [
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _ControlPanel(
                      params: params,
                      pen: pen,
                      camera: camera,
                      open: _panelOpen,
                      onToggle: () => setState(() => _panelOpen = !_panelOpen),
                    ),
                  ),
                  if (!_panelOpen)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: _StatsOverlay(params: params, stats: stats),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tweakable parameters of the experiment.
class HarmonographParams extends ChangeNotifier {
  /// Frequency ratios of the x, y and z axes.
  int ratioX = 3;
  int ratioY = 2;
  int ratioZ = 5;

  /// Offset, in ratio units, of each axis's second oscillator. Small values
  /// make the knot slowly precess.
  double detune = 0.02;

  /// Decay rate in 1/s. At zero the figure never fades.
  double damping = 0.02;

  /// Phases of the two oscillators on each of the three axes.
  List<double> phases = [0, 1.1, 0.4, 2.3, 1.7, 0.2];

  /// Angular speed of the base oscillation, in radians per second.
  double speed = 1.0;

  /// How much history, in seconds of oscillation, the trail spans.
  double trailSeconds = 18;

  /// Number of spheres in the trail.
  int points = 4000;

  /// Sphere radius at the pen, in world units. The tail tapers to nothing.
  double thickness = 0.045;

  /// Hue of the pen, 0..1. The trail cycles through hues behind it.
  double hue = 0.55;
  double hueSpread = 0.35;

  bool autoOrbit = true;
  double orbitSpeed = 8;

  /// Restart the drawing once the figure has decayed, or after
  /// [restartSeconds] when there is no damping.
  bool autoRestart = true;
  double restartSeconds = 120;

  static const int maxRatio = 9;

  void update(void Function() change) {
    change();
    notifyListeners();
  }

  void randomize(math.Random random) => update(() {
    ratioX = 1 + random.nextInt(maxRatio);
    ratioY = 1 + random.nextInt(maxRatio);
    ratioZ = 1 + random.nextInt(maxRatio);
    phases = [for (var i = 0; i < 6; i++) random.nextDouble() * 2 * math.pi];
  });

  void reset() => update(() {
    ratioX = 3;
    ratioY = 2;
    ratioZ = 5;
    detune = 0.02;
    damping = 0.02;
    phases = [0, 1.1, 0.4, 2.3, 1.7, 0.2];
    speed = 1.0;
    trailSeconds = 18;
    points = 4000;
    thickness = 0.045;
    hue = 0.55;
    hueSpread = 0.35;
    autoOrbit = true;
    orbitSpeed = 8;
    autoRestart = true;
    restartSeconds = 120;
  });
}

class HarmonographStats {
  const HarmonographStats({
    this.fps = 0,
    this.frameMs = 0,
    this.points = 0,
    this.time = 0,
    this.amplitude = 1,
  });

  final double fps;
  final double frameMs;
  final int points;
  final double time;

  /// Envelope of the damping, 1 at the start and falling towards 0.
  final double amplitude;
}

double _seconds(Duration d) => d.inMicroseconds / 1e6;

/// Owns the trail spheres and advances the pen each frame.
class _Pen {
  _Pen(Scene scene, this.params) {
    _trail = InstancedMesh(
      geometry: SphereGeometry(radius: 0.5, segments: 8, rings: 5),
      material: PhysicallyBasedMaterial()
        ..metallicFactor = 0.2
        ..roughnessFactor = 0.4,
    );
    _resize(params.points);
    scene.add(Node()..addComponent(InstancedMeshComponent(_trail)));
  }

  /// World-space half-extent of the figure at full amplitude.
  static const double _extent = 2.6;

  final HarmonographParams params;
  late final InstancedMesh _trail;
  int count = 0;

  /// Time since the drawing started, in seconds. Accumulated rather than
  /// derived from the clock, so changing the speed slider never jumps.
  double time = 0;
  double amplitude = 1;

  void _resize(int n) {
    count = n;
    _trail.clearInstances();
    final identity = vm.Matrix4.identity();
    for (var i = 0; i < n; i++) {
      _trail.addInstance(identity);
    }
  }

  /// Starts the drawing again from the origin.
  void restart() => time = 0;

  void update(double dt) {
    if (params.points != count) _resize(params.points);
    time += dt * params.speed;

    final damp = params.damping;
    if (params.autoRestart) {
      final finished = damp > 0
          ? math.exp(-damp * time) < 0.03
          : time > params.restartSeconds;
      if (finished) time = 0;
    }
    amplitude = math.exp(-damp * time);

    final w = [
      params.ratioX.toDouble(),
      params.ratioY.toDouble(),
      params.ratioZ.toDouble(),
    ];
    final phases = params.phases;
    final detune = params.detune;
    final step = params.trailSeconds / count;
    final tmp = vm.Vector4.zero();
    final color = vm.Vector4.zero();
    final position = [0.0, 0.0, 0.0];

    _trail.updateInstanceTransforms((transforms) {
      for (var k = 0; k < count; k++) {
        // The head of the trail is k = 0; later spheres are further back.
        final t = time - k * step;
        final age = k / count;

        if (t < 0) {
          // The pen has not got this far yet, so hide the sphere.
          transforms[k].setZero();
          continue;
        }

        final envelope = math.exp(-damp * t);
        for (var axis = 0; axis < 3; axis++) {
          final f = w[axis];
          position[axis] =
              _extent *
              envelope *
              0.5 *
              (math.sin(f * t + phases[axis * 2]) +
                  math.sin((f + detune) * t + phases[axis * 2 + 1]));
        }

        // Taper the tail so the trail reads as a ribbon fading out.
        final radius = params.thickness * 2 * (1 - age) * (1 - age * 0.3);
        transforms[k].setValues(
          radius,
          0,
          0,
          0,
          0,
          radius,
          0,
          0,
          0,
          0,
          radius,
          0,
          position[0],
          position[1],
          position[2],
          1,
        );

        _hsv(params.hue + age * params.hueSpread, 0.75, 1.0 - 0.6 * age, tmp);
        color.setFrom(tmp);
        _trail.setInstanceColor(k, color);
      }
    }, recomputeWinding: false);
  }
}

/// Writes the linear RGBA equivalent of an HSV color to [out].
void _hsv(double hue, double saturation, double value, vm.Vector4 out) {
  final h = (hue - hue.floorToDouble()) * 6.0;
  double channel(double offset) {
    final k = (offset + h) % 6.0;
    final c =
        1.0 - saturation * math.max(0.0, math.min(1.0, math.min(k, 4.0 - k)));
    // Approximate sRGB to linear, so the hues look as they would in Flutter.
    return math.pow(c, 2.2) * value;
  }

  out.setValues(channel(5), channel(3), channel(1), 1.0);
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.params,
    required this.pen,
    required this.camera,
    required this.open,
    required this.onToggle,
  });

  final HarmonographParams params;
  final _Pen pen;
  final CameraParams camera;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          tooltip: open ? 'Hide controls' : 'Show controls',
          onPressed: onToggle,
          icon: Icon(open ? Icons.close : Icons.tune),
        ),
        if (open) ...[
          const SizedBox(height: 8),
          Container(
            width: 280,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height - 120,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListenableBuilder(
              listenable: Listenable.merge([params, camera]),
              builder: (context, _) => SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _header('Oscillators'),
                    _ratio('X ratio', params.ratioX, (v) => params.ratioX = v),
                    _ratio('Y ratio', params.ratioY, (v) => params.ratioY = v),
                    _ratio('Z ratio', params.ratioZ, (v) => params.ratioZ = v),
                    _slider(
                      'Detune',
                      params.detune,
                      0,
                      0.2,
                      (v) => params.update(() => params.detune = v),
                    ),
                    _slider(
                      'Damping',
                      params.damping,
                      0,
                      0.2,
                      (v) => params.update(() => params.damping = v),
                    ),
                    _slider(
                      'Speed',
                      params.speed,
                      0,
                      5,
                      (v) => params.update(() => params.speed = v),
                      digits: 2,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => params.randomize(math.Random()),
                          child: const Text('Randomize'),
                        ),
                        TextButton(
                          onPressed: pen.restart,
                          child: const Text('Redraw'),
                        ),
                      ],
                    ),
                    _switch(
                      'Restart when faded',
                      params.autoRestart,
                      (v) => params.update(() => params.autoRestart = v),
                    ),
                    _header('Trail'),
                    _slider(
                      'Length (s)',
                      params.trailSeconds,
                      1,
                      60,
                      (v) => params.update(() => params.trailSeconds = v),
                      digits: 1,
                    ),
                    _slider(
                      'Points',
                      params.points.toDouble(),
                      500,
                      12000,
                      (v) => params.update(
                        () => params.points = (v / 500).round() * 500,
                      ),
                      divisions: 23,
                      digits: 0,
                    ),
                    _slider(
                      'Thickness',
                      params.thickness,
                      0.01,
                      0.12,
                      (v) => params.update(() => params.thickness = v),
                    ),
                    _slider(
                      'Hue',
                      params.hue,
                      0,
                      1,
                      (v) => params.update(() => params.hue = v),
                      digits: 2,
                    ),
                    _slider(
                      'Hue spread',
                      params.hueSpread,
                      0,
                      1,
                      (v) => params.update(() => params.hueSpread = v),
                      digits: 2,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: params.reset,
                        child: const Text('Reset'),
                      ),
                    ),
                    _header('Camera'),
                    _switch(
                      'Auto orbit',
                      params.autoOrbit,
                      (v) => params.update(() => params.autoOrbit = v),
                    ),
                    _slider(
                      'Elevation',
                      camera.elevation,
                      CameraParams.minElevation,
                      CameraParams.maxElevation,
                      (v) => camera.set(elevation: v),
                      digits: 0,
                    ),
                    _slider(
                      'Distance',
                      camera.distance,
                      CameraParams.minDistance,
                      CameraParams.maxDistance,
                      (v) => camera.set(distance: v),
                      digits: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _ratio(String label, int value, void Function(int) set) => _slider(
    label,
    value.toDouble(),
    1,
    HarmonographParams.maxRatio.toDouble(),
    (v) => params.update(() => set(v.round())),
    divisions: HarmonographParams.maxRatio - 1,
    digits: 0,
  );

  Widget _header(String text) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 11,
          letterSpacing: 1.2,
        ),
      ),
    ),
  );

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    int? divisions,
    int digits = 3,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '$label: ${value.toStringAsFixed(digits)}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _StatsOverlay extends StatelessWidget {
  const _StatsOverlay({required this.params, required this.stats});

  final HarmonographParams params;
  final ValueNotifier<HarmonographStats> stats;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListenableBuilder(
          listenable: Listenable.merge([stats, params]),
          builder: (context, _) {
            final s = stats.value;
            final lines = [
              'FPS        ${s.fps.toStringAsFixed(1)}',
              'Frame      ${s.frameMs.toStringAsFixed(2)} ms',
              'Points     ${s.points}',
              'Ratios     ${params.ratioX}:${params.ratioY}:${params.ratioZ}',
              'Time       ${s.time.toStringAsFixed(1)} s',
              'Amplitude  ${(s.amplitude * 100).toStringAsFixed(0)}%',
            ];
            return Text(
              lines.join('\n'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: 'Menlo',
                fontFamilyFallback: ['Courier', 'monospace'],
                height: 1.3,
              ),
            );
          },
        ),
      ),
    );
  }
}
