import 'package:flutter_gpu/gpu.dart' as gpu;

const String _kShaderBundlePath =
  'build/shaderbundles/shader_library.shaderbundle';
// NOTE: If you're building a library, the path must be prefixed
//       with a package name. For example:
//      'packages/my_cool_renderer/build/shaderbundles/my_renderer.shaderbundle'

gpu.ShaderLibrary? _shaderLibrary;

/// Loads the shader bundle. Loading became asynchronous in Flutter 3.47, so
/// this has to complete (see `main`) before a painter reads [shaderLibrary].
Future<void> loadShaderLibrary() async {
  _shaderLibrary ??= await gpu.ShaderLibrary.fromAsset(_kShaderBundlePath);
  if (_shaderLibrary == null) {
    throw Exception("Failed to load shader bundle! ($_kShaderBundlePath)");
  }
}

gpu.ShaderLibrary get shaderLibrary {
  final library = _shaderLibrary;
  if (library == null) {
    throw StateError('Call loadShaderLibrary() before using shaderLibrary.');
  }
  return library;
}
