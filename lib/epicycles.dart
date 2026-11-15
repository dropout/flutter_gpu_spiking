import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'app/controls.dart';
import 'app/idea_view.dart';
import 'app/orbit_camera.dart';
import 'app/scene_math.dart';

/// Fourier epicycles: any closed curve is a sum of rotating circles.
///
/// The curve is sampled as complex numbers z(τ) = x + iy, and its discrete
/// Fourier transform gives one complex coefficient c_k per frequency k, so
///
///     z(τ) = Σ c_k · e^(2πi·k·τ)
///
/// Each term is a circle of radius |c_k| turning k times per cycle, centred on
/// the tip of the circle before it. Chain them, biggest first, and the last
/// tip retraces the curve. Fewer terms give a blurrier curve; more terms sharpen
/// the corners.
///
/// Everything is drawn with one [InstancedMesh] of stretched cuboids, used as
/// line segments: the target curve, every circle, every arm, and the trail.
/// The trail can be extruded along the depth axis, turning time into a helix.
class EpicyclesPage extends StatelessWidget {
  const EpicyclesPage({super.key});

  @override
  Widget build(BuildContext context) => IdeaView(
    create: _Epicycles.new,
    camera: const CameraPose(azimuth: 0, elevation: 5, distance: 11, fov: 40),
    background: (const Color(0xFF1C1033), const Color(0xFF05030C)),
  );
}

class _Epicycles extends Idea {
  _Epicycles(Scene scene, this.camera) {
    scene.add(Node()..addComponent(InstancedMeshComponent(_lines)));
    scene.add(_pen);

    for (var s = 0; s < _circleSegments; s++) {
      final a = 2 * math.pi * s / _circleSegments;
      _circleCos[s] = math.cos(a);
      _circleSin[s] = math.sin(a);
    }
    _loadPreset(0);
    _resize();
  }

  /// Samples of the target curve, and so also of the DFT.
  static const int samples = 256;

  /// Straight segments that approximate each circle.
  static const int _circleSegments = 40;

  /// World-space half-extent the curves are scaled to fit.
  static const double _extent = 3;

  static const _presetNames = [
    'Heart',
    'Star',
    'Square',
    'Trefoil',
    'Lemniscate',
    'Butterfly',
  ];

  final OrbitCamera camera;

  /// The preset curve shown, or -1 after drawing one's own.
  final preset = ChoiceKnob(
    'Curve',
    0,
    options: [for (var i = 0; i < _presetNames.length; i++) i],
    name: (i) => _presetNames[i],
  );

  /// How many circles are chained, biggest first.
  final terms = IntKnob('Terms', 30, min: 1, max: 150);
  final period = FloatKnob('Seconds per cycle', 12, min: 2, max: 60, digits: 1);
  final showCircles = BoolKnob('Show circles', true);
  final showTarget = BoolKnob('Show target curve', true);

  /// Length of the trail, as a fraction of a cycle.
  final trailFraction = FloatKnob(
    'Length (cycles)',
    1,
    min: 0.05,
    max: 1,
    digits: 2,
  );
  final trailPoints = IntKnob('Points', 1024, min: 128, max: 4096, step: 128);

  /// Depth, in world units, that one full cycle of trail is stretched over.
  final extrude = FloatKnob(
    'Extrude (depth per cycle)',
    0,
    min: 0,
    max: 12,
    digits: 1,
  );

  /// Line thickness in world units.
  final thickness = FloatKnob('Thickness', 0.014, min: 0.004, max: 0.05);
  final hue = FloatKnob('Hue', 0.55, min: 0, max: 1, digits: 2);
  final hueSpread = FloatKnob('Hue spread', 0.5, min: 0, max: 1, digits: 2);

  @override
  late final List<Control> controls = [
    Section('Curve'),
    preset,
    Buttons({'Draw your own': _startDrawing}),
    Section('Circles'),
    terms,
    period,
    showCircles,
    showTarget,
    Section('Trail'),
    trailFraction,
    trailPoints,
    extrude,
    thickness,
    hue,
    hueSpread,
  ];

  @override
  Map<String, String> get stats => {
    'Segments': '$_segmentCount',
    'Curve': preset.value >= 0 ? _presetNames[preset.value] : 'Drawn',
    'Terms': '${terms.value}',
    'Cycles': _elapsed.toStringAsFixed(2),
    'Biggest': [
      for (var i = 0; i < math.min(5, _termCount); i++)
        math.sqrt(_re[i] * _re[i] + _im[i] * _im[i]).toStringAsFixed(2),
    ].join(' '),
  };

  final InstancedMesh _lines = InstancedMesh(
    geometry: CuboidGeometry(vm.Vector3(1, 1, 1)),
    material: PhysicallyBasedMaterial()
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.6,
  );
  final Node _pen = Node(
    mesh: Mesh(
      SphereGeometry(radius: 0.5, segments: 12, rings: 8),
      PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(1, 0.9, 0.5, 1)
        ..roughnessFactor = 0.3,
    ),
  );

  // The target curve, in world units.
  final Float64List _curveX = Float64List(samples);
  final Float64List _curveY = Float64List(samples);

  // Fourier terms, sorted by radius, biggest first.
  int _termCount = 0;
  final Float64List _re = Float64List(samples);
  final Float64List _im = Float64List(samples);
  final Float64List _freq = Float64List(samples);

  final Float64List _circleCos = Float64List(_circleSegments);
  final Float64List _circleSin = Float64List(_circleSegments);

  /// Cycles elapsed since the curve was loaded. The trail only exists for the
  /// part of it that has been drawn, so the figure builds itself up.
  double _elapsed = 0;

  // The knob values the instances were last laid out and colored for.
  int _loadedPreset = -1;
  int _segmentCount = 0;
  int _usedTerms = 0;
  int _usedTrail = 0;
  double _usedHue = -1;
  double _usedSpread = -1;

  // Index ranges into the instances.
  int get _circlesStart => samples;
  int get _armsStart => _circlesStart + _usedTerms * _circleSegments;
  int get _trailStart => _armsStart + _usedTerms;

  void _resize() {
    _usedTerms = terms.value;
    _usedTrail = trailPoints.value;
    _segmentCount = _trailStart + _usedTrail - 1;
    _lines.clearInstances();
    final identity = vm.Matrix4.identity();
    for (var i = 0; i < _segmentCount; i++) {
      _lines.addInstance(identity);
    }
    _recolor();
  }

  void _recolor() {
    _usedHue = hue.value;
    _usedSpread = hueSpread.value;
    final color = vm.Vector4.zero();
    void paint(int from, int count, double r, double g, double b) {
      color.setValues(r, g, b, 1);
      for (var i = 0; i < count; i++) {
        _lines.setInstanceColor(from + i, color);
      }
    }

    paint(0, samples, 0.2, 0.22, 0.3); // target curve
    paint(_circlesStart, _usedTerms * _circleSegments, 0.03, 0.22, 0.4);
    paint(_armsStart, _usedTerms, 0.7, 0.7, 0.85);
    for (var j = 0; j < _usedTrail - 1; j++) {
      final age = j / (_usedTrail - 1);
      hsv(_usedHue + age * _usedSpread, 0.8, 1 - 0.7 * age, color);
      _lines.setInstanceColor(_trailStart + j, color);
    }
  }

  void _loadPreset(int index) {
    preset.value = index;
    _loadedPreset = index;
    final raw = switch (index) {
      0 => _heart(),
      1 => _star(),
      2 => _square(),
      3 => _trefoil(),
      4 => _lemniscate(),
      _ => _butterfly(),
    };
    _setCurve(raw.$1, raw.$2, normalise: true);
  }

  // Preset curves, as dense point lists. They are resampled by arc length, so
  // their own parametrisation does not matter.
  (List<double>, List<double>) _param(
    int n,
    double t1,
    (double, double) Function(double t) f,
  ) {
    final xs = <double>[];
    final ys = <double>[];
    for (var i = 0; i < n; i++) {
      final p = f(t1 * i / n);
      xs.add(p.$1);
      ys.add(p.$2);
    }
    return (xs, ys);
  }

  (List<double>, List<double>) _heart() => _param(
    1024,
    2 * math.pi,
    (t) => (
      16 * math.pow(math.sin(t), 3).toDouble(),
      13 * math.cos(t) -
          5 * math.cos(2 * t) -
          2 * math.cos(3 * t) -
          math.cos(4 * t),
    ),
  );

  (List<double>, List<double>) _trefoil() => _param(
    1024,
    2 * math.pi,
    (t) =>
        (math.sin(t) + 2 * math.sin(2 * t), math.cos(t) - 2 * math.cos(2 * t)),
  );

  (List<double>, List<double>) _lemniscate() =>
      _param(1024, 2 * math.pi, (t) => (math.cos(t), math.sin(2 * t) / 2));

  (List<double>, List<double>) _butterfly() => _param(2048, 24 * math.pi, (t) {
    final r =
        math.exp(math.sin(t)) -
        2 * math.cos(4 * t) +
        math.pow(math.sin((2 * t - math.pi) / 24), 5).toDouble();
    return (math.sin(t) * r, math.cos(t) * r);
  });

  (List<double>, List<double>) _polygon(List<(double, double)> corners) {
    final xs = <double>[];
    final ys = <double>[];
    for (var i = 0; i < corners.length; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % corners.length];
      for (var s = 0; s < 100; s++) {
        xs.add(a.$1 + (b.$1 - a.$1) * s / 100);
        ys.add(a.$2 + (b.$2 - a.$2) * s / 100);
      }
    }
    return (xs, ys);
  }

  (List<double>, List<double>) _star() => _polygon([
    for (var i = 0; i < 10; i++)
      (
        (i.isEven ? 1.0 : 0.42) * math.sin(i * math.pi / 5),
        (i.isEven ? 1.0 : 0.42) * math.cos(i * math.pi / 5),
      ),
  ]);

  (List<double>, List<double>) _square() =>
      _polygon([(-1, -1), (1, -1), (1, 1), (-1, 1)]);

  // Drawing one's own curve. While drawing, only the stroke is shown.
  bool _drawing = false;
  bool _hidden = false;
  final List<vm.Vector2> _stroke = [];

  @override
  bool get capturesDrags => _drawing;

  @override
  String? get hint => _drawing ? 'Draw a closed shape, then let go' : null;

  void _startDrawing() {
    // Face the plane head on, so the stroke follows the finger.
    camera.azimuth.value = 0;
    camera.elevation.value = camera.elevation.min;
    _drawing = true;
    _hidden = true;
    _stroke.clear();
    notifyListeners();
  }

  /// Adds the point where [ray] meets the z = 0 plane the curves live in.
  void _addPoint(vm.Ray ray) {
    final hit = hitPlane(ray, vm.Vector3(0, 0, 1));
    if (hit != null) _stroke.add(vm.Vector2(hit.x, hit.y));
  }

  @override
  void onDragStart(vm.Ray ray) {
    _stroke.clear();
    _addPoint(ray);
  }

  /// Shows the stroke so far as the target curve.
  @override
  void onDragUpdate(vm.Ray ray) {
    _addPoint(ray);
    if (_stroke.length < 2) return;
    _resample(
      [for (final p in _stroke) p.x],
      [for (final p in _stroke) p.y],
      closed: true,
    );
    _hidden = false;
  }

  /// Uses the finished stroke as the curve, unless it was too short.
  @override
  void onDragEnd() {
    if (_stroke.length >= 8) {
      preset.value = -1;
      _loadedPreset = -1;
      _setCurve(
        [for (final p in _stroke) p.x],
        [for (final p in _stroke) p.y],
        normalise: true,
      );
    } else {
      _loadPreset(math.max(0, preset.value));
    }
    _drawing = false;
    notifyListeners();
  }

  void _setCurve(List<double> xs, List<double> ys, {required bool normalise}) {
    _resample(xs, ys, closed: true);
    _hidden = false;

    if (normalise) {
      var cx = 0.0, cy = 0.0;
      for (var i = 0; i < samples; i++) {
        cx += _curveX[i];
        cy += _curveY[i];
      }
      cx /= samples;
      cy /= samples;
      var maxR = 1e-9;
      for (var i = 0; i < samples; i++) {
        _curveX[i] -= cx;
        _curveY[i] -= cy;
        maxR = math.max(
          maxR,
          math.sqrt(_curveX[i] * _curveX[i] + _curveY[i] * _curveY[i]),
        );
      }
      final scale = _extent / maxR;
      for (var i = 0; i < samples; i++) {
        _curveX[i] *= scale;
        _curveY[i] *= scale;
      }
    }
    _transform();
    _elapsed = 0;
  }

  /// Resamples a polyline to [samples] points evenly spaced by arc length.
  void _resample(List<double> xs, List<double> ys, {required bool closed}) {
    final n = xs.length;
    final count = closed ? n : n - 1;
    final lengths = Float64List(count + 1);
    for (var i = 0; i < count; i++) {
      final j = (i + 1) % n;
      lengths[i + 1] =
          lengths[i] +
          math.sqrt(math.pow(xs[j] - xs[i], 2) + math.pow(ys[j] - ys[i], 2));
    }
    final total = lengths[count];
    if (total < 1e-9) {
      for (var i = 0; i < samples; i++) {
        _curveX[i] = xs[0];
        _curveY[i] = ys[0];
      }
      return;
    }
    var seg = 0;
    for (var s = 0; s < samples; s++) {
      final target = total * s / samples;
      while (seg < count - 1 && lengths[seg + 1] < target) {
        seg++;
      }
      final span = lengths[seg + 1] - lengths[seg];
      final f = span < 1e-12 ? 0.0 : (target - lengths[seg]) / span;
      final j = (seg + 1) % n;
      _curveX[s] = xs[seg] + (xs[j] - xs[seg]) * f;
      _curveY[s] = ys[seg] + (ys[j] - ys[seg]) * f;
    }
  }

  /// Discrete Fourier transform of the curve, sorted by radius.
  void _transform() {
    final n = samples;
    final entries = <(double, double, int, double)>[];
    for (var k = -n ~/ 2 + 1; k <= n ~/ 2; k++) {
      var re = 0.0, im = 0.0;
      for (var j = 0; j < n; j++) {
        final a = -2 * math.pi * k * j / n;
        final c = math.cos(a), s = math.sin(a);
        // (x + iy)(cos a + i sin a)
        re += _curveX[j] * c - _curveY[j] * s;
        im += _curveX[j] * s + _curveY[j] * c;
      }
      re /= n;
      im /= n;
      entries.add((re, im, k, re * re + im * im));
    }
    entries.sort((a, b) => b.$4.compareTo(a.$4));
    _termCount = entries.length;
    for (var i = 0; i < _termCount; i++) {
      _re[i] = entries[i].$1;
      _im[i] = entries[i].$2;
      _freq[i] = entries[i].$3.toDouble();
    }
  }

  @override
  void update(double dt) {
    if (preset.value >= 0 && preset.value != _loadedPreset) {
      _loadPreset(preset.value);
    }
    final terms = math.min(this.terms.value, _termCount);
    if (this.terms.value != _usedTerms || trailPoints.value != _usedTrail) {
      _resize();
    } else if (hue.value != _usedHue || hueSpread.value != _usedSpread) {
      _recolor();
    }

    if (!_drawing) _elapsed += dt / period.value;
    final tau0 = _elapsed;
    final th = thickness.value;

    // Chain of circle centres at the head of the trail.
    var cx = 0.0, cy = 0.0;
    _lines.updateInstanceTransforms((m) {
      // Target curve.
      final drawTarget = showTarget.value || _drawing;
      for (var i = 0; i < samples; i++) {
        if (!drawTarget || _hidden) {
          m[i].setZero();
          continue;
        }
        final j = (i + 1) % samples;
        _segment(
          m[i],
          _curveX[i],
          _curveY[i],
          0,
          _curveX[j],
          _curveY[j],
          0,
          th * 0.6,
        );
      }

      // Circles and arms.
      final drawChain = !_drawing;
      for (var k = 0; k < _usedTerms; k++) {
        final arm = _armsStart + k;
        final ring = _circlesStart + k * _circleSegments;
        if (!drawChain || k >= terms) {
          m[arm].setZero();
          for (var s = 0; s < _circleSegments; s++) {
            m[ring + s].setZero();
          }
          continue;
        }
        final phase = 2 * math.pi * _freq[k] * tau0;
        final c = math.cos(phase), s = math.sin(phase);
        final dx = _re[k] * c - _im[k] * s;
        final dy = _re[k] * s + _im[k] * c;
        final radius = math.sqrt(_re[k] * _re[k] + _im[k] * _im[k]);

        if (showCircles.value && radius > 0.01) {
          for (var q = 0; q < _circleSegments; q++) {
            final q2 = (q + 1) % _circleSegments;
            _segment(
              m[ring + q],
              cx + radius * _circleCos[q],
              cy + radius * _circleSin[q],
              0,
              cx + radius * _circleCos[q2],
              cy + radius * _circleSin[q2],
              0,
              th * 0.5,
            );
          }
        } else {
          for (var q = 0; q < _circleSegments; q++) {
            m[ring + q].setZero();
          }
        }
        _segment(m[arm], cx, cy, 0, cx + dx, cy + dy, 0, th);
        cx += dx;
        cy += dy;
      }

      // Trail: evaluate the sum at times behind the head. Each term advances
      // by a fixed rotation per trail point, so no trig is needed per point.
      final n = _usedTrail;
      final step = trailFraction.value / (n - 1);
      final px = Float64List(n);
      final py = Float64List(n);
      if (drawChain) {
        for (var k = 0; k < terms; k++) {
          final phase = 2 * math.pi * _freq[k] * tau0;
          var re = _re[k] * math.cos(phase) - _im[k] * math.sin(phase);
          var im = _re[k] * math.sin(phase) + _im[k] * math.cos(phase);
          final rc = math.cos(-2 * math.pi * _freq[k] * step);
          final rs = math.sin(-2 * math.pi * _freq[k] * step);
          for (var j = 0; j < n; j++) {
            px[j] += re;
            py[j] += im;
            final nr = re * rc - im * rs;
            im = re * rs + im * rc;
            re = nr;
          }
        }
      }
      for (var j = 0; j < n - 1; j++) {
        final inst = m[_trailStart + j];
        final age = j * step;
        // Points from before the drawing began do not exist yet.
        if (!drawChain || tau0 - (j + 1) * step < 0) {
          inst.setZero();
          continue;
        }
        final taper = th * 2 * (1 - 0.8 * j / (n - 1));
        _segment(
          inst,
          px[j],
          py[j],
          -extrude.value * age,
          px[j + 1],
          py[j + 1],
          -extrude.value * (age + step),
          taper,
        );
      }

      _pen.localTransform = vm.Matrix4.compose(
        vm.Vector3(cx, cy, 0),
        vm.Quaternion.identity(),
        vm.Vector3.all(drawChain ? th * 8 : 0),
      );
    }, recomputeWinding: false);
  }

  /// Stretches a unit cube into a thin bar from (x0, y0, z0) to (x1, y1, z1).
  static void _segment(
    vm.Matrix4 m,
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
    double thickness,
  ) {
    final dx = x1 - x0, dy = y1 - y0, dz = z1 - z0;
    final length = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (length < 1e-9) {
      m.setZero();
      return;
    }
    final ux = dx / length, uy = dy / length, uz = dz / length;
    // Any reference not parallel to the bar gives a perpendicular axis.
    final rx = 0.0;
    final ry = uz.abs() < 0.9 ? 0.0 : 1.0;
    final rz = uz.abs() < 0.9 ? 1.0 : 0.0;
    var yx = ry * uz - rz * uy;
    var yy = rz * ux - rx * uz;
    var yz = rx * uy - ry * ux;
    final yl = math.sqrt(yx * yx + yy * yy + yz * yz);
    yx /= yl;
    yy /= yl;
    yz /= yl;
    final zx = uy * yz - uz * yy;
    final zy = uz * yx - ux * yz;
    final zz = ux * yy - uy * yx;
    m.setValues(
      ux * length,
      uy * length,
      uz * length,
      0,
      yx * thickness,
      yy * thickness,
      yz * thickness,
      0,
      zx * thickness,
      zy * thickness,
      zz * thickness,
      0,
      (x0 + x1) / 2,
      (y0 + y1) / 2,
      (z0 + z1) / 2,
      1,
    );
  }
}
