import 'package:hooks/hooks.dart';

import 'build_shader_bundle.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildShaderBundle(
      buildInput: input,
      buildOutput: output,
      manifestFileName: 'shaders/shader_library.shaderbundle.json',
    );
    // The shader lab has its own bundle, kept apart from the examples' one.
    // Note the hook is a single process: a compile error in either bundle
    // fails the whole hook run.
    await buildShaderBundle(
      buildInput: input,
      buildOutput: output,
      manifestFileName: 'shaders/lab.shaderbundle.json',
    );
  });
}
