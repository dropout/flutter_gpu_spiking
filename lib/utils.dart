import 'dart:typed_data';
import 'dart:ui';

import 'package:vector_math/vector_math.dart';

ByteData float32(List<double> values) =>
  Float32List.fromList(values).buffer.asByteData();

ByteData uint16(List<int> values) =>
  Uint16List.fromList(values).buffer.asByteData();

ByteData uint32(List<int> values) =>
  Uint32List.fromList(values).buffer.asByteData();

ByteData float32Mat(Matrix4 matrix) =>
  Float32List.fromList(matrix.storage).buffer.asByteData();

Vector4 colorToVector4(Color color) =>
  Vector4(color.r, color.g, color.b, color.a);
