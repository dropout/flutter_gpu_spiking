import 'package:flutter/material.dart';
import 'package:flutter_gpu_spiking/app/color_swatch_row.dart';
import 'package:flutter_gpu_spiking/membrane.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reset restores the crest and trough colors', () {
    final params = MembraneParams();
    addTearDown(params.dispose);
    params.update(() {
      params.crestColor = Colors.red;
      params.troughColor = Colors.blue;
    });

    params.reset();

    expect(params.crestColor, MembraneParams.defaultCrestColor);
    expect(params.troughColor, MembraneParams.defaultTroughColor);
  });

  testWidgets('a swatch updates the selected color', (tester) async {
    Color selected = Colors.red;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorSwatchRow(
            label: 'Crest',
            value: selected,
            swatches: const [Colors.red, Colors.blue],
            onChanged: (color) => selected = color,
          ),
        ),
      ),
    );

    final swatches = find.descendant(
      of: find.byType(ColorSwatchRow),
      matching: find.byType(GestureDetector),
    );
    await tester.tap(swatches.at(1));

    expect(selected, Colors.blue);
  });
}
