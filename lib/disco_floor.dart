import 'dart:math' as math;

import 'package:flutter/material.dart' hide Material;
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
  _DiscoFloor? floor;

  @override
  void initState() {
    super.initState();
    // Geometry and materials touch the engine's shader bundle, so they can
    // only be created once the static resources are loaded.
    Scene.initializeStaticResources().then((_) {
      if (!mounted) return;
      setState(() => floor = _DiscoFloor(scene));
    });
  }

  @override
  void dispose() {
    scene.dispose();
    super.dispose();
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
      child: SceneView(
        scene,
        onTick: (elapsed, _) => floor.update(_seconds(elapsed)),
        cameraBuilder: (elapsed) {
          final angle = _seconds(elapsed) * 0.25;
          return PerspectiveCamera(
            position: vm.Vector3(
              math.sin(angle) * 10.5,
              6.0,
              math.cos(angle) * 10.5,
            ),
            target: vm.Vector3.zero(),
          );
        },
      ),
    );
  }
}

double _seconds(Duration d) => d.inMicroseconds / 1e6;

/// Owns the cubes and advances them each frame.
class _DiscoFloor {
  _DiscoFloor(Scene scene) {
    _cubes = InstancedMesh(
      geometry: CuboidGeometry(vm.Vector3(0.56, 0.6, 0.56)),
      material: PhysicallyBasedMaterial()
        ..metallicFactor = 0.1
        ..roughnessFactor = 0.35,
    );
    final identity = vm.Matrix4.identity();
    for (var i = 0; i < _size * _size; i++) {
      _cubes.addInstance(identity);
    }
    // An InstancedMesh rides on a component rather than on Node(mesh:).
    scene.add(Node()..addComponent(InstancedMeshComponent(_cubes)));
  }

  static const int _size = 18;
  static const double _spacing = 0.62;

  final FastNoiseLite _noise = FastNoiseLite(seed: 42)
    ..noiseType = NoiseType.openSimplex2
    ..frequency = 1.0;

  late final InstancedMesh _cubes;

  void update(double t) {
    const half = (_size - 1) / 2;
    final color = vm.Vector4.zero();

    _cubes.updateInstanceTransforms((transforms) {
      for (var row = 0; row < _size; row++) {
        for (var col = 0; col < _size; col++) {
          final index = row * _size + col;
          final x = (col - half) * _spacing;
          final z = (row - half) * _spacing;
          final distance = math.sqrt(x * x + z * z);

          // A ring that travels outwards from the center, roughened up with
          // drifting noise so it never looks perfectly regular.
          final ring = math.sin(distance * 1.5 - t * 4.0);
          final drift = _noise.getNoise3(x * 0.35, z * 0.35, t * 0.4);
          final y = 0.3 * ring + 0.35 * drift;
          transforms[index].setTranslationRaw(x, y, z);

          final glow = 0.5 + 0.5 * ring;
          _hsv(
            distance * 0.07 - t * 0.12 + drift * 0.25,
            0.85,
            0.06 + 0.94 * glow * glow,
            color,
          );
          _cubes.setInstanceColor(index, color);
        }
      }
    }, recomputeWinding: false); // translation only, never mirrored
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
