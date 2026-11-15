import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/material.dart' as material show Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'disco_floor.dart' show CameraParams;

/// A pendulum wave: a row of pendulums of slightly different lengths, all
/// released together.
///
/// Pendulum i is cut so that it completes (n₀ + i) swings in the cycle time T,
/// which makes its angular frequency ωᵢ = 2π(n₀ + i)/T and its length
/// Lᵢ = g/ωᵢ². Each is a simple harmonic oscillator,
///
///     θᵢ(t) = A·cos(ωᵢ·t)
///
/// so after exactly T they are back in step, and in between they drift through
/// travelling waves, standing waves and apparent chaos.
///
/// That relies on small swings. Switch to the real pendulum, θ'' = −ωᵢ² sin θ,
/// and a pendulum swinging wide takes longer per swing than ωᵢ promises, so the
/// pattern no longer closes: the harmonic approximation shows its limits.
class PendulumWavePage extends StatefulWidget {
  const PendulumWavePage({super.key});

  @override
  State<PendulumWavePage> createState() => _PendulumWavePageState();
}

class _PendulumWavePageState extends State<PendulumWavePage> {
  final Scene scene = Scene();
  final PendulumParams params = PendulumParams();
  final CameraParams camera = CameraParams()
    ..set(azimuth: 25, elevation: 22, distance: 11, fov: 40);
  final ValueNotifier<PendulumStats> stats = ValueNotifier(
    const PendulumStats(),
  );
  _Pendulums? pendulums;
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
      setState(() => pendulums = _Pendulums(scene, params));
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

  void _onTick(_Pendulums p, Duration elapsed) {
    final dt = _seconds(elapsed - _lastTick).clamp(0.0, 1 / 20);
    _lastTick = elapsed;
    p.update(dt);

    _framesSinceStats++;
    final window = _seconds(elapsed - _lastStatsUpdate);
    if (window >= 0.25) {
      stats.value = PendulumStats(
        fps: _framesSinceStats / window,
        frameMs: window * 1000 / _framesSinceStats,
        time: p.time,
        cyclePhase: (p.time / params.cycleSeconds) % 1,
        longest: p.longest,
        shortest: p.shortest,
      );
      _lastStatsUpdate = elapsed;
      _framesSinceStats = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendulums = this.pendulums;
    if (pendulums == null) {
      return const SizedBox.expand(
        child: Center(child: Text('Loading scene...')),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          radius: 1.1,
          colors: [Color(0xFF1A1030), Color(0xFF05030B)],
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
                onTick: (elapsed, _) => _onTick(pendulums, elapsed),
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
                      pendulums: pendulums,
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
class PendulumParams extends ChangeNotifier {
  /// Number of pendulums.
  int count = 16;

  /// Seconds after which the whole row is back in step.
  double cycleSeconds = 60;

  /// Swings the first (longest) pendulum makes per cycle. The rest make one
  /// more each.
  int firstSwings = 20;

  /// Release angle, in degrees.
  double amplitude = 25;

  /// Integrate the real pendulum equation instead of the harmonic one.
  bool nonlinear = false;

  /// Simulation speed relative to real time.
  double timeScale = 1;

  double bobSize = 0.3;
  double hue = 0.55;
  double hueSpread = 0.45;

  static const double gravity = 9.81;

  void update(void Function() change) {
    change();
    notifyListeners();
  }

  void reset() => update(() {
    count = 16;
    cycleSeconds = 60;
    firstSwings = 20;
    amplitude = 25;
    nonlinear = false;
    timeScale = 1;
    bobSize = 0.3;
    hue = 0.55;
    hueSpread = 0.45;
  });
}

class PendulumStats {
  const PendulumStats({
    this.fps = 0,
    this.frameMs = 0,
    this.time = 0,
    this.cyclePhase = 0,
    this.longest = 0,
    this.shortest = 0,
  });

  final double fps;
  final double frameMs;
  final double time;

  /// Where in the cycle the row is, 0 to 1. Back in step at 0.
  final double cyclePhase;
  final double longest;
  final double shortest;
}

double _seconds(Duration d) => d.inMicroseconds / 1e6;

/// The row of pendulums and everything that draws them.
class _Pendulums {
  _Pendulums(Scene scene, this.params) {
    _bobs = InstancedMesh(
      geometry: SphereGeometry(radius: 0.5, segments: 16, rings: 10),
      material: PhysicallyBasedMaterial()
        ..metallicFactor = 0.6
        ..roughnessFactor = 0.25,
    );
    _strings = InstancedMesh(
      geometry: CuboidGeometry(vm.Vector3(1, 1, 1)),
      material: PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(0.75, 0.75, 0.85, 1)
        ..metallicFactor = 0.0
        ..roughnessFactor = 0.6,
    );
    scene.add(Node()..addComponent(InstancedMeshComponent(_bobs)));
    scene.add(Node()..addComponent(InstancedMeshComponent(_strings)));

    _bar = Node(
      mesh: Mesh(
        CuboidGeometry(vm.Vector3(1, 1, 1)),
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(0.15, 0.15, 0.2, 1)
          ..metallicFactor = 0.8
          ..roughnessFactor = 0.35,
      ),
    );
    scene.add(_bar);
    _rebuild();
  }

  /// Height of the pivot bar.
  static const double pivotY = 1.3;
  static const double _substep = 1 / 480;
  static const int _maxSubstepsPerFrame = 64;

  final PendulumParams params;
  late final InstancedMesh _bobs;
  late final InstancedMesh _strings;
  late final Node _bar;

  int _count = 0;
  double _cycle = 0;
  int _firstSwings = 0;
  double _amplitude = 0;
  bool _nonlinear = false;
  double _hue = -1;
  double _hueSpread = -1;

  Float64List _omega = Float64List(0);
  Float64List _length = Float64List(0);
  // State of the real pendulum, used only in nonlinear mode.
  Float64List _theta = Float64List(0);
  Float64List _thetaDot = Float64List(0);

  /// Time since release, in seconds.
  double time = 0;
  double _substepAccumulator = 0;

  double get longest => _length.isEmpty ? 0 : _length.first;
  double get shortest => _length.isEmpty ? 0 : _length.last;

  /// Releases every pendulum again from the starting angle.
  void restart() {
    time = 0;
    _substepAccumulator = 0;
    final a = params.amplitude * math.pi / 180;
    for (var i = 0; i < _count; i++) {
      _theta[i] = a;
      _thetaDot[i] = 0;
    }
  }

  void _rebuild() {
    _count = params.count;
    _cycle = params.cycleSeconds;
    _firstSwings = params.firstSwings;
    _amplitude = params.amplitude;
    _nonlinear = params.nonlinear;

    _omega = Float64List(_count);
    _length = Float64List(_count);
    _theta = Float64List(_count);
    _thetaDot = Float64List(_count);
    for (var i = 0; i < _count; i++) {
      _omega[i] = 2 * math.pi * (_firstSwings + i) / _cycle;
      _length[i] = PendulumParams.gravity / (_omega[i] * _omega[i]);
    }
    restart();

    _bobs.clearInstances();
    _strings.clearInstances();
    final identity = vm.Matrix4.identity();
    for (var i = 0; i < _count; i++) {
      _bobs.addInstance(identity);
      _strings.addInstance(identity);
    }
    _recolor();
  }

  void _recolor() {
    _hue = params.hue;
    _hueSpread = params.hueSpread;
    final color = vm.Vector4.zero();
    for (var i = 0; i < _count; i++) {
      _hsv(
        params.hue + params.hueSpread * i / math.max(1, _count - 1),
        0.8,
        1.0,
        color,
      );
      _bobs.setInstanceColor(i, color);
    }
  }

  double get _spacing => math.min(0.5, 7.0 / _count);

  void update(double dt) {
    if (params.count != _count ||
        params.cycleSeconds != _cycle ||
        params.firstSwings != _firstSwings ||
        params.amplitude != _amplitude ||
        params.nonlinear != _nonlinear) {
      _rebuild();
    } else if (params.hue != _hue || params.hueSpread != _hueSpread) {
      _recolor();
    }

    final step = dt * params.timeScale;
    time += step;
    if (_nonlinear) {
      _substepAccumulator += step / _substep;
      var n = _substepAccumulator.floor().clamp(0, _maxSubstepsPerFrame);
      _substepAccumulator -= _substepAccumulator.floorToDouble();
      while (n-- > 0) {
        _integrate();
      }
    }

    final spacing = _spacing;
    final halfRow = (_count - 1) / 2;
    final amplitude = params.amplitude * math.pi / 180;
    final bob = params.bobSize;

    _bobs.updateInstanceTransforms((b) {
      _strings.updateInstanceTransforms((s) {
        for (var i = 0; i < _count; i++) {
          final theta = _nonlinear
              ? _theta[i]
              : amplitude * math.cos(_omega[i] * time);
          final x = (i - halfRow) * spacing;
          final length = _length[i];
          // The pendulums swing along z, out of the plane of the row.
          final bobY = pivotY - length * math.cos(theta);
          final bobZ = length * math.sin(theta);

          b[i].setValues(
            bob,
            0,
            0,
            0,
            0,
            bob,
            0,
            0,
            0,
            0,
            bob,
            0,
            x,
            bobY,
            bobZ,
            1,
          );
          _string(s[i], x, pivotY, 0, x, bobY, bobZ, 0.012);
        }
      }, recomputeWinding: false);
    }, recomputeWinding: false);

    _bar.localTransform = vm.Matrix4.compose(
      vm.Vector3(0, pivotY, 0),
      vm.Quaternion.identity(),
      vm.Vector3(_count * spacing + 0.4, 0.06, 0.12),
    );
  }

  /// One velocity-Verlet step of θ'' = −ω² sin θ for every pendulum.
  void _integrate() {
    for (var i = 0; i < _count; i++) {
      final w2 = _omega[i] * _omega[i];
      final a0 = -w2 * math.sin(_theta[i]);
      _theta[i] += _thetaDot[i] * _substep + 0.5 * a0 * _substep * _substep;
      final a1 = -w2 * math.sin(_theta[i]);
      _thetaDot[i] += 0.5 * (a0 + a1) * _substep;
    }
  }

  /// Stretches a unit cube into a thin bar from (x0, y0, z0) to (x1, y1, z1).
  /// The strings only ever tilt in the y-z plane, so the bar's cross-section
  /// axes are simple to build.
  static void _string(
    vm.Matrix4 m,
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
    double thickness,
  ) {
    final dy = y1 - y0, dz = z1 - z0;
    final length = math.sqrt(dy * dy + dz * dz);
    if (length < 1e-9) {
      m.setZero();
      return;
    }
    final uy = dy / length, uz = dz / length;
    // The bar's long axis is local x, so rotate it onto (0, uy, uz). The row
    // axis x stays as one cross-section axis and the other is perpendicular
    // to both.
    m.setValues(
      0,
      uy * length,
      uz * length,
      0,
      thickness,
      0,
      0,
      0,
      0,
      uz * thickness,
      -uy * thickness,
      0,
      (x0 + x1) / 2,
      (y0 + y1) / 2,
      (z0 + z1) / 2,
      1,
    );
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
    required this.pendulums,
    required this.camera,
    required this.open,
    required this.onToggle,
  });

  final PendulumParams params;
  final _Pendulums pendulums;
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
                    _header('Pendulums'),
                    _slider(
                      'Count',
                      params.count.toDouble(),
                      4,
                      40,
                      (v) => params.update(() => params.count = v.round()),
                      digits: 0,
                    ),
                    _slider(
                      'Cycle (s)',
                      params.cycleSeconds,
                      10,
                      120,
                      (v) => params.update(() => params.cycleSeconds = v),
                      digits: 0,
                    ),
                    _slider(
                      'Swings of the longest',
                      params.firstSwings.toDouble(),
                      5,
                      50,
                      (v) =>
                          params.update(() => params.firstSwings = v.round()),
                      digits: 0,
                    ),
                    _slider(
                      'Release angle (deg)',
                      params.amplitude,
                      2,
                      80,
                      (v) => params.update(() => params.amplitude = v),
                      digits: 0,
                    ),
                    _switch(
                      'Real pendulum (sin θ)',
                      params.nonlinear,
                      (v) => params.update(() => params.nonlinear = v),
                    ),
                    _slider(
                      'Time scale',
                      params.timeScale,
                      0,
                      6,
                      (v) => params.update(() => params.timeScale = v),
                      digits: 2,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: pendulums.restart,
                        child: const Text('Release again'),
                      ),
                    ),
                    _header('Look'),
                    _slider(
                      'Bob size',
                      params.bobSize,
                      0.1,
                      0.6,
                      (v) => params.update(() => params.bobSize = v),
                      digits: 2,
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
                    _slider(
                      'Azimuth',
                      camera.azimuth,
                      0,
                      360,
                      (v) => camera.set(azimuth: v),
                      digits: 0,
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
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _StatsOverlay extends StatelessWidget {
  const _StatsOverlay({required this.params, required this.stats});

  final PendulumParams params;
  final ValueNotifier<PendulumStats> stats;

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
              'FPS       ${s.fps.toStringAsFixed(1)}',
              'Frame     ${s.frameMs.toStringAsFixed(2)} ms',
              'Pendulums ${params.count}',
              'Model     ${params.nonlinear ? 'real (sin θ)' : 'harmonic'}',
              'Time      ${s.time.toStringAsFixed(1)} s',
              'Cycle     ${(s.cyclePhase * 100).toStringAsFixed(0)}%',
              'Lengths   ${s.longest.toStringAsFixed(2)} .. '
                  '${s.shortest.toStringAsFixed(2)} m',
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
