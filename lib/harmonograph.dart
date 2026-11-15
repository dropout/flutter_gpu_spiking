import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'app/controls.dart';
import 'app/idea_view.dart';
import 'app/orbit_camera.dart';
import 'app/scene_math.dart';

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
class HarmonographPage extends StatelessWidget {
  const HarmonographPage({super.key});

  @override
  Widget build(BuildContext context) => IdeaView(
    create: (scene, _) => _Harmonograph(scene),
    camera: const CameraPose(azimuth: 30, elevation: 25, distance: 9),
    orbitSpeed: 8,
    background: (const Color(0xFF14102B), const Color(0xFF03020A)),
  );
}

class _Harmonograph extends Idea {
  _Harmonograph(Scene scene) {
    scene.add(Node()..addComponent(InstancedMeshComponent(_trail)));
  }

  /// World-space half-extent of the figure at full amplitude.
  static const double _extent = 2.6;

  // Frequency ratios of the x, y and z axes.
  final ratioX = IntKnob('X ratio', 3, min: 1, max: 9);
  final ratioY = IntKnob('Y ratio', 2, min: 1, max: 9);
  final ratioZ = IntKnob('Z ratio', 5, min: 1, max: 9);

  /// Offset, in ratio units, of each axis's second oscillator. Small values
  /// make the knot slowly precess.
  final detune = FloatKnob('Detune', 0.02, min: 0, max: 0.2);

  /// Decay rate in 1/s. At zero the figure never fades.
  final damping = FloatKnob('Damping', 0.02, min: 0, max: 0.2);

  /// Angular speed of the base oscillation, in radians per second.
  final speed = FloatKnob('Speed', 1, min: 0, max: 5, digits: 2);

  /// Restart once the figure has faded, or after two minutes undamped.
  final autoRestart = BoolKnob('Restart when faded', true);

  /// How much history, in seconds of oscillation, the trail spans.
  final trailSeconds = FloatKnob('Length (s)', 18, min: 1, max: 60, digits: 1);
  final points = IntKnob('Points', 4000, min: 500, max: 12000, step: 500);

  /// Sphere radius at the pen, in world units. The tail tapers to nothing.
  final thickness = FloatKnob('Thickness', 0.045, min: 0.01, max: 0.12);

  /// Hue of the pen; the trail cycles through hues behind it.
  final hue = FloatKnob('Hue', 0.55, min: 0, max: 1, digits: 2);
  final hueSpread = FloatKnob('Hue spread', 0.35, min: 0, max: 1, digits: 2);

  /// Phases of the two oscillators on each of the three axes.
  List<double> _phases = [0, 1.1, 0.4, 2.3, 1.7, 0.2];

  @override
  late final List<Control> controls = [
    Section('Oscillators'),
    ratioX,
    ratioY,
    ratioZ,
    detune,
    damping,
    speed,
    Buttons({'Randomize': _randomize, 'Redraw': () => _time = 0}),
    autoRestart,
    Section('Trail'),
    trailSeconds,
    points,
    thickness,
    hue,
    hueSpread,
  ];

  @override
  Map<String, String> get stats => {
    'Points': '$_count',
    'Ratios': '${ratioX.value}:${ratioY.value}:${ratioZ.value}',
    'Time': '${_time.toStringAsFixed(1)} s',
    'Amplitude': '${(_amplitude * 100).toStringAsFixed(0)}%',
  };

  final InstancedMesh _trail = InstancedMesh(
    geometry: SphereGeometry(radius: 0.5, segments: 8, rings: 5),
    material: PhysicallyBasedMaterial()
      ..metallicFactor = 0.2
      ..roughnessFactor = 0.4,
  );
  int _count = 0;

  /// Time since the drawing started, in seconds. Accumulated rather than
  /// derived from the clock, so changing the speed slider never jumps.
  double _time = 0;
  double _amplitude = 1;

  void _randomize() {
    final random = math.Random();
    for (final ratio in [ratioX, ratioY, ratioZ]) {
      ratio.value = 1 + random.nextInt(ratio.max);
    }
    _phases = [for (var i = 0; i < 6; i++) random.nextDouble() * 2 * math.pi];
  }

  void _resize(int n) {
    _count = n;
    _trail.clearInstances();
    final identity = vm.Matrix4.identity();
    for (var i = 0; i < n; i++) {
      _trail.addInstance(identity);
    }
  }

  @override
  void update(double dt) {
    if (points.value != _count) _resize(points.value);
    _time += dt * speed.value;

    final damp = damping.value;
    if (autoRestart.value) {
      final finished = damp > 0 ? math.exp(-damp * _time) < 0.03 : _time > 120;
      if (finished) _time = 0;
    }
    _amplitude = math.exp(-damp * _time);

    final w = [ratioX.value, ratioY.value, ratioZ.value];
    final step = trailSeconds.value / _count;
    final color = vm.Vector4.zero();
    final position = [0.0, 0.0, 0.0];

    _trail.updateInstanceTransforms((transforms) {
      for (var k = 0; k < _count; k++) {
        // The head of the trail is k = 0; later spheres are further back.
        final t = _time - k * step;
        final age = k / _count;

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
              (math.sin(f * t + _phases[axis * 2]) +
                  math.sin((f + detune.value) * t + _phases[axis * 2 + 1]));
        }

        // Taper the tail so the trail reads as a ribbon fading out.
        final r = thickness.value * 2 * (1 - age) * (1 - age * 0.3);
        transforms[k].setScaleTranslation(
          r,
          r,
          r,
          position[0],
          position[1],
          position[2],
        );

        hsv(hue.value + age * hueSpread.value, 0.75, 1.0 - 0.6 * age, color);
        _trail.setInstanceColor(k, color);
      }
    }, recomputeWinding: false);
  }
}
