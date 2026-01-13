import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter_gpu/gpu.dart' as gpu;

import 'shader_library.dart';
import 'utils.dart';

/// A painter that draws a quad to the screen.
class QuadPainter extends CustomPainter {

  const QuadPainter();

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
        clearValue: Colors.teal.toVector4(),
      ),
    );

    // Add a render pass encoder to the command buffer so that we can start
    // encoding commands.
    final renderPass = commandBuffer.createRenderPass(renderTarget);

    // Create a RenderPipeline using shaders from the asset.
    final vertex = shaderLibrary['SimpleVertex']!;
    final fragment = shaderLibrary['SimpleFragment']!;
    final pipeline = gpu.gpuContext.createRenderPipeline(vertex, fragment);

    // Bind the pipeline so that subsequent draw calls use it.
    renderPass.bindPipeline(pipeline);

    // Append quick geometry and uniforms to a host buffer that will be
    // automatically uploaded to the GPU later on.
    final hostBuffer = gpu.gpuContext.createHostBuffer();

    // 0, 0 is at the center of the screen.
    final vertices = hostBuffer.emplace(
      <double>[
         0.5,	 0.5, // TR
        -0.5,	 0.5, // TL
        -0.5,	-0.5, // BL
         0.5,	-0.5  // BR
      ].toFloat32()
    );

    // A quad is made up of two triangles, so we need 6 indices.
    final indices = hostBuffer.emplace(
      <int>[
        0, 1, 2,
        0, 2, 3
      ].toUint16()
    );

    // Bind the vertex data.
    renderPass.bindVertexBuffer(vertices, 4);

    // Bind index data since we will be reusing vertices.
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

class QuadPage extends StatefulWidget {
  const QuadPage({super.key});
  @override
  State<QuadPage> createState() => _QuadPageState();
}

class _QuadPageState extends State<QuadPage> {

  late final Ticker ticker;
  Duration elapsed = Duration.zero;

  @override
  void initState() {
    ticker = Ticker(
      (e) => setState(() { elapsed = e; })
    );
    ticker.start();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(
      child: CustomPaint(
        painter: QuadPainter(),
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
