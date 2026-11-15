import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/material.dart' as material show Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'disco_floor.dart' show CameraParams;

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
class EpicyclesPage extends StatefulWidget {
  const EpicyclesPage({super.key});

  @override
  State<EpicyclesPage> createState() => _EpicyclesPageState();
}

class _EpicyclesPageState extends State<EpicyclesPage> {
  final Scene scene = Scene();
  final EpicycleParams params = EpicycleParams();
  final CameraParams camera = CameraParams()
    ..set(azimuth: 0, elevation: 5, distance: 11, fov: 40);
  final ValueNotifier<EpicycleStats> stats = ValueNotifier(
    const EpicycleStats(),
  );
  _Epicycles? epicycles;
  bool _panelOpen = false;
  bool _drawing = false;
  double _lastScale = 1;
  Size _viewSize = Size.zero;
  final List<vm.Vector2> _stroke = [];

  Duration _lastTick = Duration.zero;
  Duration _lastStatsUpdate = Duration.zero;
  int _framesSinceStats = 0;

  @override
  void initState() {
    super.initState();
    Scene.initializeStaticResources().then((_) {
      if (!mounted) return;
      setState(() => epicycles = _Epicycles(scene, params));
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

  void _onTick(_Epicycles epi, Duration elapsed) {
    final dt = _seconds(elapsed - _lastTick).clamp(0.0, 1 / 20);
    _lastTick = elapsed;
    if (params.autoOrbit && !_drawing) {
      camera.set(azimuth: camera.azimuth + dt * 8);
    }
    epi.update(dt);

    _framesSinceStats++;
    final window = _seconds(elapsed - _lastStatsUpdate);
    if (window >= 0.25) {
      stats.value = EpicycleStats(
        fps: _framesSinceStats / window,
        frameMs: window * 1000 / _framesSinceStats,
        segments: epi.segmentCount,
        cycle: epi.elapsed,
        largest: epi.largestRadii,
      );
      _lastStatsUpdate = elapsed;
      _framesSinceStats = 0;
    }
  }

  /// Where a pointer lands on the z = 0 plane the curves live in.
  vm.Vector2? _planePoint(Offset local) {
    if (_viewSize.isEmpty) return null;
    final ray = camera.build().screenPointToRay(local, _viewSize);
    final dz = ray.direction.z;
    if (dz.abs() < 1e-6) return null;
    final s = -ray.origin.z / dz;
    if (s < 0) return null;
    final hit = ray.origin + ray.direction * s;
    return vm.Vector2(hit.x, hit.y);
  }

  void _startDrawing() {
    // Face the plane head on, so the stroke follows the finger.
    camera.set(azimuth: 0, elevation: CameraParams.minElevation);
    setState(() {
      _drawing = true;
      _panelOpen = false;
      _stroke.clear();
    });
    epicycles?.beginPreview();
  }

  @override
  Widget build(BuildContext context) {
    final epi = epicycles;
    if (epi == null) {
      return const SizedBox.expand(
        child: Center(child: Text('Loading scene...')),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          radius: 1.1,
          colors: [Color(0xFF1C1033), Color(0xFF05030C)],
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
                  onScaleStart: (details) {
                    _lastScale = 1;
                    if (_drawing) {
                      _stroke.clear();
                      final p = _planePoint(details.localFocalPoint);
                      if (p != null) _stroke.add(p);
                    }
                  },
                  onScaleUpdate: (details) {
                    if (_drawing) {
                      final p = _planePoint(details.localFocalPoint);
                      if (p != null) {
                        _stroke.add(p);
                        epi.previewStroke(_stroke);
                      }
                      return;
                    }
                    camera.orbitBy(details.focalPointDelta);
                    if (details.pointerCount > 1) {
                      camera.zoomBy(_lastScale / details.scale);
                      _lastScale = details.scale;
                    }
                  },
                  onScaleEnd: (_) {
                    if (!_drawing) return;
                    if (_stroke.length >= 8) {
                      epi.setStroke(_stroke);
                    } else {
                      epi.loadPreset(params.preset);
                    }
                    setState(() => _drawing = false);
                  },
                  child: SceneView(
                    scene,
                    onTick: (elapsed, _) => _onTick(epi, elapsed),
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
                  if (_drawing)
                    const Positioned(
                      top: 16,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Center(
                          child: Text(
                            'Draw a closed shape, then let go',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ),
                      ),
                    )
                  else ...[
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _ControlPanel(
                        params: params,
                        epicycles: epi,
                        camera: camera,
                        open: _panelOpen,
                        onToggle: () =>
                            setState(() => _panelOpen = !_panelOpen),
                        onDraw: _startDrawing,
                      ),
                    ),
                    if (!_panelOpen)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: _StatsOverlay(params: params, stats: stats),
                      ),
                  ],
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
class EpicycleParams extends ChangeNotifier {
  static const presetNames = [
    'Heart',
    'Star',
    'Square',
    'Trefoil',
    'Lemniscate',
    'Butterfly',
  ];

  /// The preset curve shown, or -1 after drawing one's own.
  int preset = 0;

  /// How many circles are chained, biggest first.
  int terms = 30;

  /// Seconds per cycle.
  double period = 12;

  /// Length of the trail, as a fraction of a cycle.
  double trailFraction = 1.0;

  /// Points along the trail.
  int trailPoints = 1024;

  /// Line thickness in world units.
  double thickness = 0.014;

  /// Depth, in world units, that one full cycle of trail is stretched over.
  double extrude = 0;

  bool showTarget = true;
  bool showCircles = true;
  double hue = 0.55;
  double hueSpread = 0.5;
  bool autoOrbit = false;

  static const int maxTerms = 150;

  void update(void Function() change) {
    change();
    notifyListeners();
  }

  void reset() => update(() {
    terms = 30;
    period = 12;
    trailFraction = 1.0;
    trailPoints = 1024;
    thickness = 0.014;
    extrude = 0;
    showTarget = true;
    showCircles = true;
    hue = 0.55;
    hueSpread = 0.5;
    autoOrbit = false;
  });
}

class EpicycleStats {
  const EpicycleStats({
    this.fps = 0,
    this.frameMs = 0,
    this.segments = 0,
    this.cycle = 0,
    this.largest = const [],
  });

  final double fps;
  final double frameMs;
  final int segments;

  /// Cycles drawn since the curve was loaded.
  final double cycle;

  /// Radii of the biggest few circles.
  final List<double> largest;
}

double _seconds(Duration d) => d.inMicroseconds / 1e6;

/// The curve, its Fourier terms, and the segments that draw everything.
class _Epicycles {
  _Epicycles(Scene scene, this.params) {
    _lines = InstancedMesh(
      geometry: CuboidGeometry(vm.Vector3(1, 1, 1)),
      material: PhysicallyBasedMaterial()
        ..metallicFactor = 0.0
        ..roughnessFactor = 0.6,
    );
    scene.add(Node()..addComponent(InstancedMeshComponent(_lines)));

    _pen = Node(
      mesh: Mesh(
        SphereGeometry(radius: 0.5, segments: 12, rings: 8),
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(1, 0.9, 0.5, 1)
          ..roughnessFactor = 0.3,
      ),
    );
    scene.add(_pen);

    for (var s = 0; s < _circleSegments; s++) {
      final a = 2 * math.pi * s / _circleSegments;
      _circleCos[s] = math.cos(a);
      _circleSin[s] = math.sin(a);
    }
    loadPreset(0);
    _resize();
  }

  /// Samples of the target curve, and so also of the DFT.
  static const int samples = 256;

  /// Straight segments that approximate each circle.
  static const int _circleSegments = 40;

  /// World-space half-extent the curves are scaled to fit.
  static const double _extent = 3;

  final EpicycleParams params;
  late final InstancedMesh _lines;
  late final Node _pen;

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

  /// Whether a stroke is being drawn: only the stroke is shown.
  bool previewing = false;

  /// Cycles elapsed since the curve was loaded. The trail only exists for the
  /// part of it that has been drawn, so the figure builds itself up.
  double elapsed = 0;

  int segmentCount = 0;
  int _usedTerms = 0;
  int _usedTrail = 0;
  double _usedHue = -1;
  double _usedSpread = -1;

  List<double> get largestRadii => [
    for (var i = 0; i < math.min(5, _termCount); i++)
      math.sqrt(_re[i] * _re[i] + _im[i] * _im[i]),
  ];

  // Index ranges into the instances.
  int get _circlesStart => samples;
  int get _armsStart => _circlesStart + _usedTerms * _circleSegments;
  int get _trailStart => _armsStart + _usedTerms;

  void _resize() {
    _usedTerms = params.terms.clamp(1, samples);
    _usedTrail = params.trailPoints;
    segmentCount = _trailStart + _usedTrail - 1;
    _lines.clearInstances();
    final identity = vm.Matrix4.identity();
    for (var i = 0; i < segmentCount; i++) {
      _lines.addInstance(identity);
    }
    _recolor();
  }

  void _recolor() {
    _usedHue = params.hue;
    _usedSpread = params.hueSpread;
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
      _hsv(params.hue + age * params.hueSpread, 0.8, 1 - 0.7 * age, color);
      _lines.setInstanceColor(_trailStart + j, color);
    }
  }

  void loadPreset(int index) {
    params.preset = index;
    previewing = false;
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

  void beginPreview() {
    previewing = true;
    for (var i = 0; i < samples; i++) {
      _curveX[i] = 0;
      _curveY[i] = 0;
    }
    _hidden = true;
  }

  bool _hidden = false;

  /// Shows the stroke so far as the target curve.
  void previewStroke(List<vm.Vector2> stroke) {
    if (stroke.length < 2) return;
    final xs = [for (final p in stroke) p.x];
    final ys = [for (final p in stroke) p.y];
    _resample(xs, ys, closed: true);
    _hidden = false;
  }

  /// Uses a finished stroke as the curve.
  void setStroke(List<vm.Vector2> stroke) {
    params.preset = -1;
    previewing = false;
    _setCurve(
      [for (final p in stroke) p.x],
      [for (final p in stroke) p.y],
      normalise: true,
    );
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
    elapsed = 0;
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

  void update(double dt) {
    final terms = math.min(params.terms, _termCount);
    if (params.terms.clamp(1, samples) != _usedTerms ||
        params.trailPoints != _usedTrail) {
      _resize();
    } else if (params.hue != _usedHue || params.hueSpread != _usedSpread) {
      _recolor();
    }

    if (!previewing) elapsed += dt / params.period;
    final tau0 = elapsed;
    final th = params.thickness;

    // Chain of circle centres at the head of the trail.
    var cx = 0.0, cy = 0.0;
    _lines.updateInstanceTransforms((m) {
      // Target curve.
      final showTarget = params.showTarget || previewing;
      for (var i = 0; i < samples; i++) {
        if (!showTarget || _hidden) {
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
      final drawChain = !previewing;
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

        if (params.showCircles && radius > 0.01) {
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
      final step = params.trailFraction / (n - 1);
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
          -params.extrude * age,
          px[j + 1],
          py[j + 1],
          -params.extrude * (age + step),
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

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.params,
    required this.epicycles,
    required this.camera,
    required this.open,
    required this.onToggle,
    required this.onDraw,
  });

  final EpicycleParams params;
  final _Epicycles epicycles;
  final CameraParams camera;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onDraw;

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
                    _header('Curve'),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        children: [
                          for (
                            var i = 0;
                            i < EpicycleParams.presetNames.length;
                            i++
                          )
                            ChoiceChip(
                              label: Text(EpicycleParams.presetNames[i]),
                              selected: params.preset == i,
                              visualDensity: VisualDensity.compact,
                              onSelected: (_) {
                                epicycles.loadPreset(i);
                                params.update(() {});
                              },
                            ),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: onDraw,
                        icon: const Icon(Icons.draw),
                        label: const Text('Draw your own'),
                      ),
                    ),
                    _header('Circles'),
                    _slider(
                      'Terms',
                      params.terms.toDouble(),
                      1,
                      EpicycleParams.maxTerms.toDouble(),
                      (v) => params.update(() => params.terms = v.round()),
                      digits: 0,
                    ),
                    _slider(
                      'Seconds per cycle',
                      params.period,
                      2,
                      60,
                      (v) => params.update(() => params.period = v),
                      digits: 1,
                    ),
                    _switch(
                      'Show circles',
                      params.showCircles,
                      (v) => params.update(() => params.showCircles = v),
                    ),
                    _switch(
                      'Show target curve',
                      params.showTarget,
                      (v) => params.update(() => params.showTarget = v),
                    ),
                    _header('Trail'),
                    _slider(
                      'Length (cycles)',
                      params.trailFraction,
                      0.05,
                      1,
                      (v) => params.update(() => params.trailFraction = v),
                      digits: 2,
                    ),
                    _slider(
                      'Points',
                      params.trailPoints.toDouble(),
                      128,
                      4096,
                      (v) => params.update(
                        () => params.trailPoints = (v / 128).round() * 128,
                      ),
                      digits: 0,
                    ),
                    _slider(
                      'Extrude (depth per cycle)',
                      params.extrude,
                      0,
                      12,
                      (v) => params.update(() => params.extrude = v),
                      digits: 1,
                    ),
                    _slider(
                      'Thickness',
                      params.thickness,
                      0.004,
                      0.05,
                      (v) => params.update(() => params.thickness = v),
                    ),
                    _slider(
                      'Hue',
                      params.hue,
                      0,
                      1,
                      (v) => params.update(() => params.hue = v),
                      digits: 2,
                    ),
                    _slider(
                      'Hue spread',
                      params.hueSpread,
                      0,
                      1,
                      (v) => params.update(() => params.hueSpread = v),
                      digits: 2,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: params.reset,
                        child: const Text('Reset'),
                      ),
                    ),
                    _header('Camera'),
                    _switch(
                      'Auto orbit',
                      params.autoOrbit,
                      (v) => params.update(() => params.autoOrbit = v),
                    ),
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
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _StatsOverlay extends StatelessWidget {
  const _StatsOverlay({required this.params, required this.stats});

  final EpicycleParams params;
  final ValueNotifier<EpicycleStats> stats;

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
            final name = params.preset >= 0
                ? EpicycleParams.presetNames[params.preset]
                : 'Drawn';
            final lines = [
              'FPS       ${s.fps.toStringAsFixed(1)}',
              'Frame     ${s.frameMs.toStringAsFixed(2)} ms',
              'Segments  ${s.segments}',
              'Curve     $name',
              'Terms     ${params.terms}',
              'Cycles    ${s.cycle.toStringAsFixed(2)}',
              'Biggest   ${s.largest.map((r) => r.toStringAsFixed(2)).join(' ')}',
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
