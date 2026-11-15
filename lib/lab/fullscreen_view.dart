import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' show Vector4;

import 'experiment.dart';
import 'lab_shaders.dart';
import 'lab_textures.dart';
import 'params.dart';

/// Draws a lab fragment shader on a fullscreen quad every frame.
class FullscreenShaderView extends StatefulWidget {
  const FullscreenShaderView({
    super.key,
    required this.fragmentShader,
    required this.lab,
    this.scrollParam,
    this.scrollUnitsPerPixel = 0.001,
    this.renderScale = 1.0,
  });

  final String fragmentShader;
  final LabContext lab;
  final String? scrollParam;
  final double scrollUnitsPerPixel;
  final double renderScale;

  @override
  State<FullscreenShaderView> createState() => _FullscreenShaderViewState();
}

class _FullscreenShaderViewState extends State<FullscreenShaderView> {
  /// Loaded textures by asset path.
  final Map<String, gpu.Texture> _textures = {};

  @override
  void initState() {
    super.initState();
    widget.lab.values.addListener(_onValues);
    _ensureTextures();
  }

  @override
  void dispose() {
    widget.lab.values.removeListener(_onValues);
    super.dispose();
  }

  void _onValues() => _ensureTextures();

  void _ensureTextures() {
    for (final path in widget.lab.values.textureSelection) {
      if (path == null || _textures.containsKey(path)) continue;
      LabTextures.load(path).then(
        (texture) {
          if (!mounted) return;
          setState(() => _textures[path] = texture);
        },
        onError: (Object e) =>
            widget.lab.errors.report('texture:$path', 'Texture $path: $e'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lab = widget.lab;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Listener(
      onPointerSignal: _onPointerSignal,
      onPointerPanZoomUpdate: _onPanZoomUpdate,
      child: RepaintBoundary(
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _FullscreenPainter(
              fragmentShader: widget.fragmentShader,
              lab: lab,
              textures: _textures,
              devicePixelRatio: dpr,
              renderScale: widget.renderScale,
            ),
          ),
        ),
      ),
    );
  }

  /// Adds [pixels] of scroll to the experiment's scroll param, if it has one.
  void _scrollBy(double pixels) {
    final id = widget.scrollParam;
    if (id == null) return;
    final values = widget.lab.values;
    final param = values.params.whereType<FloatParam>().firstWhere(
      (p) => p.id == id,
    );
    values.set(
      id,
      (values.getFloat(id) + pixels * widget.scrollUnitsPerPixel).clamp(
        param.min,
        param.max,
      ),
    );
  }

  // Mouse wheels send scroll signals; the delta is positive when scrolling
  // down, like a page's scroll offset.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) _scrollBy(event.scrollDelta.dy);
  }

  // Trackpads send pan/zoom updates; fingers moving up scroll down.
  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) =>
      _scrollBy(-event.panDelta.dy);
}

class _FullscreenPainter extends CustomPainter {
  _FullscreenPainter({
    required this.fragmentShader,
    required this.lab,
    required this.textures,
    required this.devicePixelRatio,
    required this.renderScale,
  }) : super(repaint: Listenable.merge([lab.time, lab.mouse, lab.values]));

  final String fragmentShader;
  final LabContext lab;
  final Map<String, gpu.Texture> textures;
  final double devicePixelRatio;
  final double renderScale;

  String get _errorKey => 'draw:$fragmentShader';

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    try {
      _draw(canvas, size);
      lab.errors.clear(_errorKey);
    } catch (e) {
      lab.errors.report(_errorKey, '$e');
    }
  }

  void _draw(Canvas canvas, Size size) {
    final values = lab.values;

    // Wait for every selected texture before drawing.
    final textureBindings = <gpu.Texture>[];
    for (final path in values.textureSelection) {
      final texture = path == null ? null : textures[path];
      if (texture == null) return;
      textureBindings.add(texture);
    }

    final scale = devicePixelRatio * renderScale;
    final width = (size.width * scale).round().clamp(1, 8192);
    final height = (size.height * scale).round().clamp(1, 8192);

    final target = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: target,
          loadAction: gpu.LoadAction.clear,
          storeAction: gpu.StoreAction.store,
          clearValue: Vector4(0, 0, 0, 1),
        ),
      ),
    );

    final vertex = LabShaders.shader('LabFullscreenVertex');
    final fragment = LabShaders.shader(fragmentShader);
    final pipeline = gpu.gpuContext.createRenderPipeline(vertex, fragment);
    renderPass.bindPipeline(pipeline);

    final hostBuffer = gpu.gpuContext.createHostBuffer();

    final vertices = hostBuffer.emplace(
      Float32List.fromList(<double>[
        // X, Y (NDC)
        1.0, 1.0,
        -1.0, 1.0,
        -1.0, -1.0,
        1.0, -1.0,
      ]).buffer.asByteData(),
    );
    final indices = hostBuffer.emplace(
      Uint16List.fromList(<int>[0, 1, 2, 0, 2, 3]).buffer.asByteData(),
    );

    final mouse = lab.mouse.value;
    final globals = Float32List.fromList(<double>[
      lab.time.value, width.toDouble(), height.toDouble(), 0, //
      mouse.uv.dx, mouse.uv.dy, mouse.pressed ? 1 : 0, 0,
    ]);
    renderPass.bindUniform(
      fragment.getUniformSlot('Globals'),
      hostBuffer.emplace(globals.buffer.asByteData()),
    );
    renderPass.bindUniform(
      fragment.getUniformSlot('Params'),
      hostBuffer.emplace(values.pack().buffer.asByteData()),
    );

    final sampler = gpu.SamplerOptions(
      minFilter: gpu.MinMagFilter.linear,
      magFilter: gpu.MinMagFilter.linear,
      widthAddressMode: gpu.SamplerAddressMode.repeat,
      heightAddressMode: gpu.SamplerAddressMode.repeat,
    );
    for (var i = 0; i < textureBindings.length; i++) {
      renderPass.bindTexture(
        fragment.getUniformSlot('u_texture$i'),
        textureBindings[i],
        sampler: sampler,
      );
    }

    renderPass.bindVertexBuffer(vertices);
    renderPass.bindIndexBuffer(indices, gpu.IndexType.int16);
    renderPass.drawIndexed(6);
    commandBuffer.submit();

    canvas.save();
    canvas.scale(size.width / width, size.height / height);
    canvas.drawImage(
      target.asImage(),
      Offset.zero,
      Paint()..filterQuality = FilterQuality.low,
    );
    canvas.restore();
  }

  // Always repaint: time, mouse and values change what the shader draws, and a
  // hot-reloaded shader needs a fresh draw.
  @override
  bool shouldRepaint(covariant _FullscreenPainter oldDelegate) => true;
}
