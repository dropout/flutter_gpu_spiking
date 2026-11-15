import 'package:flutter/material.dart';

import 'color_swatch_row.dart';

/// An item in an idea's control panel.
sealed class Control {}

/// A tweakable value: its label, range and initial value live in one place,
/// so the panel and Reset need nothing more.
sealed class Knob<T> extends ValueNotifier<T> implements Control {
  Knob(this.label, this.initial) : super(initial);

  final String label;
  final T initial;

  void reset() => value = initial;
}

/// A continuous slider.
class FloatKnob extends Knob<double> {
  FloatKnob(
    super.label,
    super.initial, {
    required this.min,
    required this.max,
    this.digits = 3,
  });

  final double min;
  final double max;

  /// Digits shown after the decimal point.
  final int digits;

  @override
  set value(double v) => super.value = v.clamp(min, max);
}

/// A whole-number slider that snaps to multiples of [step] above [min].
class IntKnob extends Knob<int> {
  IntKnob(
    super.label,
    super.initial, {
    required this.min,
    required this.max,
    this.step = 1,
  });

  final int min;
  final int max;
  final int step;

  @override
  set value(int v) => super.value = v.clamp(min, max);
}

class BoolKnob extends Knob<bool> {
  BoolKnob(super.label, super.initial);
}

/// A color picked from swatches. The initial color is always one of them.
class ColorKnob extends Knob<Color> {
  ColorKnob(
    super.label,
    super.initial, {
    List<Color> swatches = ColorSwatchRow.defaultSwatches,
  }) : swatches = {initial, ...swatches}.toList();

  final List<Color> swatches;
}

/// One of a fixed set of [options], shown as chips.
class ChoiceKnob<T> extends Knob<T> {
  ChoiceKnob(
    super.label,
    super.initial, {
    required this.options,
    String Function(T)? name,
  }) : _name = name ?? ((T t) => '$t');

  final List<T> options;

  // Private behind [nameOf]: reading a `Function(T)` field through a
  // `ChoiceKnob<dynamic>` fails Dart's covariance check, calling a method
  // does not.
  final String Function(T) _name;

  String nameOf(T option) => _name(option);
}

/// A heading that starts a group of controls.
class Section implements Control {
  Section(this.title);

  final String title;
}

/// Read-only text, rebuilt whenever a knob changes.
class Note implements Control {
  Note(this.text);

  final String Function() text;
}

/// A row of buttons, label to action.
class Buttons implements Control {
  Buttons(this.actions);

  final Map<String, VoidCallback> actions;
}

/// Restores every knob in [controls] to its initial value.
void resetKnobs(Iterable<Control> controls) {
  for (final c in controls) {
    if (c is Knob) c.reset();
  }
}

/// Renders [controls] top to bottom, rebuilding when any knob changes.
class ControlList extends StatelessWidget {
  const ControlList({super.key, required this.controls});

  final List<Control> controls;

  static const _text = TextStyle(color: Colors.white, fontSize: 12);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(controls.whereType<Knob>()),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [for (final c in controls) _build(c)],
      ),
    );
  }

  Widget _build(Control control) {
    switch (control) {
      case Section(:final title):
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
        );
      case Note(:final text):
        return Text(
          text(),
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        );
      case Buttons(:final actions):
        return Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            alignment: WrapAlignment.end,
            children: [
              for (final MapEntry(:key, :value) in actions.entries)
                TextButton(onPressed: value, child: Text(key)),
            ],
          ),
        );
      case FloatKnob():
        return _slider(
          '${control.label}: ${control.value.toStringAsFixed(control.digits)}',
          Slider(
            value: control.value,
            min: control.min,
            max: control.max,
            onChanged: (v) => control.value = v,
          ),
        );
      case IntKnob():
        return _slider(
          '${control.label}: ${control.value}',
          Slider(
            value: control.value.toDouble(),
            min: control.min.toDouble(),
            max: control.max.toDouble(),
            divisions: (control.max - control.min) ~/ control.step,
            onChanged: (v) => control.value = v.round(),
          ),
        );
      case BoolKnob():
        return Row(
          children: [
            Expanded(child: Text(control.label, style: _text)),
            Switch(value: control.value, onChanged: (v) => control.value = v),
          ],
        );
      case ColorKnob():
        return ColorSwatchRow(
          label: control.label,
          value: control.value,
          swatches: control.swatches,
          onChanged: (c) => control.value = c,
        );
      case ChoiceKnob():
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in control.options)
                ChoiceChip(
                  label: Text(control.nameOf(option)),
                  selected: control.value == option,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => control.value = option,
                ),
            ],
          ),
        );
    }
  }

  Widget _slider(String caption, Slider slider) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(caption, style: _text),
      ),
      slider,
    ],
  );
}
