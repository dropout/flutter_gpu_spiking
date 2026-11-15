import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'app/controls.dart';
import 'app/idea_view.dart';
import 'app/orbit_camera.dart';
import 'app/scene_math.dart';

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
class PendulumWavePage extends StatelessWidget {
  const PendulumWavePage({super.key});

  @override
  Widget build(BuildContext context) => IdeaView(
    create: (scene, _) => _Pendulums(scene),
    camera: const CameraPose(azimuth: 25, elevation: 22, distance: 11, fov: 40),
    background: (const Color(0xFF1A1030), const Color(0xFF05030B)),
  );
}

class _Pendulums extends Idea {
  _Pendulums(Scene scene) {
    scene.add(Node()..addComponent(InstancedMeshComponent(_bobs)));
    scene.add(Node()..addComponent(InstancedMeshComponent(_strings)));
    scene.add(_bar);
    _rebuild();
  }

  /// Height of the pivot bar.
  static const double pivotY = 1.3;
  static const double gravity = 9.81;
  static const double _substep = 1 / 480;
  static const int _maxSubstepsPerFrame = 64;

  final count = IntKnob('Count', 16, min: 4, max: 40);

  /// Seconds after which the whole row is back in step.
  final cycleSeconds = FloatKnob('Cycle (s)', 60, min: 10, max: 120, digits: 0);

  /// Swings the first (longest) pendulum makes per cycle. The rest make one
  /// more each.
  final firstSwings = IntKnob('Swings of the longest', 20, min: 5, max: 50);

  /// Release angle, in degrees.
  final amplitude = FloatKnob(
    'Release angle (deg)',
    25,
    min: 2,
    max: 80,
    digits: 0,
  );

  /// Integrate the real pendulum equation instead of the harmonic one.
  final nonlinear = BoolKnob('Real pendulum (sin θ)', false);

  /// Simulation speed relative to real time.
  final timeScale = FloatKnob('Time scale', 1, min: 0, max: 6, digits: 2);

  final bobSize = FloatKnob('Bob size', 0.3, min: 0.1, max: 0.6, digits: 2);
  final hue = FloatKnob('Hue', 0.55, min: 0, max: 1, digits: 2);
  final hueSpread = FloatKnob('Hue spread', 0.45, min: 0, max: 1, digits: 2);

  @override
  late final List<Control> controls = [
    Section('Pendulums'),
    count,
    cycleSeconds,
    firstSwings,
    amplitude,
    nonlinear,
    timeScale,
    Buttons({'Release again': _restart}),
    Section('Look'),
    bobSize,
    hue,
    hueSpread,
  ];

  @override
  Map<String, String> get stats => {
    'Pendulums': '$_count',
    'Model': nonlinear.value ? 'real (sin θ)' : 'harmonic',
    'Time': '${_time.toStringAsFixed(1)} s',
    'Cycle': '${((_time / cycleSeconds.value) % 1 * 100).toStringAsFixed(0)}%',
    'Lengths':
        '${_length.first.toStringAsFixed(2)} .. '
        '${_length.last.toStringAsFixed(2)} m',
  };

  final InstancedMesh _bobs = InstancedMesh(
    geometry: SphereGeometry(radius: 0.5, segments: 16, rings: 10),
    material: PhysicallyBasedMaterial()
      ..metallicFactor = 0.6
      ..roughnessFactor = 0.25,
  );
  final InstancedMesh _strings = InstancedMesh(
    geometry: CuboidGeometry(vm.Vector3(1, 1, 1)),
    material: PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.75, 0.75, 0.85, 1)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.6,
  );
  final Node _bar = Node(
    mesh: Mesh(
      CuboidGeometry(vm.Vector3(1, 1, 1)),
      PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(0.15, 0.15, 0.2, 1)
        ..metallicFactor = 0.8
        ..roughnessFactor = 0.35,
    ),
  );

  // The knob values the row was last built for.
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
  double _time = 0;
  double _substepAccumulator = 0;

  /// Releases every pendulum again from the starting angle.
  void _restart() {
    _time = 0;
    _substepAccumulator = 0;
    final a = amplitude.value * math.pi / 180;
    for (var i = 0; i < _count; i++) {
      _theta[i] = a;
      _thetaDot[i] = 0;
    }
  }

  void _rebuild() {
    _count = count.value;
    _cycle = cycleSeconds.value;
    _firstSwings = firstSwings.value;
    _amplitude = amplitude.value;
    _nonlinear = nonlinear.value;

    _omega = Float64List(_count);
    _length = Float64List(_count);
    _theta = Float64List(_count);
    _thetaDot = Float64List(_count);
    for (var i = 0; i < _count; i++) {
      _omega[i] = 2 * math.pi * (_firstSwings + i) / _cycle;
      _length[i] = gravity / (_omega[i] * _omega[i]);
    }
    _restart();

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
    _hue = hue.value;
    _hueSpread = hueSpread.value;
    final color = vm.Vector4.zero();
    for (var i = 0; i < _count; i++) {
      hsv(_hue + _hueSpread * i / math.max(1, _count - 1), 0.8, 1.0, color);
      _bobs.setInstanceColor(i, color);
    }
  }

  double get _spacing => math.min(0.5, 7.0 / _count);

  @override
  void update(double dt) {
    if (count.value != _count ||
        cycleSeconds.value != _cycle ||
        firstSwings.value != _firstSwings ||
        amplitude.value != _amplitude ||
        nonlinear.value != _nonlinear) {
      _rebuild();
    } else if (hue.value != _hue || hueSpread.value != _hueSpread) {
      _recolor();
    }

    final step = dt * timeScale.value;
    _time += step;
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
    final a = _amplitude * math.pi / 180;
    final bob = bobSize.value;

    _bobs.updateInstanceTransforms((b) {
      _strings.updateInstanceTransforms((s) {
        for (var i = 0; i < _count; i++) {
          final theta = _nonlinear
              ? _theta[i]
              : a * math.cos(_omega[i] * _time);
          final x = (i - halfRow) * spacing;
          final length = _length[i];
          // The pendulums swing along z, out of the plane of the row.
          final bobY = pivotY - length * math.cos(theta);
          final bobZ = length * math.sin(theta);

          b[i].setScaleTranslation(bob, bob, bob, x, bobY, bobZ);
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
