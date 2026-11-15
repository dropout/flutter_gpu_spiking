import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerScrollEvent;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/material.dart' as material show Material;
import 'package:flutter_scene/noise.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A flutter_scene investigation: a procedurally animated floor of cubes.
///
/// The floor is one [InstancedMesh] of 324 cubes, a single draw call, whose
/// per-instance transforms and colors are rewritten every frame. There are no
/// model or texture assets.
class DiscoFloorPage extends StatefulWidget {
  const DiscoFloorPage({super.key});

  @override
  State<DiscoFloorPage> createState() => _DiscoFloorPageState();
}

class _DiscoFloorPageState extends State<DiscoFloorPage> {
  final Scene scene = Scene();
  final DiscoParams params = DiscoParams();
  final CameraParams camera = CameraParams();
  double _lastScale = 1;
  final ValueNotifier<DiscoStats> stats = ValueNotifier(const DiscoStats());
  _DiscoFloor? floor;
  bool _panelOpen = false;

  Duration _lastTick = Duration.zero;
  Duration _lastStatsUpdate = Duration.zero;
  int _framesSinceStats = 0;

  @override
  void initState() {
    super.initState();
    _syncEnvironmentLighting();
    params.addListener(_syncEnvironmentLighting);
    // Geometry and materials touch the engine's shader bundle, so they can
    // only be created once the static resources are loaded.
    Scene.initializeStaticResources().then((_) {
      if (!mounted) return;
      setState(() => floor = _DiscoFloor(scene, params));
    });
  }

  @override
  void dispose() {
    params.removeListener(_syncEnvironmentLighting);
    params.dispose();
    camera.dispose();
    stats.dispose();
    scene.dispose();
    super.dispose();
  }

  void _syncEnvironmentLighting() {
    scene.environmentIntensity = params.environmentIntensity;
  }

  void _onTick(_DiscoFloor floor, Duration elapsed) {
    final dt = _seconds(elapsed - _lastTick);
    _lastTick = elapsed;
    floor.update(dt);

    _framesSinceStats++;
    final window = _seconds(elapsed - _lastStatsUpdate);
    if (window >= 0.25) {
      stats.value = DiscoStats(
        fps: _framesSinceStats / window,
        frameMs: window * 1000 / _framesSinceStats,
        phase: floor.phase,
        cubes: floor.count,
        minHeight: floor.minHeight,
        maxHeight: floor.maxHeight,
      );
      _lastStatsUpdate = elapsed;
      _framesSinceStats = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final floor = this.floor;
    if (floor == null) {
      return const SizedBox.expand(
        child: Center(child: Text('Loading scene...')),
      );
    }

    // The scene has no skybox, so it clears to transparent and this gradient
    // shows through as the background.
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          radius: 1.1,
          colors: [Color(0xFF2B0B4A), Color(0xFF05010D)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Drag orbits, pinch or scroll zooms.
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
                onTick: (elapsed, _) => _onTick(floor, elapsed),
                cameraBuilder: (elapsed) => camera.build(),
              ),
            ),
          ),
          // Flutter's Material is hidden by the scene import, so reach the
          // widget through a prefix. It gives the sliders something to draw on.
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
                        camera: camera,
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

enum DiscoMaterial {
  current('Current', metallicAmount: 0.1, roughness: 0.35),
  matte('Matte', metallicAmount: 0, roughness: 1),
  metallic('Metallic', metallicAmount: 1, roughness: 0.2),
  clearcoat(
    'Clearcoat',
    metallicAmount: 0.1,
    roughness: 0.35,
    clearcoatAmount: 1,
  ),
  iridescent(
    'Iridescent',
    metallicAmount: 0.1,
    roughness: 0.25,
    iridescence: 1,
  ),
  glass('Glass-like', metallicAmount: 0, roughness: 0.1, transmission: 0.9);

  const DiscoMaterial(
    this.label, {
    required this.metallicAmount,
    required this.roughness,
    this.clearcoatAmount = 0,
    this.iridescence = 0,
    this.transmission = 0,
  });

  final String label;
  final double metallicAmount;
  final double roughness;
  final double clearcoatAmount;
  final double iridescence;
  final double transmission;

  void applyTo(PhysicallyBasedMaterial material) {
    material
      ..metallicFactor = metallicAmount
      ..roughnessFactor = roughness
      ..clearcoat = clearcoatAmount
      ..iridescence = iridescence
      ..transmission = transmission;
  }
}

/// Tweakable parameters of the experiment.
class DiscoParams extends ChangeNotifier {
  static const double defaultEnvironmentIntensity = 0.25;

  double waveSpeed = 0.5;
  double waveLength = 2 * math.pi / 1.5;
  double waveAmplitude = 0.2;
  double noiseAmplitude = 0.2;
  double noiseDrift = 0.005;

  /// Cubes per world unit along each axis. The floor's area is fixed, so this
  /// changes how many cubes tile it, and the cubes shrink or grow to fit.
  double density = _DiscoFloor._defaultDensity;
  Color colorA = const Color(0xFF1E1954);
  Color colorB = const Color(0xFF342B91);
  DiscoMaterial material = DiscoMaterial.current;
  double environmentIntensity = defaultEnvironmentIntensity;

  void update(void Function() change) {
    change();
    notifyListeners();
  }

  void reset() => update(() {
    waveSpeed = 1.0;
    // waveLength = 2 * math.pi / 1.5;
    waveLength = 5.5;
    waveAmplitude = 0.1;
    noiseAmplitude = 0.0125;
    noiseDrift = 0.005;
    density = _DiscoFloor._defaultDensity;
    colorA = const Color(0xFF1E1954);
    colorB = const Color(0xFF342B91);
    material = DiscoMaterial.current;
    environmentIntensity = defaultEnvironmentIntensity;
  });
}

/// A named camera placement.
class CameraPreset {
  const CameraPreset(
    this.name, {
    required this.azimuth,
    required this.elevation,
    required this.distance,
    required this.fov,
  });

  final String name;
  final double azimuth; // degrees around the Y axis
  final double elevation; // degrees above the floor plane
  final double distance;
  final double fov; // vertical, degrees
}

/// An orbit camera around the middle of the floor.
class CameraParams extends ChangeNotifier {
  static const presets = [
    CameraPreset('Default', azimuth: 45, elevation: 35, distance: 12.873, fov: 20),
    CameraPreset(
      'Isometric',
      azimuth: 45,
      elevation: 35,
      distance: 16,
      fov: 20,
    ),
    CameraPreset('Top-down', azimuth: 45, elevation: 89, distance: 14, fov: 45),
    CameraPreset('Low angle', azimuth: 30, elevation: 12, distance: 9, fov: 50),
    CameraPreset('Club', azimuth: 200, elevation: 20, distance: 6, fov: 75),
  ];

  static const double minDistance = 1.5;
  static const double maxDistance = 30;
  // Stop short of straight up or down, where the up vector degenerates.
  static const double minElevation = 2;
  static const double maxElevation = 89;

  double azimuth = 45;
  double elevation = 43;
  double distance = 5.8;
  double fov = 45;

  void apply(CameraPreset p) => set(
    azimuth: p.azimuth,
    elevation: p.elevation,
    distance: p.distance,
    fov: p.fov,
  );

  void set({
    double? azimuth,
    double? elevation,
    double? distance,
    double? fov,
  }) {
    if (azimuth != null) this.azimuth = azimuth % 360;
    if (elevation != null) {
      this.elevation = elevation.clamp(minElevation, maxElevation);
    }
    if (distance != null) {
      this.distance = distance.clamp(minDistance, maxDistance);
    }
    if (fov != null) this.fov = fov.clamp(10, 120);
    notifyListeners();
  }

  /// Drag [delta] in logical pixels: right turns the floor, down tilts up.
  void orbitBy(Offset delta) => set(
    azimuth: azimuth - delta.dx * 0.4,
    elevation: elevation + delta.dy * 0.4,
  );

  void zoomBy(double factor) => set(distance: distance * factor);

  PerspectiveCamera build() {
    final az = azimuth * math.pi / 180;
    final el = elevation * math.pi / 180;
    return PerspectiveCamera(
      fovRadiansY: fov * math.pi / 180,
      position: vm.Vector3(
        distance * math.cos(el) * math.sin(az),
        distance * math.sin(el),
        distance * math.cos(el) * math.cos(az),
      ),
      target: vm.Vector3.zero(),
    );
  }
}

/// Values sampled a few times a second for the bottom-left overlay.
class DiscoStats {
  const DiscoStats({
    this.fps = 0,
    this.frameMs = 0,
    this.phase = 0,
    this.cubes = 0,
    this.minHeight = 0,
    this.maxHeight = 0,
  });

  final double fps;
  final double frameMs;
  final double phase;
  final int cubes;
  final double minHeight;
  final double maxHeight;
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.params,
    required this.camera,
    required this.open,
    required this.onToggle,
  });

  final DiscoParams params;
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
                    _header('Experiment'),
                    _slider(
                      'Wave speed',
                      params.waveSpeed,
                      0,
                      5,
                      (v) => params.update(() => params.waveSpeed = v),
                    ),
                    _slider(
                      'Wavelength',
                      params.waveLength,
                      0.5,
                      10,
                      (v) => params.update(() => params.waveLength = v),
                    ),
                    _slider(
                      'Wave amplitude',
                      params.waveAmplitude,
                      0,
                      0.5,
                      (v) => params.update(() => params.waveAmplitude = v),
                    ),
                    _slider(
                      'Noise amplitude',
                      params.noiseAmplitude,
                      0,
                      0.5,
                      (v) => params.update(() => params.noiseAmplitude = v),
                    ),
                    _slider(
                      'Noise drift',
                      params.noiseDrift,
                      0,
                      1,
                      (v) => params.update(() => params.noiseDrift = v),
                    ),
                    _slider(
                      'Density (cubes/unit)',
                      params.density,
                      0.5,
                      5,
                      (v) => params.update(() => params.density = v),
                    ),
                    _colorRow(
                      'Color A',
                      params.colorA,
                      (c) => params.update(() => params.colorA = c),
                    ),
                    _colorRow(
                      'Color B',
                      params.colorB,
                      (c) => params.update(() => params.colorB = c),
                    ),
                    _slider(
                      'Environment lighting',
                      params.environmentIntensity,
                      0,
                      2,
                      (v) =>
                          params.update(() => params.environmentIntensity = v),
                    ),
                    _header('Material'),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final preset in DiscoMaterial.values)
                          ChoiceChip(
                            label: Text(preset.label),
                            selected: params.material == preset,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) =>
                                params.update(() => params.material = preset),
                          ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: params.reset,
                        child: const Text('Reset'),
                      ),
                    ),
                    _header('Camera'),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final p in CameraParams.presets)
                          ActionChip(
                            label: Text(p.name),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => camera.apply(p),
                          ),
                      ],
                    ),
                    _slider(
                      'Azimuth',
                      camera.azimuth,
                      0,
                      360,
                      (v) => camera.set(azimuth: v),
                    ),
                    _slider(
                      'Elevation',
                      camera.elevation,
                      CameraParams.minElevation,
                      CameraParams.maxElevation,
                      (v) => camera.set(elevation: v),
                    ),
                    _slider(
                      'Distance',
                      camera.distance,
                      CameraParams.minDistance,
                      CameraParams.maxDistance,
                      (v) => camera.set(distance: v),
                    ),
                    _slider(
                      'Field of view',
                      camera.fov,
                      10,
                      120,
                      (v) => camera.set(fov: v),
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

  static const _swatches = [
    Color(0xFF1E1954),
    Color(0xFF342B91),
    Color(0xFF0D75F8),
    Color(0xFFA81FE0),
    Color(0xFFFF2BD6),
    Color(0xFF00E5FF),
    Color(0xFFFFB300),
    Color(0xFF111111),
  ];

  Widget _colorRow(String label, Color value, ValueChanged<Color> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: const TextStyle(color: Colors.white)),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in _swatches)
                  GestureDetector(
                    onTap: () => onChanged(c),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == value ? Colors.white : Colors.white24,
                          width: c == value ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
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

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '$label: ${value.toStringAsFixed(3)}',
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
  const _StatsOverlay({
    required this.params,
    required this.camera,
    required this.stats,
  });

  final DiscoParams params;
  final CameraParams camera;
  final ValueNotifier<DiscoStats> stats;

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
          listenable: Listenable.merge([stats, params, camera]),
          builder: (context, _) {
            final s = stats.value;
            final lines = [
              'FPS        ${s.fps.toStringAsFixed(1)}',
              'Frame      ${s.frameMs.toStringAsFixed(2)} ms',
              'Cubes      ${s.cubes}',
              'Wave phase ${s.phase.toStringAsFixed(2)}',
              'Height     ${s.minHeight.toStringAsFixed(3)} .. '
                  '${s.maxHeight.toStringAsFixed(3)}',
              'Speed      ${params.waveSpeed.toStringAsFixed(2)}',
              'Camera     az ${camera.azimuth.toStringAsFixed(0)}° '
                  'el ${camera.elevation.toStringAsFixed(0)}°',
              'Cam dist   ${camera.distance.toStringAsFixed(1)}  '
                  'fov ${camera.fov.toStringAsFixed(0)}°',
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

double _seconds(Duration d) => d.inMicroseconds / 1e6;

/// Owns the cubes and advances them each frame.
class _DiscoFloor {
  _DiscoFloor(Scene scene, this.params) {
    params.material.applyTo(_material);
    _appliedMaterial = params.material;
    _cubes = InstancedMesh(
      geometry: CuboidGeometry(vm.Vector3(0.56, 0.6, 0.56)),
      material: _material,
    );
    _resize(_gridSize);
    // An InstancedMesh rides on a component rather than on Node(mesh:).
    scene.add(Node()..addComponent(InstancedMeshComponent(_cubes)));

  }

  /// The floor covers a fixed square area; density only changes how many cubes
  /// tile it. The defaults reproduce the original 18 x 18 grid at 0.58 pitch.
  static const double _side = 18 * 0.58;
  // static const double _defaultDensity = 18 / _side;
  static const double _defaultDensity = 2.5;
  static const double _referencePitch = 0.58;

  /// Cubes along one edge of the floor.
  int _size = 18;
  int get count => _size * _size;

  final DiscoParams params;

  final FastNoiseLite _noise = FastNoiseLite(seed: 42)
    ..noiseType = NoiseType.openSimplex2
    ..frequency = 1.0;

  late final InstancedMesh _cubes;
  final PhysicallyBasedMaterial _material = PhysicallyBasedMaterial();
  late DiscoMaterial _appliedMaterial;

  int get _gridSize => (params.density * _side).round().clamp(2, 200);

  void _resize(int size) {
    _size = size;
    _cubes.clearInstances();
    final identity = vm.Matrix4.identity();
    for (var i = 0; i < size * size; i++) {
      _cubes.addInstance(identity);
    }
  }

  /// Wave phase and noise time are accumulated, rather than derived from the
  /// elapsed time, so changing a speed slider never makes the floor jump.
  double phase = 0;
  double _noiseTime = 0;
  double minHeight = 0;
  double maxHeight = 0;

  void update(double dt) {
    phase += dt * params.waveSpeed;
    _noiseTime += dt * params.noiseDrift;

    if (_appliedMaterial != params.material) {
      params.material.applyTo(_material);
      _appliedMaterial = params.material;
    }
    if (_gridSize != _size) _resize(_gridSize);
    final half = (_size - 1) / 2;
    final spacing = _side / _size;
    // Cubes keep the same fill ratio of their cell as the original layout.
    final footprint = spacing / _referencePitch;
    final color = vm.Vector4.zero();
    var lo = double.infinity;
    var hi = double.negativeInfinity;

    _cubes.updateInstanceTransforms((transforms) {
      for (var row = 0; row < _size; row++) {
        for (var col = 0; col < _size; col++) {
          final index = row * _size + col;
          final x = (col - half) * spacing;
          final z = (row - half) * spacing;
          final waveX = x + half * spacing;
          final waveZ = z + half * spacing;
          final distance = math.sqrt(waveX * waveX + waveZ * waveZ);

          // A ring that travels outwards from the top-left corner, roughened
          // up with drifting noise so it never looks perfectly regular.
          final ring = math.sin(
            distance * (2 * math.pi / params.waveLength) - phase,
          );
          final drift = _noise.getNoise3(x * 0.15, z * 0.15, _noiseTime);
          final y = params.waveAmplitude * ring + params.noiseAmplitude * drift;
          lo = math.min(lo, y);
          hi = math.max(hi, y);
          // Column-major: scale the footprint, keep the thickness.
          transforms[index].setValues(
            footprint,
            0,
            0,
            0, //
            0,
            1,
            0,
            0,
            0,
            0,
            footprint,
            0,
            x,
            y,
            z,
            1,
          );

          final finalColor =
              Color.lerp(params.colorA, params.colorB, 0.5 - 0.5 * ring) ??
              params.colorA;
          color.setValues(
            finalColor.r,
            finalColor.g,
            finalColor.b,
            finalColor.a,
          );
          _cubes.setInstanceColor(index, color);
        }
      }
    }, recomputeWinding: false); // positive scale only, never mirrored
    minHeight = lo;
    maxHeight = hi;
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
