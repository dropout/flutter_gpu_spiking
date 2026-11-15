import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

/// Textures dropped into `assets/lab/textures/` (picked up automatically).
class LabTextures {
  LabTextures._();

  static const String directory = 'assets/lab/textures/';

  static final Map<String, Future<gpu.Texture>> _cache = {};

  /// Asset paths under [directory], sorted.
  static Future<List<String>> list() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest
        .listAssets()
        .where((a) => a.startsWith(directory) && !a.endsWith('.gitkeep'))
        .toList()
      ..sort();
  }

  static String displayName(String assetPath) =>
      assetPath.substring(assetPath.lastIndexOf('/') + 1);

  /// Loads [assetPath] into an RGBA8 GPU texture (cached).
  static Future<gpu.Texture> load(String assetPath) =>
      _cache.putIfAbsent(assetPath, () => _decode(assetPath));

  static Future<gpu.Texture> _decode(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      image.width,
      image.height,
      format: gpu.PixelFormat.r8g8b8a8UNormInt,
      sampleCount: 1,
      enableShaderReadUsage: true,
    );
    texture.overwrite(pixels!);
    image.dispose();
    codec.dispose();
    return texture;
  }

  /// Forgets cached textures so changed image files are decoded again.
  static void clearCache() => _cache.clear();
}

