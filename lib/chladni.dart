import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/material.dart' as material show Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'disco_floor.dart' show CameraParams;

/// Chladni plate: sand on a vibrating square plate collects on the nodal lines
/// of a standing wave.
///
/// The plate's displacement for mode (n, m) is
///
///     u(x, y) = cos(nπx)·cos(mπy) ± cos(mπx)·cos(nπy)
///
/// Sand is kicked around with a strength proportional to |u|, so it bounces
/// away from the antinodes and stays put wherever u ≈ 0: the nodal lines.
/// Each grain is one instance of a single [InstancedMesh] and is stepped on
/// the CPU every frame.
class ChladniPage extends StatefulWidget {
  const ChladniPage({super.key});

  @override
  State<ChladniPage> createState() => _ChladniPageState();
}

class _ChladniPageState extends State<ChladniPage> {
  final Scene scene = Scene();
  final ChladniParams params = ChladniParams();
  final CameraParams camera = CameraParams()
    ..set(azimuth: 0, elevation: 80, distance: 9, fov: 45);
  final ValueNotifier<ChladniStats> stats = ValueNotifier(
    const ChladniStats(),
  );
  _Plate? plate;
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
      setState(() => plate = _Plate(scene, params));
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

  void _onTick(_Plate plate, Duration elapsed) {
    final dt = _seconds(elapsed - _lastTick).clamp(0.0, 1 / 20);
    _lastTick = elapsed;
    plate.update(dt);

    _framesSinceStats++;
    final window = _seconds(elapsed - _lastStatsUpdate);
    if (window >= 0.25) {
      stats.value = ChladniStats(
        fps: _framesSinceStats / window,
        frameMs: window * 1000 / _framesSinceStats,
        grains: plate.count,
        settled: plate.settledFraction,
      );
      _lastStatsUpdate = elapsed;
      _framesSinceStats = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final plate = this.plate;
    if (plate == null) {
      return const SizedBox.expand(
        child: Center(child: Text('Loading scene...')),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          radius: 1.1,
          colors: [Color(0xFF1B2A33), Color(0xFF04080B)],
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
                onTick: (elapsed, _) => _onTick(plate, elapsed),
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
                      plate: plate,
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
class ChladniParams extends ChangeNotifier {
  /// Mode numbers, the number of half-waves along each axis.
  int n = 3;
  int m = 5;

  /// Whether the two cosine products are added (symmetric) or subtracted
  /// (antisymmetric). The two give different families of figures.
  bool antisymmetric = false;

  /// Largest hop, in plate widths per frame at 60 fps, of a grain on an
  /// antinode.
  double shake = 0.03;

  /// Number of sand grains.
  int grains = 12000;

  /// Grain edge length in world units.
  double grainSize = 0.035;

  /// Jump to a new random mode every [cycleSeconds].
  bool autoCycle = false;
  double cycleSeconds = 10;

  static const int maxMode = 12;

  void update(void Function() change) {
    change();
    notifyListeners();
  }

  void randomMode(math.Random random) => update(() {
    final a = 1 + random.nextInt(maxMode);
    var b = 1 + random.nextInt(maxMode);
    if (b == a) b = a % maxMode + 1;
    n = math.min(a, b);
    m = math.max(a, b);
    antisymmetric = random.nextBool();
  });

  void reset() => update(() {
    n = 3;
    m = 5;
    antisymmetric = false;
    shake = 0.03;
    grains = 12000;
    grainSize = 0.035;
    autoCycle = false;
    cycleSeconds = 10;
  });
}

class ChladniStats {
  const ChladniStats({
    this.fps = 0,
    this.frameMs = 0,
    this.grains = 0,
    this.settled = 0,
  });

  final double fps;
  final double frameMs;
  final int grains;

  /// Fraction of grains resting close to a nodal line.
  final double settled;
}

double _seconds(Duration d) => d.inMicroseconds / 1e6;

/// Owns the plate and the sand, and advances the sand each frame.
class _Plate {
  _Plate(Scene scene, this.params) {
    scene.add(
      Node(
        localTransform: vm.Matrix4.translation(vm.Vector3(0, -0.06, 0)),
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(side, 0.12, side)),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.02, 0.025, 0.03, 1)
            ..metallicFactor = 0.5
            ..roughnessFactor = 0.5,
        ),
      ),
    );
    _grains = InstancedMesh(
      geometry: CuboidGeometry(vm.Vector3(1, 1, 1)),
      material: PhysicallyBasedMaterial()
        ..metallicFactor = 0.0
        ..roughnessFactor = 0.9,
    );
    scene.add(Node()..addComponent(InstancedMeshComponent(_grains)));
    _scatter(params.grains);
  }

  /// Edge length of the plate in world units.
  static const double side = 6;

  /// |u| below this counts as resting on a nodal line.
  static const double _settledThreshold = 0.05;

  final ChladniParams params;
  final math.Random _random = math.Random(7);

  late final InstancedMesh _grains;

  // Grain positions on the plate, normalised to 0..1 on both axes.
  List<double> _x = const [];
  List<double> _y = const [];

  int get count => _x.length;
  double settledFraction = 0;

  double _sinceCycle = 0;

  // Resting and active sand colours, linear RGBA.
  static final _restColor = vm.Vector4(0.95, 0.72, 0.36, 1);
  static final _activeColor = vm.Vector4(0.3, 0.2, 0.1, 1);

  /// Re-randomises the grains over the whole plate.
  void scatter() => _scatter(params.grains);

  void _scatter(int count) {
    _x = List<double>.generate(count, (_) => _random.nextDouble());
    _y = List<double>.generate(count, (_) => _random.nextDouble());
    _grains.clearInstances();
    final identity = vm.Matrix4.identity();
    for (var i = 0; i < count; i++) {
      _grains.addInstance(identity);
    }
  }

  void update(double dt) {
    if (params.grains != count) _scatter(params.grains);

    if (params.autoCycle) {
      _sinceCycle += dt;
      if (_sinceCycle >= params.cycleSeconds) {
        _sinceCycle = 0;
        params.randomMode(_random);
      }
    } else {
      _sinceCycle = 0;
    }

    final n = params.n * math.pi;
    final m = params.m * math.pi;
    final sign = params.antisymmetric ? -1.0 : 1.0;
    // Frame-rate independent: shake is a per-frame step at 60 fps.
    final step = params.shake * dt * 60;
    final size = params.grainSize;
    final half = side / 2;
    final color = vm.Vector4.zero();
    var settled = 0;

    _grains.updateInstanceTransforms((transforms) {
      for (var i = 0; i < transforms.length; i++) {
        var x = _x[i];
        var y = _y[i];

        // Mode shape at the grain, normalised so |u| is at most 1.
        final u =
            0.5 *
            (math.cos(n * x) * math.cos(m * y) +
                sign * math.cos(m * x) * math.cos(n * y));
        final amp = u.abs();

        // A random hop whose length scales with the local vibration.
        final angle = _random.nextDouble() * 2 * math.pi;
        final hop = step * amp * _random.nextDouble();
        x += math.cos(angle) * hop;
        y += math.sin(angle) * hop;
        // Reflect off the plate edges.
        if (x < 0) x = -x;
        if (x > 1) x = 2 - x;
        if (y < 0) y = -y;
        if (y > 1) y = 2 - y;
        _x[i] = x;
        _y[i] = y;

        if (amp < _settledThreshold) settled++;

        // Grains that are hopping lift off the plate a little.
        final lift = size / 2 + hop * side * 2;
        transforms[i].setValues(
          size,
          0,
          0,
          0,
          0,
          size,
          0,
          0,
          0,
          0,
          size,
          0,
          (x - 0.5) * 2 * half,
          lift,
          (y - 0.5) * 2 * half,
          1,
        );

        final t = (amp * 2).clamp(0.0, 1.0);
        color.setValues(
          _restColor.x + (_activeColor.x - _restColor.x) * t,
          _restColor.y + (_activeColor.y - _restColor.y) * t,
          _restColor.z + (_activeColor.z - _restColor.z) * t,
          1,
        );
        _grains.setInstanceColor(i, color);
      }
    }, recomputeWinding: false);

    settledFraction = count == 0 ? 0 : settled / count;
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.params,
    required this.plate,
    required this.camera,
    required this.open,
    required this.onToggle,
  });

  final ChladniParams params;
  final _Plate plate;
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
                    _header('Mode'),
                    _slider(
                      'n (half-waves in x)',
                      params.n.toDouble(),
                      1,
                      ChladniParams.maxMode.toDouble(),
                      (v) => params.update(() => params.n = v.round()),
                      divisions: ChladniParams.maxMode - 1,
                      digits: 0,
                    ),
                    _slider(
                      'm (half-waves in y)',
                      params.m.toDouble(),
                      1,
                      ChladniParams.maxMode.toDouble(),
                      (v) => params.update(() => params.m = v.round()),
                      divisions: ChladniParams.maxMode - 1,
                      digits: 0,
                    ),
                    _switch(
                      'Antisymmetric (minus)',
                      params.antisymmetric,
                      (v) => params.update(() => params.antisymmetric = v),
                    ),
                    _switch(
                      'Auto-cycle modes',
                      params.autoCycle,
                      (v) => params.update(() => params.autoCycle = v),
                    ),
                    if (params.autoCycle)
                      _slider(
                        'Cycle every (s)',
                        params.cycleSeconds,
                        2,
                        30,
                        (v) => params.update(() => params.cycleSeconds = v),
                        digits: 1,
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => params.randomMode(math.Random()),
                          child: const Text('Random mode'),
                        ),
                        TextButton(
                          onPressed: plate.scatter,
                          child: const Text('Scatter sand'),
                        ),
                      ],
                    ),
                    _header('Sand'),
                    _slider(
                      'Shake',
                      params.shake,
                      0.002,
                      0.1,
                      (v) => params.update(() => params.shake = v),
                    ),
                    _slider(
                      'Grains',
                      params.grains.toDouble(),
                      1000,
                      30000,
                      (v) => params.update(
                        () => params.grains = (v / 1000).round() * 1000,
                      ),
                      divisions: 29,
                      digits: 0,
                    ),
                    _slider(
                      'Grain size',
                      params.grainSize,
                      0.01,
                      0.1,
                      (v) => params.update(() => params.grainSize = v),
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

  final ChladniParams params;
  final ValueNotifier<ChladniStats> stats;

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
              'FPS      ${s.fps.toStringAsFixed(1)}',
              'Frame    ${s.frameMs.toStringAsFixed(2)} ms',
              'Grains   ${s.grains}',
              'Mode     (${params.n}, ${params.m}) '
                  '${params.antisymmetric ? '-' : '+'}',
              'Settled  ${(s.settled * 100).toStringAsFixed(0)}%',
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
