import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'app/controls.dart';
import 'app/idea_view.dart';
import 'app/orbit_camera.dart';
import 'app/scene_math.dart';

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
class ChladniPage extends StatelessWidget {
  const ChladniPage({super.key});

  @override
  Widget build(BuildContext context) => IdeaView(
    create: (scene, _) => _Plate(scene),
    camera: const CameraPose(azimuth: 0, elevation: 80, distance: 9),
    background: (const Color(0xFF1B2A33), const Color(0xFF04080B)),
  );
}

class _Plate extends Idea {
  _Plate(Scene scene) {
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
    scene.add(Node()..addComponent(InstancedMeshComponent(_grains)));
    _scatter();
  }

  /// Edge length of the plate in world units.
  static const double side = 6;

  /// |u| below this counts as resting on a nodal line.
  static const double _settledThreshold = 0.05;

  // Resting and active sand colours, linear RGBA.
  static final _restColor = vm.Vector4(0.95, 0.72, 0.36, 1);
  static final _activeColor = vm.Vector4(0.3, 0.2, 0.1, 1);

  /// Mode numbers, the number of half-waves along each axis.
  final n = IntKnob('n (half-waves in x)', 3, min: 1, max: 12);
  final m = IntKnob('m (half-waves in y)', 5, min: 1, max: 12);

  /// Whether the two cosine products are added (symmetric) or subtracted
  /// (antisymmetric). The two give different families of figures.
  final antisymmetric = BoolKnob('Antisymmetric (minus)', false);

  /// Jump to a new random mode every [cycleSeconds].
  final autoCycle = BoolKnob('Auto-cycle modes', false);
  final cycleSeconds = FloatKnob(
    'Cycle every (s)',
    10,
    min: 2,
    max: 30,
    digits: 1,
  );

  /// Largest hop, in plate widths per frame at 60 fps, of a grain on an
  /// antinode.
  final shake = FloatKnob('Shake', 0.03, min: 0.002, max: 0.1);
  final grains = IntKnob('Grains', 12000, min: 1000, max: 30000, step: 1000);

  /// Grain edge length in world units.
  final grainSize = FloatKnob('Grain size', 0.035, min: 0.01, max: 0.1);

  @override
  late final List<Control> controls = [
    Section('Mode'),
    n,
    m,
    antisymmetric,
    autoCycle,
    cycleSeconds,
    Buttons({'Random mode': _randomMode, 'Scatter sand': _scatter}),
    Section('Sand'),
    shake,
    grains,
    grainSize,
  ];

  @override
  Map<String, String> get stats => {
    'Grains': '$_count',
    'Mode': '(${n.value}, ${m.value}) ${antisymmetric.value ? '-' : '+'}',
    'Settled': '${(_settledFraction * 100).toStringAsFixed(0)}%',
  };

  final InstancedMesh _grains = InstancedMesh(
    geometry: CuboidGeometry(vm.Vector3(1, 1, 1)),
    material: PhysicallyBasedMaterial()
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.9,
  );
  final math.Random _random = math.Random(7);

  // Grain positions on the plate, normalised to 0..1 on both axes.
  List<double> _x = const [];
  List<double> _y = const [];

  int get _count => _x.length;
  double _settledFraction = 0;
  double _sinceCycle = 0;

  void _randomMode() {
    final a = 1 + _random.nextInt(n.max);
    var b = 1 + _random.nextInt(n.max);
    if (b == a) b = a % n.max + 1;
    n.value = math.min(a, b);
    m.value = math.max(a, b);
    antisymmetric.value = _random.nextBool();
  }

  /// Re-randomises the grains over the whole plate.
  void _scatter() {
    final count = grains.value;
    _x = List<double>.generate(count, (_) => _random.nextDouble());
    _y = List<double>.generate(count, (_) => _random.nextDouble());
    _grains.clearInstances();
    final identity = vm.Matrix4.identity();
    for (var i = 0; i < count; i++) {
      _grains.addInstance(identity);
    }
  }

  @override
  void update(double dt) {
    if (grains.value != _count) _scatter();

    if (autoCycle.value) {
      _sinceCycle += dt;
      if (_sinceCycle >= cycleSeconds.value) {
        _sinceCycle = 0;
        _randomMode();
      }
    } else {
      _sinceCycle = 0;
    }

    final kn = n.value * math.pi;
    final km = m.value * math.pi;
    final sign = antisymmetric.value ? -1.0 : 1.0;
    // Frame-rate independent: shake is a per-frame step at 60 fps.
    final step = shake.value * dt * 60;
    final size = grainSize.value;
    final color = vm.Vector4.zero();
    var settled = 0;

    _grains.updateInstanceTransforms((transforms) {
      for (var i = 0; i < transforms.length; i++) {
        var x = _x[i];
        var y = _y[i];

        // Mode shape at the grain, normalised so |u| is at most 1.
        final u =
            0.5 *
            (math.cos(kn * x) * math.cos(km * y) +
                sign * math.cos(km * x) * math.cos(kn * y));
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
        transforms[i].setScaleTranslation(
          size,
          size,
          size,
          (x - 0.5) * side,
          lift,
          (y - 0.5) * side,
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

    _settledFraction = _count == 0 ? 0 : settled / _count;
  }
}
