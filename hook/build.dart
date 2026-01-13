import 'package:hooks/hooks.dart';

import 'build_shader_bundle.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildShaderBundle(
      buildInput: input,
      buildOutput: output,
      manifestFileName: 'shaders/shader_library.shaderbundle.json',
    );
  });
}
