import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import 'shader_library.dart';
import 'utils.dart';

/// A painter that draws a quad to the screen.
class CubePainter extends CustomPainter {

  final double time;
  final ByteData imageByteData;
  final double depthClearValue;

  const CubePainter({
    required this.time,
    required this.imageByteData,
    this.depthClearValue = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {

    // Create the final destination texture (1 sample)
    final resolveTexture = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      size.width.toInt(),
      size.height.toInt(),
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
      coordinateSystem: gpu.TextureCoordinateSystem.renderToTexture
    );

    // Create a depth texture for 3D rendering.
    final gpu.Texture depthTexture = gpu.gpuContext.createTexture(
      gpu.StorageMode.deviceTransient,
      size.width.toInt(),
      size.height.toInt(),
      format: gpu.gpuContext.defaultDepthStencilFormat,
      enableRenderTargetUsage: true,
      coordinateSystem: gpu.TextureCoordinateSystem.renderToTexture
    );

    // Create the command buffer.
    // This will be used to submit all encoded commands at the end.
    final commandBuffer = gpu.gpuContext.createCommandBuffer();

    // Define a render target. This is just a collection of attachments that a
    // RenderPass will write to.
    final renderTarget = gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(
        texture: resolveTexture,
        clearValue: Colors.teal.toVector4(),
      ),
      depthStencilAttachment: gpu.DepthStencilAttachment(
        texture: depthTexture,
        depthClearValue: depthClearValue,
      ),
    );

    // Add a render pass encoder to the command buffer so that we can start
    // encoding commands.
    final renderPass = commandBuffer.createRenderPass(renderTarget);

    // Create a RenderPipeline using shaders from the asset.
    final vertex = shaderLibrary['GenericVertex']!;
    final fragment = shaderLibrary['GenericTexturedFragment']!;
    final pipeline = gpu.gpuContext.createRenderPipeline(vertex, fragment);

    // Bind the pipeline so that subsequent draw calls use it.
    renderPass.bindPipeline(pipeline);

    // Enable depth testing.
    renderPass.setDepthWriteEnable(true);
    renderPass.setDepthCompareOperation(gpu.CompareFunction.less);

    // Append quick geometry and uniforms to a host buffer that will be
    // automatically uploaded to the GPU later on.
    final hostBuffer = gpu.gpuContext.createHostBuffer();

    // Vertex format: X, Y, Z, U, V, R, G, B, A (9 floats per vertex)
    // Cube with different colors on each face, and since we are using
    // different colors per vertex, we need to duplicate vertices for each face
    // in this solution.
    final vertices = hostBuffer.emplace(
      <double>[
        // Front (red)
        -0.5,  0.5,  0.5,  0.0, 1.0,  1.0, 0.0, 0.0, 1.0, // 0 TL
         0.5,  0.5,  0.5,  1.0, 1.0,  1.0, 0.0, 0.0, 1.0, // 1 TR
         0.5, -0.5,  0.5,  1.0, 0.0,  1.0, 0.0, 0.0, 1.0, // 2 BR
        -0.5, -0.5,  0.5,  0.0, 0.0,  1.0, 0.0, 0.0, 1.0, // 3 BL

        // Back (green)
         0.5,  0.5, -0.5,  0.0, 1.0,  0.0, 1.0, 0.0, 1.0, // 4 TL
        -0.5,  0.5, -0.5,  1.0, 1.0,  0.0, 1.0, 0.0, 1.0, // 5 TR
        -0.5, -0.5, -0.5,  1.0, 0.0,  0.0, 1.0, 0.0, 1.0, // 6 BR
         0.5, -0.5, -0.5,  0.0, 0.0,  0.0, 1.0, 0.0, 1.0, // 7 BL

        // Left (blue)
        -0.5,  0.5, -0.5,  0.0, 1.0,  0.0, 0.0, 1.0, 1.0, // 8 TL
        -0.5,  0.5,  0.5,  1.0, 1.0,  0.0, 0.0, 1.0, 1.0, // 9 TR
        -0.5, -0.5,  0.5,  1.0, 0.0,  0.0, 0.0, 1.0, 1.0, //10 BR
        -0.5, -0.5, -0.5,  0.0, 0.0,  0.0, 0.0, 1.0, 1.0, //11 BL

        // Right (yellow)
         0.5,  0.5,  0.5,  0.0, 1.0,  1.0, 1.0, 0.0, 1.0, //12 TL
         0.5,  0.5, -0.5,  1.0, 1.0,  1.0, 1.0, 0.0, 1.0, //13 TR
         0.5, -0.5, -0.5,  1.0, 0.0,  1.0, 1.0, 0.0, 1.0, //14 BR
         0.5, -0.5,  0.5,  0.0, 0.0,  1.0, 1.0, 0.0, 1.0, //15 BL

        // Top (magenta)
        -0.5,  0.5, -0.5,  0.0, 1.0,  1.0, 0.0, 1.0, 1.0, //16 TL
         0.5,  0.5, -0.5,  1.0, 1.0,  1.0, 0.0, 1.0, 1.0, //17 TR
         0.5,  0.5,  0.5,  1.0, 0.0,  1.0, 0.0, 1.0, 1.0, //18 BR
        -0.5,  0.5,  0.5,  0.0, 0.0,  1.0, 0.0, 1.0, 1.0, //19 BL

        // Bottom (cyan)
        -0.5, -0.5,  0.5,  0.0, 1.0,  0.0, 1.0, 1.0, 1.0, //20 TL
         0.5, -0.5,  0.5,  1.0, 1.0,  0.0, 1.0, 1.0, 1.0, //21 TR
         0.5, -0.5, -0.5,  1.0, 0.0,  0.0, 1.0, 1.0, 1.0, //22 BR
        -0.5, -0.5, -0.5,  0.0, 0.0,  0.0, 1.0, 1.0, 1.0, //23 BL
      ].toFloat32()
    );

    final indices = hostBuffer.emplace(
      <int>[
        // front
        0, 1, 2, 0, 2, 3,
        // back
        4, 5, 6, 4, 6, 7,
        // left
        8, 9,10, 8,10,11,
        // right
       12,13,14,12,14,15,
        // top
       16,17,18,16,18,19,
        // bottom
       20,21,22,20,22,23,
      ].toUint16()
    );

    // Bind the vertex data (9 floats per vertex)
    renderPass.bindVertexBuffer(vertices, 4);

    // Bind index data (36 indices)
    renderPass.bindIndexBuffer(indices, gpu.IndexType.int16, 36);

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

    // Create a simple model-view-projection matrix to rotate the cube.
    final model = vm.Matrix4.identity()
      ..rotateY(time * 0.0001)
      ..rotateX(time * 0.00007);

    // Simple camera: translate back along Z.
    final view = vm.Matrix4.identity();
    view.translateByVector3(vm.Vector3(0.0, 0.0, -2.0));

    // Perspective projection (fovy = pi/3)
    final aspect = size.width / size.height;
    final projection = vm.makePerspectiveMatrix(
      1.0471975512, aspect, 0.1, 100.0);

    // Compose MVP: projection * view * model
    final mvp = vm.Matrix4.identity() * projection * view * model;

    final frameInfoSlot = vertex.getUniformSlot('FrameInfo');
    final frameInfoFloats = <double>[
      mvp.storage[0],
      mvp.storage[1],
      mvp.storage[2],
      mvp.storage[3],
      mvp.storage[4],
      mvp.storage[5],
      mvp.storage[6],
      mvp.storage[7],
      mvp.storage[8],
      mvp.storage[9],
      mvp.storage[10],
      mvp.storage[11],
      mvp.storage[12],
      mvp.storage[13],
      mvp.storage[14],
      mvp.storage[15],
      time,
    ].toFloat32();

    final frameInfoView = hostBuffer.emplace(frameInfoFloats.buffer.asByteData());
    renderPass.bindUniform(frameInfoSlot, frameInfoView);

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

class TexturedCubePage extends StatefulWidget {
  const TexturedCubePage({super.key});
  @override
  State<TexturedCubePage> createState() => _TexturedCubePageState();
}

class _TexturedCubePageState extends State<TexturedCubePage> {

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
        painter: CubePainter(
          imageByteData: imageData!,
          time: elapsed.inMilliseconds.toDouble(),
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
