import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter_gpu/gpu.dart' as gpu;

import 'shaders.dart';
import 'utils.dart';


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

    // Create the final destination (1 sample)
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
        clearValue: colorToVector4(Colors.deepPurpleAccent),
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
    final vertices = hostBuffer.emplace(float32(<double>[
      -0.5, -0.5, // Bottom Left
      0.0, 0.5, // Top Center
      0.5, -0.5, // Bottom Right
    ]));

    // Bind the vertex data. In this case, we won't bother binding an index
    // buffer, since triangles can be drawn directly from the vertex buffer.
    renderPass.bindVertexBuffer(vertices, 3);

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

class TrianglePage extends StatefulWidget {
  const TrianglePage({super.key});
  @override
  State<TrianglePage> createState() => _TrianglePageState();
}

class _TrianglePageState extends State<TrianglePage> {

  late final Ticker ticker;

  @override
  void initState() {
    ticker = Ticker(
      (elapsed) {
        setState(() {

        });
      },
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
    ticker.dispose();
    super.dispose();
  }

}
