import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/noise.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'app/controls.dart';
import 'app/idea_view.dart';
import 'app/orbit_camera.dart';
import 'app/scene_math.dart';

/// A flutter_scene investigation: a procedurally animated floor of cubes.
///
/// The floor is one [InstancedMesh] of cubes, a single draw call, whose
/// per-instance transforms and colors are rewritten every frame. There are no
/// model or texture assets.
class DiscoFloorPage extends StatelessWidget {
  const DiscoFloorPage({super.key});

  @override
  Widget build(BuildContext context) => IdeaView(
    create: (scene, _) => _DiscoFloor(scene),
    camera: const CameraPose(azimuth: 45, elevation: 43, distance: 5.8),
    cameraPresets: const [
      CameraPose(
        name: 'Default',
        azimuth: 45,
        elevation: 35,
        distance: 12.873,
        fov: 20,
      ),
      CameraPose(
        name: 'Isometric',
        azimuth: 45,
        elevation: 35,
        distance: 16,
        fov: 20,
      ),
      CameraPose(name: 'Top-down', azimuth: 45, elevation: 89, distance: 14),
      CameraPose(
        name: 'Low angle',
        azimuth: 30,
        elevation: 12,
        distance: 9,
        fov: 50,
      ),
      CameraPose(
        name: 'Club',
        azimuth: 200,
        elevation: 20,
        distance: 6,
        fov: 75,
      ),
    ],
    background: (const Color(0xFF2B0B4A), const Color(0xFF05010D)),
  );
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

class _DiscoFloor extends Idea {
  _DiscoFloor(this.scene) {
    // An InstancedMesh rides on a component rather than on Node(mesh:).
    scene.add(Node()..addComponent(InstancedMeshComponent(_cubes)));
  }

  final Scene scene;

  /// The floor covers a fixed square area; density only changes how many cubes
  /// tile it. The cubes keep the fill ratio of the original 0.58 pitch.
  static const double _side = 18 * 0.58;
  static const double _referencePitch = 0.58;

  final waveSpeed = FloatKnob('Wave speed', 0.5, min: 0, max: 5);
  final waveLength = FloatKnob(
    'Wavelength',
    2 * math.pi / 1.5,
    min: 0.5,
    max: 10,
  );
  final waveAmplitude = FloatKnob('Wave amplitude', 0.2, min: 0, max: 0.5);
  final noiseAmplitude = FloatKnob('Noise amplitude', 0.2, min: 0, max: 0.5);
  final noiseDrift = FloatKnob('Noise drift', 0.005, min: 0, max: 1);

  /// Cubes per world unit along each axis. The floor's area is fixed, so this
  /// changes how many cubes tile it, and the cubes shrink or grow to fit.
  final density = FloatKnob('Density (cubes/unit)', 2.5, min: 0.5, max: 5);
  final colorA = ColorKnob('Color A', const Color(0xFF1E1954));
  final colorB = ColorKnob('Color B', const Color(0xFF342B91));
  final environment = FloatKnob('Environment lighting', 0.25, min: 0, max: 2);
  final material = ChoiceKnob(
    'Material',
    DiscoMaterial.current,
    options: DiscoMaterial.values,
    name: (m) => m.label,
  );

  @override
  late final List<Control> controls = [
    Section('Experiment'),
    waveSpeed,
    waveLength,
    waveAmplitude,
    noiseAmplitude,
    noiseDrift,
    density,
    colorA,
    colorB,
    environment,
    Section('Material'),
    material,
  ];

  @override
  Map<String, String> get stats => {
    'Cubes': '${_size * _size}',
    'Wave phase': _phase.toStringAsFixed(2),
    'Height':
        '${_minHeight.toStringAsFixed(3)} .. ${_maxHeight.toStringAsFixed(3)}',
  };

  final FastNoiseLite _noise = FastNoiseLite(seed: 42)
    ..noiseType = NoiseType.openSimplex2
    ..frequency = 1.0;

  final PhysicallyBasedMaterial _material = PhysicallyBasedMaterial();
  late final InstancedMesh _cubes = InstancedMesh(
    geometry: CuboidGeometry(vm.Vector3(0.56, 0.6, 0.56)),
    material: _material,
  );
  DiscoMaterial? _appliedMaterial;

  /// Cubes along one edge of the floor.
  int _size = 0;

  /// Wave phase and noise time are accumulated, rather than derived from the
  /// elapsed time, so changing a speed slider never makes the floor jump.
  double _phase = 0;
  double _noiseTime = 0;
  double _minHeight = 0;
  double _maxHeight = 0;

  void _resize(int size) {
    _size = size;
    _cubes.clearInstances();
    final identity = vm.Matrix4.identity();
    for (var i = 0; i < size * size; i++) {
      _cubes.addInstance(identity);
    }
  }

  @override
  void update(double dt) {
    _phase += dt * waveSpeed.value;
    _noiseTime += dt * noiseDrift.value;
    scene.environmentIntensity = environment.value;

    if (_appliedMaterial != material.value) {
      material.value.applyTo(_material);
      _appliedMaterial = material.value;
    }
    final gridSize = (density.value * _side).round().clamp(2, 200);
    if (gridSize != _size) _resize(gridSize);

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
            distance * (2 * math.pi / waveLength.value) - _phase,
          );
          final drift = _noise.getNoise3(x * 0.15, z * 0.15, _noiseTime);
          final y = waveAmplitude.value * ring + noiseAmplitude.value * drift;
          lo = math.min(lo, y);
          hi = math.max(hi, y);
          // Scale the footprint, keep the thickness.
          transforms[index].setScaleTranslation(
            footprint,
            1,
            footprint,
            x,
            y,
            z,
          );

          final c = Color.lerp(colorA.value, colorB.value, 0.5 - 0.5 * ring)!;
          color.setValues(c.r, c.g, c.b, c.a);
          _cubes.setInstanceColor(index, color);
        }
      }
    }, recomputeWinding: false); // positive scale only, never mirrored
    _minHeight = lo;
    _maxHeight = hi;
  }
}
