import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/material.dart' as material show Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'controls.dart';
import 'orbit_camera.dart';

/// One experiment shown by [IdeaView]. It adds its nodes to the scene when
/// constructed and advances them in [update].
///
/// Notify listeners when [capturesDrags] or [hint] change.
abstract class Idea extends ChangeNotifier {
  /// The control panel, top to bottom. Reset restores every knob in it.
  List<Control> get controls;

  /// Advances the experiment by [dt] seconds.
  void update(double dt);

  /// Extra lines for the stats overlay, label to value.
  Map<String, String> get stats => const {};

  /// A tap on the view, as a world-space ray from the camera.
  void onTap(vm.Ray ray) {}

  /// While true, drags go to [onDragStart], [onDragUpdate] and [onDragEnd]
  /// instead of orbiting the camera, and the panel is hidden.
  bool get capturesDrags => false;
  void onDragStart(vm.Ray ray) {}
  void onDragUpdate(vm.Ray ray) {}
  void onDragEnd() {}

  /// Text shown across the top of the view.
  String? get hint => null;

  @override
  void dispose() {
    for (final c in controls) {
      if (c is Knob) c.dispose();
    }
    super.dispose();
  }
}

/// Runs an [Idea] in a [SceneView] with an orbit camera, a control panel and
/// a stats overlay.
class IdeaView extends StatefulWidget {
  const IdeaView({
    super.key,
    required this.create,
    required this.camera,
    this.orbitSpeed = 0,
    this.cameraPresets = const [],
    required this.background,
  });

  /// Builds the idea once the scene's static resources are loaded.
  final Idea Function(Scene scene, OrbitCamera camera) create;
  final CameraPose camera;
  final double orbitSpeed;
  final List<CameraPose> cameraPresets;

  /// Inner and outer colors of the radial background. The scene has no
  /// skybox, so it clears to transparent and this shows through.
  final (Color, Color) background;

  @override
  State<IdeaView> createState() => _IdeaViewState();
}

class _IdeaViewState extends State<IdeaView> {
  final Scene scene = Scene();
  late final OrbitCamera camera = OrbitCamera(
    widget.camera,
    orbitSpeed: widget.orbitSpeed,
    presets: widget.cameraPresets,
  );
  final ValueNotifier<List<String>> stats = ValueNotifier(const []);
  Idea? idea;
  bool panelOpen = false;
  Size viewSize = Size.zero;
  double lastScale = 1;

  Duration lastTick = Duration.zero;
  Duration lastStats = Duration.zero;
  int framesSinceStats = 0;

  @override
  void initState() {
    super.initState();
    // Geometry and materials touch the engine's shader bundle, so they can
    // only be created once the static resources are loaded.
    Scene.initializeStaticResources().then((_) {
      if (!mounted) return;
      setState(() {
        idea = widget.create(scene, camera)..addListener(() => setState(() {}));
      });
    });
  }

  @override
  void dispose() {
    idea?.dispose();
    camera.dispose();
    stats.dispose();
    scene.dispose();
    super.dispose();
  }

  void _tick(Idea idea, Duration elapsed) {
    final dt = _seconds(elapsed - lastTick).clamp(0.0, 1 / 20);
    lastTick = elapsed;
    if (!idea.capturesDrags) camera.tick(dt);
    idea.update(dt);

    framesSinceStats++;
    final window = _seconds(elapsed - lastStats);
    if (window >= 0.25) {
      final lines = {
        'FPS': (framesSinceStats / window).toStringAsFixed(1),
        'Frame': '${(window * 1000 / framesSinceStats).toStringAsFixed(2)} ms',
        ...idea.stats,
      };
      final width = lines.keys.map((k) => k.length).reduce(math.max) + 2;
      stats.value = [
        for (final MapEntry(:key, :value) in lines.entries)
          '${key.padRight(width)}$value',
      ];
      lastStats = elapsed;
      framesSinceStats = 0;
    }
  }

  vm.Ray _ray(Offset local) => camera.build().screenPointToRay(local, viewSize);

  @override
  Widget build(BuildContext context) {
    final idea = this.idea;
    if (idea == null) {
      return const SizedBox.expand(
        child: Center(child: Text('Loading scene...')),
      );
    }
    final hint = idea.hint;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          radius: 1.1,
          colors: [widget.background.$1, widget.background.$2],
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
                viewSize = constraints.biggest;
                return GestureDetector(
                  onTapUp: (d) => idea.onTap(_ray(d.localPosition)),
                  onScaleStart: (d) {
                    lastScale = 1;
                    if (idea.capturesDrags) {
                      idea.onDragStart(_ray(d.localFocalPoint));
                    }
                  },
                  onScaleUpdate: (d) {
                    if (idea.capturesDrags) {
                      idea.onDragUpdate(_ray(d.localFocalPoint));
                      return;
                    }
                    camera.orbitBy(d.focalPointDelta);
                    if (d.pointerCount > 1) {
                      camera.zoomBy(lastScale / d.scale);
                      lastScale = d.scale;
                    }
                  },
                  onScaleEnd: (_) {
                    if (idea.capturesDrags) idea.onDragEnd();
                  },
                  child: SceneView(
                    scene,
                    onTick: (elapsed, _) => _tick(idea, elapsed),
                    cameraBuilder: (_) => camera.build(),
                  ),
                );
              },
            ),
          ),
          // Flutter's Material is hidden by the scene import, so reach the
          // widget through a prefix. It gives the sliders something to draw on.
          material.Material(
            type: MaterialType.transparency,
            child: SafeArea(
              child: Stack(
                children: [
                  if (hint != null)
                    Positioned(
                      top: 16,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Center(
                          child: Text(
                            hint,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (!idea.capturesDrags) ...[
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _Panel(
                        open: panelOpen,
                        onToggle: () => setState(() => panelOpen = !panelOpen),
                        controls: [
                          ...idea.controls,
                          Buttons({'Reset': () => resetKnobs(idea.controls)}),
                          ...camera.controls,
                        ],
                      ),
                    ),
                    if (!panelOpen)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: _StatsOverlay(stats: stats),
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

double _seconds(Duration d) => d.inMicroseconds / 1e6;

class _Panel extends StatelessWidget {
  const _Panel({
    required this.open,
    required this.onToggle,
    required this.controls,
  });

  final bool open;
  final VoidCallback onToggle;
  final List<Control> controls;

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
            child: SingleChildScrollView(
              child: ControlList(controls: controls),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatsOverlay extends StatelessWidget {
  const _StatsOverlay({required this.stats});

  final ValueNotifier<List<String>> stats;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ValueListenableBuilder(
          valueListenable: stats,
          builder: (context, lines, _) => Text(
            lines.join('\n'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFamily: 'Menlo',
              fontFamilyFallback: ['Courier', 'monospace'],
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}
