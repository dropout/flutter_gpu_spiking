import 'package:flutter/material.dart';
import 'package:flutter_gpu_spiking/lab/controls_panel.dart';
import 'package:flutter_gpu_spiking/lab/params.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('integer params reset and pack as floats', () {
    final values = LabValues([
      const IntParam('count', 'Count', min: 1, max: 8, initial: 3),
    ]);
    addTearDown(values.dispose);

    expect(values.getInt('count'), 3);
    expect(values.pack()[0], 3);

    values.set('count', 7);
    expect(values.pack()[0], 7);

    values.reset();
    expect(values.getInt('count'), 3);
  });

  testWidgets('integer controls write whole values', (tester) async {
    final values = LabValues([
      const IntParam('count', 'Count', min: 1, max: 8, initial: 3),
    ]);
    addTearDown(values.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ControlsPanel(values: values)),
      ),
    );

    final slider = find.byType(Slider);
    final track = tester.getRect(slider);
    await tester.tapAt(track.centerRight - const Offset(4, 0));
    await tester.pump();

    expect(values.getInt('count'), 8);
    expect(find.textContaining('Count'), findsOneWidget);
    expect(find.textContaining('  8'), findsOneWidget);
  });
}
