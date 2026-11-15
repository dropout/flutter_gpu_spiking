import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'controls.dart';

/// A camera placement around the origin.
class CameraPose {
  const CameraPose({
    this.name = '',
    required this.azimuth,
    required this.elevation,
    required this.distance,
    this.fov = 45,
  });

  final String name;
  final double azimuth; // degrees around the Y axis
  final double elevation; // degrees above the XZ plane
  final double distance;
  final double fov; // vertical, degrees
}

/// A camera that orbits the origin. Drag orbits, pinch or scroll zooms.
class OrbitCamera {
  OrbitCamera(
    CameraPose pose, {
    double orbitSpeed = 0,
    this.presets = const [],
  }) {
    apply(pose);
    this.orbitSpeed.value = orbitSpeed;
  }

  final List<CameraPose> presets;

  final azimuth = FloatKnob('Azimuth', 0, min: 0, max: 360, digits: 0);
  // Stop short of straight up or down, where the up vector degenerates.
  final elevation = FloatKnob('Elevation', 30, min: 2, max: 89, digits: 0);
  final distance = FloatKnob('Distance', 10, min: 1.5, max: 30, digits: 1);
  final fov = FloatKnob('Field of view', 45, min: 10, max: 120, digits: 0);
  final orbitSpeed = FloatKnob(
    'Auto orbit (deg/s)',
    0,
    min: 0,
    max: 30,
    digits: 0,
  );

  late final List<Control> controls = [
    Section('Camera'),
    if (presets.isNotEmpty)
      Buttons({for (final p in presets) p.name: () => apply(p)}),
    orbitSpeed,
    azimuth,
    elevation,
    distance,
    fov,
  ];

  void apply(CameraPose p) {
    azimuth.value = p.azimuth;
    elevation.value = p.elevation;
    distance.value = p.distance;
    fov.value = p.fov;
  }

  /// Drag [delta] in logical pixels: right turns the scene, down tilts up.
  void orbitBy(Offset delta) {
    azimuth.value = (azimuth.value - delta.dx * 0.4) % 360;
    elevation.value += delta.dy * 0.4;
  }

  void zoomBy(double factor) => distance.value *= factor;

  /// Advances the auto orbit by [dt] seconds.
  void tick(double dt) {
    if (orbitSpeed.value > 0) {
      azimuth.value = (azimuth.value + dt * orbitSpeed.value) % 360;
    }
  }

  PerspectiveCamera build() {
    final az = azimuth.value * math.pi / 180;
    final el = elevation.value * math.pi / 180;
    final d = distance.value;
    return PerspectiveCamera(
      fovRadiansY: fov.value * math.pi / 180,
      position: vm.Vector3(
        d * math.cos(el) * math.sin(az),
        d * math.sin(el),
        d * math.cos(el) * math.cos(az),
      ),
      target: vm.Vector3.zero(),
    );
  }

  void dispose() {
    for (final c in controls) {
      if (c is Knob) c.dispose();
    }
  }
}
