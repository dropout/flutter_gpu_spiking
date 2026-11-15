import 'package:flutter_gpu_spiking/lab/experiments.dart';
import 'package:flutter_gpu_spiking/lab/params.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sweep length is packed into the transition shader slot', () {
    final experiment = labExperiments.singleWhere(
      (e) => e.name == 'Transition',
    );
    final values = LabValues(experiment.params);
    addTearDown(values.dispose);

    values.set('progress', 0.75);
    values.set('sweepLength', 0.25);
    expect(values.pack()[0], 0.75);
    expect(values.pack()[3], 0.25);

    values.set('sweepLength', 0.0);
    expect(values.pack()[3], 0.0);
  });
}
