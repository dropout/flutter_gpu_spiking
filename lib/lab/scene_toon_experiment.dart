import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'experiment.dart';
import 'lab_shaders.dart';
import 'lab_textures.dart';
import 'params.dart';

/// A flutter_scene experiment: a [ShaderMaterial] with a custom fragment shader
/// (`shaders/lab/scene_toon.frag`) on a sphere or torus.
///
/// Scene values reach the shader through the `SceneInfo` uniform block, rewritten
/// every frame: time, camera position and light direction. The light azimuth and
/// elevation controls are read in Dart to build that direction, so their `Params`
/// slots go unused by the shader.
class ToonSceneExperiment extends LabExperiment {
  const ToonSceneExperiment();

  @override
  String get name => 'Scene: toon';

  @override
  String get description =>
      'flutter_scene ShaderMaterial. Drag to orbit, scroll to zoom. Camera '
      'position, light direction and time are fed to the shader as scene uniforms.';

  @override
  List<LabParam> get params => const [
    TextureParam('texture', 'Texture'),
    FloatParam('bands', 'Light bands', min: 1, max: 12, initial: 4),
    FloatParam('rimPower', 'Rim power', min: 0.5, max: 6, initial: 2.5),
    FloatParam('rimStrength', 'Rim strength', min: 0, max: 2, initial: 0.8),
    FloatParam('texScale', 'Texture scale', min: 0.25, max: 8, initial: 2),
    FloatParam('stripes', 'Stripe pulse', min: 0, max: 1, initial: 0.3),
    ColorParam('tint', 'Tint', initial: Color(0xFFFFFFFF)),
    ColorParam('rim', 'Rim color', initial: Color(0xFF80D8FF)),
    FloatParam('lightAz', 'Light azimuth', min: 0, max: 360, initial: 40),
    FloatParam('lightEl', 'Light elevation', min: -10, max: 90, initial: 45),
    ChoiceParam('shape', 'Shape', options: ['Sphere', 'Torus']),
  ];

  @override
  Widget buildView(BuildContext context, LabContext lab) =>
      _ToonSceneView(key: const ValueKey('toon'), lab: lab);
}

class _ToonSceneView extends StatefulWidget {
  const _ToonSceneView({super.key, required this.lab});

  final LabContext lab;

  @override
  State<_ToonSceneView> createState() => _ToonSceneViewState();
}

class _ToonSceneViewState extends State<_ToonSceneView> {
  static const String _errorKey = 'scene:toon';

  final Scene _scene = Scene();
  ShaderMaterial? _material;
  Node? _sphere;
  Node? _torus;

  String? _boundTexturePath;
  int _textureRequest = 0;

  double _azimuth = 30;
  double _elevation = 20;
  double _distance = 4.2;
  double _lastScale = 1;

  PerspectiveCamera? _camera;

  @override
  void initState() {
    super.initState();
    // Geometry and materials touch the engine's shader bundle, so they can only
    // be created once the static resources are loaded.
    Scene.initializeStaticResources().then((_) async {
      try {
        // Load through flutter_scene's gpu surface so it can read the bundle's
        // shader reflection. This returns the same cached library as
        // LabShaders, so hot reload keeps working.
        final library = await gpu.loadShaderLibraryAsync(kLabBundleAsset);
        if (!mounted) return;
        _build(library!['LabSceneToonFragment']!);
        widget.lab.errors.clear(_errorKey);
      } catch (e) {
        widget.lab.errors.report(_errorKey, '$e');
      }
      if (mounted) setState(() {});
    });
  }

  void _build(gpu.Shader fragment) {
    final material = ShaderMaterial(fragmentShader: fragment);
    final sphere = Node(
      mesh: Mesh(SphereGeometry(radius: 0.8, segments: 64, rings: 32), material),
    );
    final torus = Node(
      mesh: Mesh(
        TorusGeometry(
          radius: 0.7,
          tubeRadius: 0.3,
          radialSegments: 64,
          tubularSegments: 32,
        ),
        material,
      ),
    );
    _scene.add(sphere);
    _scene.add(torus);
    _material = material;
    _sphere = sphere;
    _torus = torus;
  }

  @override
  void dispose() {
    _scene.dispose();
    super.dispose();
  }

  /// Rewrites everything the shader reads from the scene and the panel.
  void _onTick() {
    final material = _material;
    final camera = _camera;
    if (material == null || camera == null) return;
    final lab = widget.lab;
    final values = lab.values;

    _sphere!.visible = values.getChoice('shape') == 0;
    _torus!.visible = values.getChoice('shape') == 1;

    final path = values.getTexture('texture');
    if (path != null && path != _boundTexturePath) {
      _boundTexturePath = path;
      final request = ++_textureRequest;
      LabTextures.load(path).then((texture) {
        if (!mounted || request != _textureRequest) return;
        material.setTexture(
          'u_texture0',
          texture,
          sampler: gpu.SamplerOptions(
            minFilter: gpu.MinMagFilter.linear,
            magFilter: gpu.MinMagFilter.linear,
            widthAddressMode: gpu.SamplerAddressMode.repeat,
            heightAddressMode: gpu.SamplerAddressMode.repeat,
          ),
        );
      }, onError: (Object e) => lab.errors.report('texture:$path', '$e'));
    }

    final az = values.getFloat('lightAz') * math.pi / 180;
    final el = values.getFloat('lightEl') * math.pi / 180;
    final light = vm.Vector3(
      math.cos(el) * math.sin(az),
      math.sin(el),
      math.cos(el) * math.cos(az),
    );
    final mouse = lab.mouse.value;
    material.setUniformBlockFromFloats('SceneInfo', [
      lab.time.value, mouse.uv.dx, mouse.uv.dy, mouse.pressed ? 1 : 0, //
      camera.position.x, camera.position.y, camera.position.z, 0, //
      light.x, light.y, light.z, 0,
    ]);
    material.setUniformBlockFromFloats('Params', values.pack());
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
      target: vm.Vector3.zero(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_material == null) {
      return const SizedBox.expand(
        child: Center(child: Text('Loading scene...')),
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          radius: 1.1,
          colors: [Color(0xFF2B0B4A), Color(0xFF05010D)],
        ),
      ),
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            setState(
              () => _distance = (_distance * math.exp(event.scrollDelta.dy * 0.001))
                  .clamp(1.5, 12.0),
            );
          }
        },
        child: GestureDetector(
          onScaleStart: (_) => _lastScale = 1,
          onScaleUpdate: (details) => setState(() {
            _azimuth = (_azimuth - details.focalPointDelta.dx * 0.4) % 360;
            _elevation = (_elevation + details.focalPointDelta.dy * 0.4).clamp(
              -85.0,
              85.0,
            );
            if (details.pointerCount > 1) {
              _distance = (_distance * _lastScale / details.scale).clamp(
                1.5,
                12.0,
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
      ),
    );
  }
}
