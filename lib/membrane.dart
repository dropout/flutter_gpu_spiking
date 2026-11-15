import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/material.dart' as material show Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'app/color_swatch_row.dart';
import 'disco_floor.dart' show CameraParams;

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
class MembranePage extends StatefulWidget {
  const MembranePage({super.key});

  @override
  State<MembranePage> createState() => _MembranePageState();
}

class _MembranePageState extends State<MembranePage> {
  final Scene scene = Scene();
  final MembraneParams params = MembraneParams();
  final CameraParams camera = CameraParams()
    ..set(azimuth: 45, elevation: 40, distance: 12, fov: 40);
  final ValueNotifier<MembraneStats> stats = ValueNotifier(
    const MembraneStats(),
  );
  _Membrane? membrane;
  bool _panelOpen = false;
  double _lastScale = 1;
  Size _viewSize = Size.zero;

  Duration _lastTick = Duration.zero;
  Duration _lastStatsUpdate = Duration.zero;
  int _framesSinceStats = 0;

  @override
  void initState() {
    super.initState();
    Scene.initializeStaticResources().then((_) {
      if (!mounted) return;
      final m = _Membrane(scene, params)..exciteMode();
      setState(() => membrane = m);
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

  void _onTick(_Membrane membrane, Duration elapsed) {
    final dt = _seconds(elapsed - _lastTick).clamp(0.0, 1 / 20);
    _lastTick = elapsed;
    membrane.update(dt);

    _framesSinceStats++;
    final window = _seconds(elapsed - _lastStatsUpdate);
    if (window >= 0.25) {
      stats.value = MembraneStats(
        fps: _framesSinceStats / window,
        frameMs: window * 1000 / _framesSinceStats,
        nodes: membrane.size * membrane.size,
        simTime: membrane.simTime,
        peak: membrane.peak,
      );
      _lastStatsUpdate = elapsed;
      _framesSinceStats = 0;
    }
  }

  /// Casts a ray from a tap through the camera onto the resting plane (y = 0)
  /// and plucks the membrane where it lands.
  void _pluckAt(_Membrane membrane, Offset local) {
    if (_viewSize.isEmpty) return;
    // Let the camera unproject the tap, so the ray agrees with exactly what
    // the renderer draws.
    final ray = camera.build().screenPointToRay(local, _viewSize);
    final dy = ray.direction.y;
    if (dy.abs() < 1e-6) return;
    final s = -ray.origin.y / dy;
    if (s < 0) return;
    final hit = ray.origin + ray.direction * s;
    membrane.pluck(hit.x, hit.z);
  }

  @override
  Widget build(BuildContext context) {
    final membrane = this.membrane;
    if (membrane == null) {
      return const SizedBox.expand(
        child: Center(child: Text('Loading scene...')),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          radius: 1.1,
          colors: [Color(0xFF0D2430), Color(0xFF02070B)],
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewSize = constraints.biggest;
                return GestureDetector(
                  onTapUp: (details) =>
                      _pluckAt(membrane, details.localPosition),
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
                    onTick: (elapsed, _) => _onTick(membrane, elapsed),
                    cameraBuilder: (elapsed) => camera.build(),
                  ),
                );
              },
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
                      membrane: membrane,
                      camera: camera,
                      open: _panelOpen,
                      onToggle: () => setState(() => _panelOpen = !_panelOpen),
                    ),
                  ),
                  if (!_panelOpen)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: _StatsOverlay(
                        params: params,
                        membrane: membrane,
                        stats: stats,
                      ),
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
class MembraneParams extends ChangeNotifier {
  static const defaultCrestColor = Color.from(
    alpha: 1,
    red: 0,
    green: 0.8,
    blue: 1,
  );
  static const defaultTroughColor = Color.from(
    alpha: 1,
    red: 1,
    green: 0.1,
    blue: 0.5,
  );

  /// Courant number: how far a wave travels per step, in grid cells. The 2D
  /// scheme is stable up to 1/√2.
  double courant = 0.18;

  /// Fraction of velocity lost per step.
  double damping = 0.0100;

  /// Simulation speed relative to real time.
  double timeScale = 0.1;

  /// Nodes along one edge of the membrane.
  int nodes = 48;

  /// Normal mode used by "Excite mode" and the driver's tuning.
  int modeN = 2;
  int modeM = 3;

  /// Size of a pluck, in world units and displacement.
  double pluckRadius = 0.6;
  double pluckAmplitude = 1.0;

  /// A sinusoidal force on one node, at [driveHz] in simulation time.
  bool drive = false;
  double driveHz = 3;
  double driveAmplitude = 0.01;

  /// World units of height per unit of displacement.
  double gain = 0.8;
  Color crestColor = defaultCrestColor;
  Color troughColor = defaultTroughColor;

  static const int maxMode = 10;
  static const double maxCourant = 0.7; // just under 1/√2

  void update(void Function() change) {
    change();
    notifyListeners();
  }

  void reset() => update(() {
    courant = 0.18;
    damping = 0.0100;
    timeScale = 0.1;
    nodes = 48;
    modeN = 2;
    modeM = 3;
    pluckRadius = 0.6;
    pluckAmplitude = 1.0;
    drive = false;
    driveHz = 3;
    driveAmplitude = 0.01;
    gain = 0.8;
    crestColor = defaultCrestColor;
    troughColor = defaultTroughColor;
  });
}

class MembraneStats {
  const MembraneStats({
    this.fps = 0,
    this.frameMs = 0,
    this.nodes = 0,
    this.simTime = 0,
    this.peak = 0,
  });

  final double fps;
  final double frameMs;
  final int nodes;
  final double simTime;

  /// Largest absolute displacement on the membrane.
  final double peak;
}

double _seconds(Duration d) => d.inMicroseconds / 1e6;

/// The lattice state and the cubes that draw it.
class _Membrane {
  _Membrane(Scene scene, this.params) {
    _cubes = InstancedMesh(
      geometry: CuboidGeometry(vm.Vector3(1, 0.25, 1)),
      material: PhysicallyBasedMaterial()
        ..metallicFactor = 0.2
        ..roughnessFactor = 0.4,
    );
    _allocate(params.nodes);
    scene.add(Node()..addComponent(InstancedMeshComponent(_cubes)));
  }

  /// Edge length of the membrane in world units.
  static const double side = 8;

  /// Simulation steps per second of simulated time at timeScale 1.
  static const double stepsPerSecond = 240;
  static const double _dt = 1 / stepsPerSecond;

  /// Cap on steps per frame, so a slow frame cannot snowball.
  static const int _maxStepsPerFrame = 16;

  final MembraneParams params;
  late final InstancedMesh _cubes;

  int size = 0;
  Float64List _u = Float64List(0);
  Float64List _prev = Float64List(0);
  Float64List _next = Float64List(0);

  double simTime = 0;
  double peak = 0;
  double _stepAccumulator = 0;
  int _stepCount = 0;

  double get _pitch => side / (size - 1);

  // Colors, linear RGBA: neutral at rest, tinted by the sign of displacement.
  static final _rest = vm.Vector4(0.05, 0.09, 0.16, 1);

  void _allocate(int n) {
    size = n;
    _u = Float64List(n * n);
    _prev = Float64List(n * n);
    _next = Float64List(n * n);
    simTime = 0;
    _stepCount = 0;
    _stepAccumulator = 0;
    _cubes.clearInstances();
    final identity = vm.Matrix4.identity();
    for (var i = 0; i < n * n; i++) {
      _cubes.addInstance(identity);
    }
  }

  /// Stills the membrane.
  void clear() {
    _u.fillRange(0, _u.length, 0);
    _prev.fillRange(0, _prev.length, 0);
    simTime = 0;
    _stepCount = 0;
  }

  /// Displaces the membrane in a Gaussian bump around world point (x, z) and
  /// lets go.
  void pluck(double x, double z) {
    final half = side / 2;
    if (x.abs() > half || z.abs() > half) return;
    final sigma = params.pluckRadius;
    final pitch = _pitch;
    for (var j = 1; j < size - 1; j++) {
      for (var i = 1; i < size - 1; i++) {
        final dx = (i * pitch - half) - x;
        final dz = (j * pitch - half) - z;
        final bump =
            params.pluckAmplitude *
            math.exp(-(dx * dx + dz * dz) / (2 * sigma * sigma));
        _u[j * size + i] += bump;
        _prev[j * size + i] += bump; // released from rest
      }
    }
  }

  /// Resets the membrane to a pure standing wave in mode (n, m).
  void exciteMode() {
    final n = params.modeN;
    final m = params.modeM;
    final omega = _omega(n, m);
    final last = size - 1;
    for (var j = 0; j < size; j++) {
      for (var i = 0; i < size; i++) {
        final shape =
            math.sin(n * math.pi * i / last) * math.sin(m * math.pi * j / last);
        _u[j * size + i] = shape;
        // One step back along the exact discrete solution, so the mode starts
        // as an undisturbed standing wave.
        _prev[j * size + i] = shape * math.cos(omega * _dt);
      }
    }
    simTime = 0;
    _stepCount = 0;
  }

  /// Angular frequency of mode (n, m) on this lattice, in rad/s, including the
  /// slight slowing of short waves that the discretisation causes.
  double _omega(int n, int m) {
    final last = size - 1;
    final sn = math.sin(n * math.pi / (2 * last));
    final sm = math.sin(m * math.pi / (2 * last));
    final s = (params.courant * math.sqrt(sn * sn + sm * sm)).clamp(0.0, 1.0);
    return 2 / _dt * math.asin(s);
  }

  /// Natural frequency of mode (n, m) in Hz of simulation time.
  double frequencyHz(int n, int m) => _omega(n, m) / (2 * math.pi);

  void _step() {
    final n = size;
    final c2 = params.courant * params.courant;
    final keep = 1 - params.damping;
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

    if (params.drive) {
      final k = (n * 0.43).round() * n + (n * 0.31).round();
      next[k] +=
          params.driveAmplitude *
          math.sin(2 * math.pi * params.driveHz * _stepCount * _dt);
    }

    _prev = u;
    _u = next;
    _next = prev;
    _stepCount++;
  }

  void update(double dt) {
    if (params.nodes != size) {
      _allocate(params.nodes);
      exciteMode();
    }

    _stepAccumulator += dt * params.timeScale * stepsPerSecond;
    var steps = _stepAccumulator.floor().clamp(0, _maxStepsPerFrame);
    _stepAccumulator -= _stepAccumulator.floorToDouble();
    while (steps-- > 0) {
      _step();
    }
    simTime = _stepCount * _dt;

    final n = size;
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
          transforms[k].setValues(
            footprint,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            footprint,
            0,
            i * pitch - half,
            u * params.gain,
            j * pitch - half,
            1,
          );

          final t = (u.abs() * 1.5).clamp(0.0, 1.0);
          final tint = u >= 0 ? params.crestColor : params.troughColor;
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
    peak = maxAbs;
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.params,
    required this.membrane,
    required this.camera,
    required this.open,
    required this.onToggle,
  });

  final MembraneParams params;
  final _Membrane membrane;
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
                    _header('Normal mode'),
                    _slider(
                      'n',
                      params.modeN.toDouble(),
                      1,
                      MembraneParams.maxMode.toDouble(),
                      (v) => params.update(() => params.modeN = v.round()),
                      divisions: MembraneParams.maxMode - 1,
                      digits: 0,
                    ),
                    _slider(
                      'm',
                      params.modeM.toDouble(),
                      1,
                      MembraneParams.maxMode.toDouble(),
                      (v) => params.update(() => params.modeM = v.round()),
                      divisions: MembraneParams.maxMode - 1,
                      digits: 0,
                    ),
                    _note(
                      'Natural frequency: '
                      '${membrane.frequencyHz(params.modeN, params.modeM).toStringAsFixed(2)} Hz',
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: membrane.exciteMode,
                          child: const Text('Excite mode'),
                        ),
                        TextButton(
                          onPressed: membrane.clear,
                          child: const Text('Still'),
                        ),
                      ],
                    ),
                    _header('Pluck (tap the membrane)'),
                    _slider(
                      'Radius',
                      params.pluckRadius,
                      0.2,
                      2,
                      (v) => params.update(() => params.pluckRadius = v),
                      digits: 2,
                    ),
                    _slider(
                      'Amplitude',
                      params.pluckAmplitude,
                      -2,
                      2,
                      (v) => params.update(() => params.pluckAmplitude = v),
                      digits: 2,
                    ),
                    _header('Driver'),
                    _switch(
                      'Drive a point',
                      params.drive,
                      (v) => params.update(() => params.drive = v),
                    ),
                    _slider(
                      'Frequency (Hz)',
                      params.driveHz,
                      0.2,
                      30,
                      (v) => params.update(() => params.driveHz = v),
                      digits: 2,
                    ),
                    _slider(
                      'Force',
                      params.driveAmplitude,
                      0.001,
                      0.05,
                      (v) => params.update(() => params.driveAmplitude = v),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => params.update(
                          () => params.driveHz = membrane.frequencyHz(
                            params.modeN,
                            params.modeM,
                          ),
                        ),
                        child: const Text('Tune to mode'),
                      ),
                    ),
                    _header('Medium'),
                    _slider(
                      'Wave speed (Courant)',
                      params.courant,
                      0.1,
                      MembraneParams.maxCourant,
                      (v) => params.update(() => params.courant = v),
                      digits: 2,
                    ),
                    _slider(
                      'Damping',
                      params.damping,
                      0,
                      0.01,
                      (v) => params.update(() => params.damping = v),
                      digits: 4,
                    ),
                    _slider(
                      'Time scale',
                      params.timeScale,
                      0.1,
                      3,
                      (v) => params.update(() => params.timeScale = v),
                      digits: 2,
                    ),
                    _slider(
                      'Nodes per edge',
                      params.nodes.toDouble(),
                      16,
                      96,
                      (v) => params.update(
                        () => params.nodes = (v / 8).round() * 8,
                      ),
                      divisions: 10,
                      digits: 0,
                    ),
                    _slider(
                      'Height gain',
                      params.gain,
                      0.1,
                      3,
                      (v) => params.update(() => params.gain = v),
                      digits: 2,
                    ),
                    _header('Colors'),
                    ColorSwatchRow(
                      label: 'Crest',
                      value: params.crestColor,
                      swatches: _colorSwatches,
                      onChanged: (c) =>
                          params.update(() => params.crestColor = c),
                    ),
                    ColorSwatchRow(
                      label: 'Trough',
                      value: params.troughColor,
                      swatches: _colorSwatches,
                      onChanged: (c) =>
                          params.update(() => params.troughColor = c),
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

  static const _colorSwatches = [
    MembraneParams.defaultCrestColor,
    MembraneParams.defaultTroughColor,
    ...ColorSwatchRow.defaultSwatches,
  ];

  Widget _note(String text) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      text,
      style: const TextStyle(color: Colors.white70, fontSize: 12),
    ),
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
  const _StatsOverlay({
    required this.params,
    required this.membrane,
    required this.stats,
  });

  final MembraneParams params;
  final _Membrane membrane;
  final ValueNotifier<MembraneStats> stats;

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
              'Nodes     ${s.nodes}',
              'Sim time  ${s.simTime.toStringAsFixed(1)} s',
              'Peak      ${s.peak.toStringAsFixed(3)}',
              'Mode      (${params.modeN}, ${params.modeM}) '
                  '${membrane.frequencyHz(params.modeN, params.modeM).toStringAsFixed(2)} Hz',
              if (params.drive)
                'Driver    ${params.driveHz.toStringAsFixed(2)} Hz',
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
