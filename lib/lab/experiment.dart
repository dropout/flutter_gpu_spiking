import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import 'fullscreen_view.dart';
import 'lab_errors.dart';
import 'params.dart';

/// What the shell hands an experiment's view.
class LabContext {
  const LabContext({
    required this.values,
    required this.time,
    required this.mouse,
    required this.errors,
  });

  final LabValues values;

  /// Seconds since the lab started (stops while paused).
  final ValueListenable<double> time;

  /// Pointer position over the viewport, in uv (0..1, origin top-left), plus
  /// whether a button is pressed.
  final ValueListenable<LabMouse> mouse;

  final LabErrors errors;
}

class LabMouse {
  const LabMouse(this.uv, {this.pressed = false});

  final Offset uv;
  final bool pressed;
}

/// One entry in the lab: a name, its control-panel parameters and a view.
abstract class LabExperiment {
  const LabExperiment();

  String get name;
  String get description;
  List<LabParam> get params;

  Widget buildView(BuildContext context, LabContext lab);
}

/// A simple Flutter GPU experiment: one fragment shader from the lab bundle
/// drawn on a fullscreen quad. See `shaders/lab/plasma.frag` for the uniform
/// contract the shader sees.
class FragmentExperiment extends LabExperiment {
  const FragmentExperiment({
    required this.name,
    required this.description,
    required this.fragmentShader,
    required this.params,
  });

  @override
  final String name;
  @override
  final String description;
  @override
  final List<LabParam> params;

  /// Name of the fragment shader in `shaders/lab.shaderbundle.json`.
  final String fragmentShader;

  @override
  Widget buildView(BuildContext context, LabContext lab) =>
      FullscreenShaderView(
        key: ValueKey(name),
        fragmentShader: fragmentShader,
        lab: lab,
      );
}
