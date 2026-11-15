import 'package:flutter_gpu/gpu.dart' as gpu;

const String kLabBundleAsset = 'build/shaderbundles/lab.shaderbundle';

/// The lab's shader bundle (`shaders/lab.shaderbundle.json`).
class LabShaders {
  LabShaders._();

  static gpu.ShaderLibrary? _library;

  static Future<void> load() async {
    _library ??= await gpu.ShaderLibrary.fromAsset(kLabBundleAsset);
    if (_library == null) {
      throw Exception('Failed to load shader bundle! ($kLabBundleAsset)');
    }
  }

  /// Re-fetches the bundle asset and reparses it in place. Hot reload does the
  /// same automatically; this is for the Refresh button.
  static void reload() => gpu.ShaderLibrary.reinitialize(kLabBundleAsset);

  static gpu.Shader shader(String name) {
    final library = _library;
    if (library == null) {
      throw StateError('Call LabShaders.load() first.');
    }
    final shader = library[name];
    if (shader == null) {
      throw StateError(
        'Shader "$name" is not in $kLabBundleAsset. '
        'Add it to shaders/lab.shaderbundle.json.',
      );
    }
    return shader;
  }
}
