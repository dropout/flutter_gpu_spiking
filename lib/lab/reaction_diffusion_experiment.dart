import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' show Vector4;

import 'experiment.dart';
import 'lab_shaders.dart';
import 'params.dart';

/// Gray-Scott reaction-diffusion: the first lab experiment with state that
/// persists between frames.
///
/// Two half-float textures hold the concentrations (A in red, B in green). Each
/// simulation step is one render pass that reads one texture and writes the
/// other (`shaders/lab/rd_step.frag`), then the roles swap: ping-pong, the
/// stand-in for the compute shaders Flutter GPU does not have. A separate pass
/// (`shaders/lab/rd_display.frag`) colors the latest state for the screen.
///
/// Both shaders read the same `Params` block, in the order declared below.
/// Press over the viewport to paint B into the field. Changing the seed or the
/// resolution restarts the simulation.
class ReactionDiffusionExperiment extends LabExperiment {
  const ReactionDiffusionExperiment();

  @override
  String get name => 'Reaction-diffusion';

  @override
  String get description =>
      'Gray-Scott system on ping-pong float textures. Press to paint, pick a '
      'preset or tune feed and kill (the sliders apply when the preset is '
      'Custom). Change the seed to restart.';

  static const List<String> resolutions = ['256', '384', '512', '768', '1024'];

  @override
  List<LabParam> get params => const [
    FloatParam(
      'feed',
      'Feed',
      min: 0.01,
      max: 0.09,
      initial: 0.0545,
      decimals: 4,
    ),
    FloatParam(
      'kill',
      'Kill',
      min: 0.04,
      max: 0.07,
      initial: 0.062,
      decimals: 4,
    ),
    FloatParam('diffA', 'Diffusion A', min: 0.5, max: 1.2, initial: 1),
    FloatParam('diffB', 'Diffusion B', min: 0.1, max: 0.8, initial: 0.5),
    FloatParam('dt', 'Time step', min: 0.2, max: 1.2, initial: 1),
    FloatParam(
      'steps',
      'Steps per frame',
      min: 1,
      max: 24,
      initial: 8,
      decimals: 0,
      divisions: 23,
    ),
    FloatParam('brush', 'Brush radius', min: 0.005, max: 0.1, initial: 0.025),
    ChoiceParam(
      'preset',
      'Preset',
      options: [
        'Custom',
        'Coral',
        'Mitosis',
        'Maze',
        'Worms',
        'Spots',
        'U-skate',
      ],
      initial: 1,
    ),
    BoolParam('relief', 'Relief lighting', initial: true),
    FloatParam(
      'seed',
      'Seed (restarts)',
      min: 0,
      max: 999,
      initial: 1,
      decimals: 0,
      divisions: 999,
    ),
    ChoiceParam(
      'resolution',
      'Resolution (restarts)',
      options: resolutions,
      initial: 2,
    ),
    ColorParam('bg', 'Background', initial: Color(0xFF0B1B2B)),
    ColorParam('mid', 'Mid', initial: Color(0xFF1F8A9E)),
    ColorParam('hi', 'High', initial: Color(0xFFF4E9C8)),
  ];

  @override
  Widget buildView(BuildContext context, LabContext lab) =>
      _ReactionDiffusionView(key: const ValueKey('rd'), lab: lab);
}

class _ReactionDiffusionView extends StatefulWidget {
  const _ReactionDiffusionView({super.key, required this.lab});

  final LabContext lab;

  @override
  State<_ReactionDiffusionView> createState() => _ReactionDiffusionViewState();
}

class _ReactionDiffusionViewState extends State<_ReactionDiffusionView> {
  final _Simulation _sim = _Simulation();

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return RepaintBoundary(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _RdPainter(
            sim: _sim,
            lab: widget.lab,
            devicePixelRatio: dpr,
          ),
        ),
      ),
    );
  }
}

/// The persistent part: the two state textures and what produced them.
class _Simulation {
  final List<gpu.Texture?> textures = [null, null];

  /// Index of the texture holding the latest state.
  int current = 0;

  int width = 0;
  int height = 0;
  double seed = -1;
  bool needsReset = true;

  /// Makes sure the state textures match [w] x [h] and the seed; flags a
  /// restart when anything changed.
  void ensure(int w, int h, double newSeed) {
    if (w != width || h != height || textures[0] == null) {
      width = w;
      height = h;
      for (var i = 0; i < 2; i++) {
        textures[i] = gpu.gpuContext.createTexture(
          gpu.StorageMode.devicePrivate,
          w,
          h,
          format: gpu.PixelFormat.r16g16b16a16Float,
          enableRenderTargetUsage: true,
          enableShaderReadUsage: true,
        );
      }
      needsReset = true;
    }
    if (newSeed != seed) {
      seed = newSeed;
      needsReset = true;
    }
  }
}

class _RdPainter extends CustomPainter {
  _RdPainter({
    required this.sim,
    required this.lab,
    required this.devicePixelRatio,
  }) : super(repaint: Listenable.merge([lab.time, lab.mouse, lab.values]));

  final _Simulation sim;
  final LabContext lab;
  final double devicePixelRatio;

  static const String _errorKey = 'draw:reaction-diffusion';

  /// While the lab is paused its clock stops; the simulation then holds too.
  double _lastTime = -1;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    try {
      _paint(canvas, size);
      lab.errors.clear(_errorKey);
    } catch (e) {
      lab.errors.report(_errorKey, '$e');
    }
  }

  void _paint(Canvas canvas, Size size) {
    final values = lab.values;

    // Simulation size: the chosen long side, square pixels.
    final longSide = int.parse(
      ReactionDiffusionExperiment.resolutions[values.getChoice('resolution')],
    );
    final aspect = size.width / size.height;
    final simW = (aspect >= 1 ? longSide : longSide * aspect).round().clamp(
      16,
      4096,
    );
    final simH = (aspect >= 1 ? longSide / aspect : longSide).round().clamp(
      16,
      4096,
    );
    sim.ensure(simW, simH, values.getFloat('seed'));

    final time = lab.time.value;
    final running = time != _lastTime || sim.needsReset;
    _lastTime = time;

    final vertex = LabShaders.shader('LabFullscreenVertex');
    final stepShader = LabShaders.shader('LabRdStepFragment');
    final displayShader = LabShaders.shader('LabRdDisplayFragment');
    final hostBuffer = gpu.gpuContext.createHostBuffer();

    final params = hostBuffer.emplace(values.pack().buffer.asByteData());
    final quad = _FullscreenQuad(hostBuffer);
    final mouse = lab.mouse.value;

    final stepPipeline = gpu.gpuContext.createRenderPipeline(
      vertex,
      stepShader,
    );
    final repeat = gpu.SamplerOptions(
      minFilter: gpu.MinMagFilter.linear,
      magFilter: gpu.MinMagFilter.linear,
      widthAddressMode: gpu.SamplerAddressMode.repeat,
      heightAddressMode: gpu.SamplerAddressMode.repeat,
    );

    // Simulation passes: read `current`, write the other, swap.
    final steps = sim.needsReset
        ? 1
        : (running ? values.getFloat('steps').round() : 0);
    for (var i = 0; i < steps; i++) {
      final reset = sim.needsReset;
      final src = sim.textures[sim.current]!;
      final dst = sim.textures[1 - sim.current]!;

      // One command buffer per pass: Metal allows a single open render encoder
      // per command buffer, and Flutter GPU only closes it on submit.
      final stepBuffer = gpu.gpuContext.createCommandBuffer();
      final pass = stepBuffer.createRenderPass(
        gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(
            texture: dst,
            loadAction: gpu.LoadAction.clear,
            storeAction: gpu.StoreAction.store,
            clearValue: Vector4(1, 0, 0, 1),
          ),
        ),
      );
      pass.bindPipeline(stepPipeline);
      pass.bindUniform(
        stepShader.getUniformSlot('Globals'),
        hostBuffer.emplace(
          Float32List.fromList([
            time, simW.toDouble(), simH.toDouble(), reset ? 1 : 0, //
            mouse.uv.dx, mouse.uv.dy, mouse.pressed ? 1 : 0, sim.seed,
          ]).buffer.asByteData(),
        ),
      );
      pass.bindUniform(stepShader.getUniformSlot('Params'), params);
      pass.bindTexture(
        stepShader.getUniformSlot('u_state'),
        src,
        sampler: repeat,
      );
      quad.draw(pass);
      stepBuffer.submit();

      sim.current = 1 - sim.current;
      sim.needsReset = false;
    }

    // Display pass: color the latest state into an RGBA8 target at viewport
    // resolution.
    final scale = devicePixelRatio;
    final outW = (size.width * scale).round().clamp(1, 8192);
    final outH = (size.height * scale).round().clamp(1, 8192);
    final target = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      outW,
      outH,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );
    final displayBuffer = gpu.gpuContext.createCommandBuffer();
    final displayPass = displayBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: target,
          loadAction: gpu.LoadAction.clear,
          storeAction: gpu.StoreAction.store,
          clearValue: Vector4(0, 0, 0, 1),
        ),
      ),
    );
    displayPass.bindPipeline(
      gpu.gpuContext.createRenderPipeline(vertex, displayShader),
    );
    displayPass.bindUniform(
      displayShader.getUniformSlot('Globals'),
      hostBuffer.emplace(
        Float32List.fromList([
          time, simW.toDouble(), simH.toDouble(), 0, //
          mouse.uv.dx, mouse.uv.dy, mouse.pressed ? 1 : 0, sim.seed,
        ]).buffer.asByteData(),
      ),
    );
    displayPass.bindUniform(displayShader.getUniformSlot('Params'), params);
    displayPass.bindTexture(
      displayShader.getUniformSlot('u_state'),
      sim.textures[sim.current]!,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
      ),
    );
    quad.draw(displayPass);
    displayBuffer.submit();

    canvas.save();
    canvas.scale(size.width / outW, size.height / outH);
    canvas.drawImage(
      target.asImage(),
      Offset.zero,
      Paint()..filterQuality = FilterQuality.low,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RdPainter oldDelegate) => true;
}

/// The fullscreen quad every lab pass draws, uploaded once per frame.
class _FullscreenQuad {
  _FullscreenQuad(gpu.HostBuffer hostBuffer)
    : _vertices = hostBuffer.emplace(
        Float32List.fromList(<double>[
          1.0, 1.0, //
          -1.0, 1.0,
          -1.0, -1.0,
          1.0, -1.0,
        ]).buffer.asByteData(),
      ),
      _indices = hostBuffer.emplace(
        Uint16List.fromList(<int>[0, 1, 2, 0, 2, 3]).buffer.asByteData(),
      );

  final gpu.BufferView _vertices;
  final gpu.BufferView _indices;

  void draw(gpu.RenderPass pass) {
    pass.bindVertexBuffer(_vertices);
    pass.bindIndexBuffer(_indices, gpu.IndexType.int16);
    pass.drawIndexed(6);
  }
}
