import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'experiment.dart';
import 'lab_shaders.dart';
import 'params.dart';

/// A procedural terrain mesh in flutter_scene.
///
/// The CPU builds a heightfield grid from fractal noise (optionally blended
/// with ridged noise for mountain crests), with smooth normals from central
/// differences, and uploads it as an updatable [MeshGeometry]. Changing a
/// terrain parameter rebuilds the arrays and swaps them into the same
/// geometry. A custom [ShaderMaterial] (`shaders/lab/terrain.frag`) colors it
/// by height and slope, with water, a snow line and optional contour lines.
///
/// The panel's `Params` block is only read in Dart here; the shader gets its
/// own `Terrain` block, rewritten every frame.
class TerrainExperiment extends LabExperiment {
  const TerrainExperiment();

  @override
  String get name => 'Scene: terrain';

  @override
  String get description =>
      'Heightfield mesh from fBm / ridged noise, built on the CPU and shaded '
      'by height and slope. Drag to orbit, scroll to zoom.';

  @override
  List<LabParam> get params => const [
    FloatParam(
      'seed',
      'Seed',
      min: 0,
      max: 999,
      initial: 7,
      decimals: 0,
      divisions: 999,
    ),
    FloatParam('frequency', 'Frequency', min: 0.3, max: 4, initial: 1.2),
    FloatParam(
      'octaves',
      'Octaves',
      min: 1,
      max: 8,
      initial: 6,
      decimals: 0,
      divisions: 7,
    ),
    FloatParam('height', 'Height', min: 0.1, max: 2.5, initial: 1.1),
    FloatParam('ridged', 'Ridged', min: 0, max: 1, initial: 0.4),
    FloatParam(
      'grid',
      'Grid size',
      min: 32,
      max: 250,
      initial: 160,
      decimals: 0,
      divisions: 218,
    ),
    FloatParam('water', 'Water level', min: 0, max: 0.8, initial: 0.3),
    FloatParam('snow', 'Snow line', min: 0.3, max: 1.2, initial: 0.75),
    FloatParam('rockSlope', 'Rock slope', min: 0.05, max: 0.6, initial: 0.25),
    FloatParam('lightAz', 'Sun azimuth', min: 0, max: 360, initial: 215),
    FloatParam('lightEl', 'Sun elevation', min: 5, max: 90, initial: 35),
    FloatParam('contour', 'Contour lines', min: 0, max: 1, initial: 0),
    ColorParam('water_c', 'Water', initial: Color(0xFF1B6E9C)),
    ColorParam('grass_c', 'Grass', initial: Color(0xFF4F8A3A)),
    ColorParam('snow_c', 'Snow', initial: Color(0xFFF2F6FA)),
  ];

  @override
  Widget buildView(BuildContext context, LabContext lab) =>
      _TerrainView(key: const ValueKey('terrain'), lab: lab);
}

/// World size of the terrain's square footprint.
const double _kTerrainSize = 4;

/// The arrays one terrain mesh is made of.
class _TerrainMesh {
  _TerrainMesh({
    required this.positions,
    required this.normals,
    required this.texCoords,
    required this.colors,
    required this.indices,
  });

  final Float32List positions;
  final Float32List normals;
  final Float32List texCoords;
  final Float32List colors;
  final List<int> indices;
}

/// Gradient noise on an integer lattice, in about -1..1.
class _Noise {
  _Noise(int seed) : _seed = seed * 0x9E3779B1;

  final int _seed;

  int _hash(int x, int y) {
    var h = (x * 0x27D4EB2D) ^ (y * 0x165667B1) ^ _seed;
    h = (h ^ (h >> 15)) * 0x2C1B3C6D;
    h = (h ^ (h >> 12)) * 0x297A2D39;
    h = h ^ (h >> 15);
    return h & 0xFFFFFFFF;
  }

  double _gradient(int ix, int iy, double fx, double fy) {
    final angle = _hash(ix, iy) / 0xFFFFFFFF * 2 * math.pi;
    return math.cos(angle) * fx + math.sin(angle) * fy;
  }

  double sample(double x, double y) {
    final ix = x.floor();
    final iy = y.floor();
    final fx = x - ix;
    final fy = y - iy;
    final u = fx * fx * fx * (fx * (fx * 6 - 15) + 10);
    final v = fy * fy * fy * (fy * (fy * 6 - 15) + 10);
    final a = _gradient(ix, iy, fx, fy);
    final b = _gradient(ix + 1, iy, fx - 1, fy);
    final c = _gradient(ix, iy + 1, fx, fy - 1);
    final d = _gradient(ix + 1, iy + 1, fx - 1, fy - 1);
    final top = a + (b - a) * u;
    final bottom = c + (d - c) * u;
    return (top + (bottom - top) * v) * 1.41;
  }
}

/// Builds the mesh arrays for a [grid] x [grid] vertex terrain.
_TerrainMesh _buildTerrain({
  required int grid,
  required int seed,
  required double frequency,
  required int octaves,
  required double ridged,
  required double height,
  required double water,
}) {
  final noise = _Noise(seed);
  final count = grid * grid;
  final heights = Float32List(count); // raw 0..1, before water flattening

  const rot = [0.8, 0.6, -0.6, 0.8];
  for (var j = 0; j < grid; j++) {
    for (var i = 0; i < grid; i++) {
      var x = i / (grid - 1) * frequency * 2 + seed * 0.37;
      var y = j / (grid - 1) * frequency * 2 + seed * 0.61;

      var sum = 0.0;
      var ridgeSum = 0.0;
      var amp = 1.0;
      var norm = 0.0;
      for (var o = 0; o < octaves; o++) {
        final n = noise.sample(x, y);
        sum += amp * n;
        final r = 1 - n.abs();
        ridgeSum += amp * r * r;
        norm += amp;
        final nx = (rot[0] * x + rot[1] * y) * 2 + 17.3;
        final ny = (rot[2] * x + rot[3] * y) * 2 + 9.1;
        x = nx;
        y = ny;
        amp *= 0.5;
      }
      final smooth = (sum / norm * 0.5 + 0.5).clamp(0.0, 1.0);
      final crest = (ridgeSum / norm).clamp(0.0, 1.0);
      final h = smooth + (crest - smooth) * ridged;
      // Flatten valleys a little and keep the range in 0..1.
      heights[j * grid + i] = math.pow(h.clamp(0.0, 1.0), 1.4).toDouble();
    }
  }

  final positions = Float32List(count * 3);
  final normals = Float32List(count * 3);
  final texCoords = Float32List(count * 2);
  final colors = Float32List(count * 4);
  final step = _kTerrainSize / (grid - 1);

  double raw(int i, int j) =>
      heights[j.clamp(0, grid - 1) * grid + i.clamp(0, grid - 1)];

  for (var j = 0; j < grid; j++) {
    for (var i = 0; i < grid; i++) {
      final k = j * grid + i;
      final h = heights[k];
      positions[k * 3] = (i / (grid - 1) - 0.5) * _kTerrainSize;
      positions[k * 3 + 1] = math.max(h, water) * height;
      positions[k * 3 + 2] = (j / (grid - 1) - 0.5) * _kTerrainSize;

      // Central differences on the raw heights; flat on the water surface.
      var nx = 0.0, ny = 1.0, nz = 0.0;
      if (h > water) {
        final dx = (raw(i + 1, j) - raw(i - 1, j)) * height / (2 * step);
        final dz = (raw(i, j + 1) - raw(i, j - 1)) * height / (2 * step);
        final len = math.sqrt(dx * dx + 1 + dz * dz);
        nx = -dx / len;
        ny = 1 / len;
        nz = -dz / len;
      }
      normals[k * 3] = nx;
      normals[k * 3 + 1] = ny;
      normals[k * 3 + 2] = nz;

      texCoords[k * 2] = i / (grid - 1);
      texCoords[k * 2 + 1] = j / (grid - 1);

      colors[k * 4] = h; // raw height for the shader
      colors[k * 4 + 3] = 1;
    }
  }

  final indices = <int>[];
  for (var j = 0; j < grid - 1; j++) {
    for (var i = 0; i < grid - 1; i++) {
      final a = j * grid + i;
      final b = a + 1;
      final c = a + grid;
      final d = c + 1;
      indices.addAll([a, c, b, b, c, d]);
    }
  }

  return _TerrainMesh(
    positions: positions,
    normals: normals,
    texCoords: texCoords,
    colors: colors,
    indices: indices,
  );
}

class _TerrainView extends StatefulWidget {
  const _TerrainView({super.key, required this.lab});

  final LabContext lab;

  @override
  State<_TerrainView> createState() => _TerrainViewState();
}

class _TerrainViewState extends State<_TerrainView> {
  static const String _errorKey = 'scene:terrain';

  final Scene _scene = Scene();
  ShaderMaterial? _material;
  MeshGeometry? _geometry;
  String? _builtKey;

  double _azimuth = 35;
  double _elevation = 32;
  double _distance = 6.5;
  double _lastScale = 1;

  PerspectiveCamera? _camera;
  GradientSkySource? _sky;

  @override
  void initState() {
    super.initState();
    Scene.initializeStaticResources().then((_) async {
      try {
        final library = await gpu.loadShaderLibraryAsync(kLabBundleAsset);
        if (!mounted) return;
        _build(library!['LabTerrainFragment']!);
        widget.lab.errors.clear(_errorKey);
      } catch (e) {
        widget.lab.errors.report(_errorKey, '$e');
      }
      if (mounted) setState(() {});
    });
  }

  void _build(gpu.Shader fragment) {
    final material = ShaderMaterial(fragmentShader: fragment)
      // Normals come from the heightfield, not triangle winding, so draw both
      // faces and skip culling.
      ..doubleSided = true;
    final mesh = _meshForCurrentValues();
    final geometry = MeshGeometry.fromArrays(
      positions: mesh.positions,
      normals: mesh.normals,
      texCoords: mesh.texCoords,
      colors: mesh.colors,
      indices: mesh.indices,
      storage: GeometryStorage.updatable,
    );
    _scene.add(Node(mesh: Mesh(geometry, material)));
    _material = material;
    _geometry = geometry;
    _builtKey = _terrainKey();

    final sky = GradientSkySource(
      zenithColor: vm.Vector3(0.05, 0.16, 0.50),
      horizonColor: vm.Vector3(0.50, 0.65, 0.90),
      groundColor: vm.Vector3(0.20, 0.22, 0.25),
    );
    _sky = sky;
    _scene.skybox = Skybox(sky);
  }

  /// Everything that changes the mesh itself.
  String _terrainKey() {
    final v = widget.lab.values;
    return [
      v.getFloat('seed'),
      v.getFloat('frequency'),
      v.getFloat('octaves'),
      v.getFloat('height'),
      v.getFloat('ridged'),
      v.getFloat('grid'),
      v.getFloat('water'),
    ].join(',');
  }

  _TerrainMesh _meshForCurrentValues() {
    final v = widget.lab.values;
    return _buildTerrain(
      grid: v.getFloat('grid').round(),
      seed: v.getFloat('seed').round(),
      frequency: v.getFloat('frequency'),
      octaves: v.getFloat('octaves').round(),
      ridged: v.getFloat('ridged'),
      height: v.getFloat('height'),
      water: v.getFloat('water'),
    );
  }

  @override
  void dispose() {
    _scene.dispose();
    super.dispose();
  }

  /// Linear-light RGB of a panel color.
  List<double> _linear(Color c) => [
    math.pow(c.r, 2.2).toDouble(),
    math.pow(c.g, 2.2).toDouble(),
    math.pow(c.b, 2.2).toDouble(),
    1,
  ];

  void _onTick() {
    final material = _material;
    final geometry = _geometry;
    final camera = _camera;
    if (material == null || geometry == null || camera == null) return;
    final v = widget.lab.values;

    final key = _terrainKey();
    if (key != _builtKey) {
      _builtKey = key;
      try {
        final mesh = _meshForCurrentValues();
        geometry.rebuild(
          positions: mesh.positions,
          normals: mesh.normals,
          texCoords: mesh.texCoords,
          colors: mesh.colors,
          indices: mesh.indices,
        );
        widget.lab.errors.clear(_errorKey);
      } catch (e) {
        widget.lab.errors.report(_errorKey, '$e');
      }
    }

    final az = v.getFloat('lightAz') * math.pi / 180;
    final el = v.getFloat('lightEl') * math.pi / 180;
    final light = vm.Vector3(
      math.cos(el) * math.sin(az),
      math.sin(el),
      math.cos(el) * math.cos(az),
    );
    _sky?.sunDirection = light;

    material.setUniformBlockFromFloats('Terrain', [
      v.getFloat('water'), v.getFloat('snow'), //
      v.getFloat('rockSlope'), v.getFloat('contour'),
      light.x, light.y, light.z, 0, //
      camera.position.x, camera.position.y, camera.position.z, 0,
      ..._linear(v.getColor('water_c')),
      ..._linear(v.getColor('grass_c')),
      ..._linear(v.getColor('snow_c')),
    ]);
  }

  PerspectiveCamera _buildCamera() {
    final az = _azimuth * math.pi / 180;
    final el = _elevation * math.pi / 180;
    return _camera = PerspectiveCamera(
      fovRadiansY: 45 * math.pi / 180,
      position: vm.Vector3(
        _distance * math.cos(el) * math.sin(az),
        _distance * math.sin(el),
        _distance * math.cos(el) * math.cos(az),
      ),
      target: vm.Vector3(0, 0.3, 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_material == null) {
      return const SizedBox.expand(
        child: Center(child: Text('Loading scene...')),
      );
    }
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          setState(
            () =>
                _distance = (_distance * math.exp(event.scrollDelta.dy * 0.001))
                    .clamp(2.0, 14.0),
          );
        }
      },
      child: GestureDetector(
        onScaleStart: (_) => _lastScale = 1,
        onScaleUpdate: (details) => setState(() {
          _azimuth = (_azimuth - details.focalPointDelta.dx * 0.4) % 360;
          _elevation = (_elevation + details.focalPointDelta.dy * 0.4).clamp(
            5.0,
            85.0,
          );
          if (details.pointerCount > 1) {
            _distance = (_distance * _lastScale / details.scale).clamp(
              2.0,
              14.0,
            );
            _lastScale = details.scale;
          }
        }),
        child: SceneView(
          _scene,
          onTick: (elapsed, _) => _onTick(),
          cameraBuilder: (elapsed) => _buildCamera(),
        ),
      ),
    );
  }
}
