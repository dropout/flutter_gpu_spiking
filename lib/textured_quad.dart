
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:flutter_gpu/gpu.dart' as gpu;

import 'shader_library.dart';
import 'utils.dart';

/// A painter that draws a textured quad using a multisampled render target.
class TexturedQuadPainter extends CustomPainter {

  final ByteData imageByteData;

  const TexturedQuadPainter({
    required this.imageByteData,
  });

  @override
  void paint(Canvas canvas, Size size) {

    // Creating a multisample buffer (4 samples)
    final msaaTexture = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      size.width.toInt(),
      size.height.toInt(),
      sampleCount: 4,
    );

    // Create the final destination texture (1 sample)
    final resolveTexture = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      size.width.toInt(),
      size.height.toInt(),
      sampleCount: 1,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
      coordinateSystem: gpu.TextureCoordinateSystem.renderToTexture
    );

    // Create the command buffer.
    // This will be used to submit all encoded commands at the end.
    final commandBuffer = gpu.gpuContext.createCommandBuffer();

    // Define a render target. This is just a collection of attachments that a
    // RenderPass will write to.
    final renderTarget = gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(
        texture: msaaTexture,
        resolveTexture: resolveTexture,
        storeAction: gpu.StoreAction.multisampleResolve,
        loadAction: gpu.LoadAction.clear,
        clearValue: Colors.indigo.toVector4(),
      ),
    );

    // Add a render pass encoder to the command buffer so that we can start
    // encoding commands.
    final renderPass = commandBuffer.createRenderPass(renderTarget);

    // Create a RenderPipeline using shaders from the asset.
    final vertex = shaderLibrary['TexturedVertex']!;
    final fragment = shaderLibrary['TexturedFragment']!;
    final pipeline = gpu.gpuContext.createRenderPipeline(vertex, fragment);

    // Bind the pipeline so that subsequent draw calls use it.
    renderPass.bindPipeline(pipeline);

    // Append quick geometry and uniforms to a host buffer that will be
    // automatically uploaded to the GPU later on.
    final hostBuffer = gpu.gpuContext.createHostBuffer();

    // 0, 0 is at the center of the screen.
    final vertices = hostBuffer.emplace(
      <double>[
      // X,	   Y,	   Z,	   U,	   V,	   R,	   G,	   B,	   A
         0.5,	 0.5,  0.0,  1.0,  0.0,  1.0,  1.0,  1.0,  1.0, // TR
        -0.5,	 0.5,  0.0,  0.0,  0.0,  1.0,  1.0,  1.0,  1.0, // TL
        -0.5,	-0.5,  0.0,  0.0,  1.0,  1.0,  1.0,  1.0,  1.0, // BL
         0.5,	-0.5,  0.0,  1.0,  1.0,  1.0,  1.0,  1.0,  1.0, // BR
      ].toFloat32()
    );

    final indices = hostBuffer.emplace(
      <int>[
        0, 1, 2,
        0, 2, 3
      ].toUint16()
    );

    gpu.SamplerOptions samplerOptions = gpu.SamplerOptions(
      minFilter: gpu.MinMagFilter.linear,
      magFilter: gpu.MinMagFilter.linear,
      mipFilter: gpu.MipFilter.linear,
      heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    );

    final sampledTexture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      1024,
      1024,
      format: gpu.PixelFormat.r8g8b8a8UNormInt,
      sampleCount: 1,
      enableShaderReadUsage: true,
    );
    sampledTexture.overwrite(imageByteData);
    final textureSlot = pipeline.fragmentShader.getUniformSlot('u_texture');
    renderPass.bindTexture(
      textureSlot,
      sampledTexture,
      sampler: samplerOptions
    );

    // Bind the vertex data. In this case, we won't bother binding an index
    // buffer, since triangles can be drawn directly from the vertex buffer.
    renderPass.bindVertexBuffer(vertices, 4);
    renderPass.bindIndexBuffer(indices, gpu.IndexType.int16, 6);

    // And finally, we append a draw call.
    renderPass.draw();

    // Submit all of the previously encoded passes. Passes are encoded in the
    // same order they were created in.
    commandBuffer.submit();

    // Wrap the Flutter GPU texture as a ui.Image and draw it like normal!
    canvas.drawImage(
      resolveTexture.asImage(),
      Offset(0, 0),
      Paint()
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

class TexturedQuadPage extends StatefulWidget {
  const TexturedQuadPage({super.key});
  @override
  State<TexturedQuadPage> createState() => _TexturedQuadPageState();
}

class _TexturedQuadPageState extends State<TexturedQuadPage> {

  late final Ticker ticker;
  Duration elapsed = Duration.zero;
  ByteData? imageData;

  @override
  void initState() {
    ticker = Ticker(
      (e) => setState(() { elapsed = e; })
    );
    ticker.start();
    rootBundle.load('assets/images/uv_checker_1k.png').then((bd) async {
      ui.decodeImageFromList(bd.buffer.asUint8List(), (img) async {
        imageData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        setState(() {
        });
      });
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (imageData == null) {
      return const SizedBox.expand(
        child: Center(
          child: Text('Loading image...'),
        ),
      );
    }

    return SizedBox.expand(
      child: CustomPaint(
        painter: TexturedQuadPainter(
          imageByteData: imageData!,
        ),
      )
    );
  }

  @override
  void dispose() {
    ticker.stop();
    ticker.dispose();
    super.dispose();
  }

}
