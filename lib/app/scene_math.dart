import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

/// Writes the linear RGBA equivalent of an HSV color to [out].
void hsv(double hue, double saturation, double value, vm.Vector4 out) {
  final h = (hue - hue.floorToDouble()) * 6.0;
  double channel(double offset) {
    final k = (offset + h) % 6.0;
    final c =
        1.0 - saturation * math.max(0.0, math.min(1.0, math.min(k, 4.0 - k)));
    // Approximate sRGB to linear, so the hues look as they would in Flutter.
    return math.pow(c, 2.2) * value;
  }

  out.setValues(channel(5), channel(3), channel(1), 1.0);
}

/// Where [ray] crosses the plane through the origin with [normal], or null
/// if it runs parallel to the plane or points away from it.
vm.Vector3? hitPlane(vm.Ray ray, vm.Vector3 normal) {
  final along = ray.direction.dot(normal);
  if (along.abs() < 1e-6) return null;
  final t = -ray.origin.dot(normal) / along;
  return t < 0 ? null : ray.at(t);
}

extension InstanceTransform on vm.Matrix4 {
  /// Scales by ([sx], [sy], [sz]), then moves to ([x], [y], [z]).
  void setScaleTranslation(
    double sx,
    double sy,
    double sz,
    double x,
    double y,
    double z,
  ) => setValues(sx, 0, 0, 0, 0, sy, 0, 0, 0, 0, sz, 0, x, y, z, 1);
}
