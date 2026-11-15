import 'package:flutter_gpu_spiking/disco_floor.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('switching presets removes the previous material features', () {
    final material = PhysicallyBasedMaterial();

    DiscoMaterial.glass.applyTo(material);
    expect(material.transmission, greaterThan(0));

    DiscoMaterial.iridescent.applyTo(material);
    expect(material.transmission, 0);
    expect(material.iridescence, greaterThan(0));

    DiscoMaterial.clearcoat.applyTo(material);
    expect(material.iridescence, 0);
    expect(material.clearcoat, greaterThan(0));

    DiscoMaterial.current.applyTo(material);
    expect(material.clearcoat, 0);
    expect(material.metallicFactor, 0.1);
    expect(material.roughnessFactor, 0.35);
  });
}
