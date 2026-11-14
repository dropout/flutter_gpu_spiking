import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter_gpu/gpu.dart' as gpu;

import 'shader_library.dart';
import 'utils.dart';

/// A painter that draws a simple triangle to the screen.
class TrianglePainter extends CustomPainter {

  const TrianglePainter();

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
        clearValue: Colors.deepPurpleAccent.toVector4(),
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
        -0.5, -0.5, // Bottom Left
        0.0, 0.5, // Top Center
        0.5, -0.5, // Bottom Right
      ].toFloat32(),
    );

    // Bind the vertex data. In this case, we won't bother binding an index
    // buffer, since triangles can be drawn directly from the vertex buffer.
    renderPass.bindVertexBuffer(vertices);

    // And finally, we append a draw call.
    renderPass.draw(3);

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

class TrianglePage extends StatefulWidget {
  const TrianglePage({super.key});
  @override
  State<TrianglePage> createState() => _TrianglePageState();
}

class _TrianglePageState extends State<TrianglePage> {

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
        painter: TrianglePainter(),
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
