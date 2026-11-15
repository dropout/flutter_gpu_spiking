import 'package:flutter/material.dart';
import 'package:flutter_gpu_spiking/app/color_swatch_row.dart';
import 'package:flutter_gpu_spiking/app/controls.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reset restores every knob and notifies once per changed knob', () {
    final speed = FloatKnob('Speed', 0.5, min: 0, max: 5);
    final color = ColorKnob('Crest', Colors.cyan);
    final choice = ChoiceKnob('Shape', 'a', options: const ['a', 'b']);
    final controls = <Control>[Section('Test'), speed, color, choice];
    addTearDown(() {
      for (final k in [speed, color, choice]) {
        k.dispose();
      }
    });

    speed.value = 2;
    color.value = Colors.red;
    choice.value = 'b';
    var notifications = 0;
    for (final k in [speed, color, choice]) {
      k.addListener(() => notifications++);
    }

    resetKnobs(controls);

    expect(speed.value, 0.5);
    expect(color.value, Colors.cyan);
    expect(choice.value, 'a');
    expect(notifications, 3);
  });

  test('numeric knobs clamp to their range', () {
    final f = FloatKnob('F', 1, min: 0, max: 2);
    final i = IntKnob('I', 5, min: 1, max: 9);
    addTearDown(f.dispose);
    addTearDown(i.dispose);

    f.value = 7;
    i.value = -3;

    expect(f.value, 2);
    expect(i.value, 1);
  });

  test('a color knob always offers its initial color', () {
    final knob = ColorKnob('C', Colors.cyan, swatches: const [Colors.red]);
    addTearDown(knob.dispose);

    expect(knob.swatches, [Colors.cyan, Colors.red]);
  });

  testWidgets('the panel shows a knob and writes slider changes back', (
    tester,
  ) async {
    final knob = IntKnob('Grains', 2, min: 0, max: 4);
    addTearDown(knob.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ControlList(controls: [knob])),
      ),
    );

    expect(find.text('Grains: 2'), findsOneWidget);
    final track = tester.getRect(find.byType(Slider));
    await tester.tapAt(track.centerRight - const Offset(4, 0));
    await tester.pump();

    expect(knob.value, 4);
    expect(find.text('Grains: 4'), findsOneWidget);
  });

  testWidgets('the panel shows a typed choice knob and selects options', (
    tester,
  ) async {
    final knob = ChoiceKnob(
      'Align',
      TextAlign.left,
      options: const [TextAlign.left, TextAlign.right],
      name: (a) => a.name.toUpperCase(),
    );
    addTearDown(knob.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ControlList(controls: [knob])),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('RIGHT'));
    await tester.pump();

    expect(knob.value, TextAlign.right);
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
