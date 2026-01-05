import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter_gpu/gpu.dart' as gpu;

import 'shaders.dart';
import 'utils.dart';


class TrianglePainter extends CustomPainter {

  const TrianglePainter();

  @override
  void paint(Canvas canvas, Size size) {

    /// Allocate a new renderable texture.
    final gpu.Texture renderTexture = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate, size.width.toInt(), size.height.toInt(),
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
      coordinateSystem: gpu.TextureCoordinateSystem.renderToTexture
    );

    /// Create the command buffer. This will be used to submit all encoded
    /// commands at the end.
    final commandBuffer = gpu.gpuContext.createCommandBuffer();

    /// Define a render target. This is just a collection of attachments that a
    /// RenderPass will write to.
    final renderTarget = gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(
        texture: renderTexture,
        clearValue: colorToVector4(Colors.deepPurpleAccent),
      ),
      // depthStencilAttachment: gpu.DepthStencilAttachment(texture: depthTexture),
    );

    /// Add a render pass encoder to the command buffer so that we can start
    /// encoding commands.
    final pass = commandBuffer.createRenderPass(renderTarget);

    /// Create a RenderPipeline using shaders from the asset.
    final vertex = shaderLibrary['SimpleVertex']!;
    final fragment = shaderLibrary['SimpleFragment']!;
    final pipeline = gpu.gpuContext.createRenderPipeline(vertex, fragment);

    pass.bindPipeline(pipeline);

    /// (Optional) Configure blending for the first color attachment.
    pass.setColorBlendEnable(true);
    pass.setColorBlendEquation(
      gpu.ColorBlendEquation(
        colorBlendOperation: gpu.BlendOperation.add,
        sourceColorBlendFactor: gpu.BlendFactor.one,
        destinationColorBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
        alphaBlendOperation: gpu.BlendOperation.add,
        sourceAlphaBlendFactor: gpu.BlendFactor.one,
        destinationAlphaBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha
      )
    );

    /// Append quick geometry and uniforms to a host buffer that will be
    /// automatically uploaded to the GPU later on.
    final transients = gpu.gpuContext.createHostBuffer();
    final vertices = transients.emplace(float32(<double>[
      -0.5, -0.5, //
      0, 0.5, //
      0.5, -0.5, //
    ]));


    /// Bind the vertex data. In this case, we won't bother binding an index
    /// buffer.
    pass.bindVertexBuffer(vertices, 3);

    /// And finally, we append a draw call.
    pass.draw();

    /// Submit all of the previously encoded passes. Passes are encoded in the
    /// same order they were created in.
    commandBuffer.submit();

    /// Wrap the Flutter GPU texture as a ui.Image and draw it like normal!
    final image = renderTexture.asImage();

    canvas.drawImage(image, Offset(0, 0), Paint());
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
  Ticker? tick;
  double time = 0;
  double deltaSeconds = 0;
  double seedX = -0.512511498387847167;
  double seedY = 0.521295573094847167;

  @override
  void initState() {
    tick = Ticker(
      (elapsed) {
        setState(() {
          double previousTime = time;
          time = elapsed.inMilliseconds / 1000.0;
          deltaSeconds = previousTime > 0 ? time - previousTime : 0;
        });
      },
    );
    tick!.start();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: TrianglePainter(),
      )
    );
  }
}