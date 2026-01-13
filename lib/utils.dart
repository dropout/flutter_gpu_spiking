import 'dart:typed_data';

import 'package:flutter/material.dart' as mtl;
import 'package:vector_math/vector_math.dart';

extension MaterialColorExtension on mtl.MaterialColor {
  Vector4 toVector4() => Vector4(r, g, b, a);
}

extension ColorExt on mtl.Color {
  Vector4 toVector4() => Vector4(r, g, b, a);
}

extension ListExtDouble on List<double> {
  ByteData toFloat32() => Float32List.fromList(this).buffer.asByteData();
}

extension ListExtInt on List<int> {
  ByteData toUint16() => Uint16List.fromList(this).buffer.asByteData();
  ByteData toUint32() => Uint32List.fromList(this).buffer.asByteData();
}

extension MatrixExt on Matrix4 {
  ByteData toFloat32() => Float32List.fromList(storage).buffer.asByteData();
}
