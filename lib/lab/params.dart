import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Number of vec4 slots (`p0`..`p5`) in the shared `Params` uniform block.
const int kParamVec4Count = 6;
const int kParamFloatCount = kParamVec4Count * 4;

/// A control-panel parameter declared by an experiment.
sealed class LabParam {
  const LabParam(this.id, this.label);

  final String id;
  final String label;
}

/// A float slider. Packed as one float.
class FloatParam extends LabParam {
  const FloatParam(
    super.id,
    super.label, {
    required this.min,
    required this.max,
    required this.initial,
  });

  final double min;
  final double max;
  final double initial;
}

/// A color. Packed as a whole vec4 (r, g, b, a).
class ColorParam extends LabParam {
  const ColorParam(super.id, super.label, {required this.initial});

  final Color initial;
}

/// A toggle. Packed as one float (0 or 1).
class BoolParam extends LabParam {
  const BoolParam(super.id, super.label, {this.initial = false});

  final bool initial;
}

/// A choice from a list. Packed as one float holding the selected index.
class ChoiceParam extends LabParam {
  const ChoiceParam(
    super.id,
    super.label, {
    required this.options,
    this.initial = 0,
  });

  final List<String> options;
  final int initial;
}

/// A texture from `assets/lab/textures/`. Not packed into `Params`: textures
/// bind in declaration order as `u_texture0`, `u_texture1`, ...
class TextureParam extends LabParam {
  const TextureParam(super.id, super.label, {this.initial});

  /// Asset path, or null to pick the first available texture.
  final String? initial;
}

/// Where a parameter lands inside the `Params` block.
class ParamSlot {
  const ParamSlot(this.param, this.floatIndex);

  final LabParam param;
  final int floatIndex;

  /// GLSL access path, e.g. `p0.x` or `p1` for a color.
  String get glsl {
    final vec = 'p${floatIndex ~/ 4}';
    if (param is ColorParam) return vec;
    return '$vec.${'xyzw'[floatIndex % 4]}';
  }
}

/// Assigns packed slots to [params] in order. Colors align to a vec4.
List<ParamSlot> layoutParams(List<LabParam> params) {
  final slots = <ParamSlot>[];
  var next = 0;
  for (final param in params) {
    switch (param) {
      case TextureParam():
        break;
      case ColorParam():
        next = (next + 3) & ~3;
        slots.add(ParamSlot(param, next));
        next += 4;
      case FloatParam() || BoolParam() || ChoiceParam():
        slots.add(ParamSlot(param, next));
        next += 1;
    }
  }
  assert(
    next <= kParamFloatCount,
    'Experiment uses $next floats; Params holds $kParamFloatCount.',
  );
  return slots;
}

/// Current values of one experiment's parameters.
class LabValues extends ChangeNotifier {
  LabValues(this.params) {
    _resetValues();
  }

  final List<LabParam> params;
  late final List<ParamSlot> slots = layoutParams(params);
  final Map<String, Object?> _values = {};

  void _resetValues() {
    for (final p in params) {
      _values[p.id] = switch (p) {
        FloatParam() => p.initial,
        ColorParam() => p.initial,
        BoolParam() => p.initial,
        ChoiceParam() => p.initial,
        TextureParam() => p.initial,
      };
    }
  }

  void reset() {
    _resetValues();
    notifyListeners();
  }

  void set(String id, Object? value) {
    _values[id] = value;
    notifyListeners();
  }

  double getFloat(String id) => _values[id]! as double;
  Color getColor(String id) => _values[id]! as Color;
  bool getBool(String id) => _values[id]! as bool;
  int getChoice(String id) => _values[id]! as int;
  String? getTexture(String id) => _values[id] as String?;

  /// Asset paths of the texture params, in declaration order.
  List<String?> get textureSelection => [
    for (final p in params)
      if (p is TextureParam) getTexture(p.id),
  ];

  /// Packs all non-texture params into the `Params` block layout.
  Float32List pack() {
    final out = Float32List(kParamFloatCount);
    for (final slot in slots) {
      final i = slot.floatIndex;
      switch (slot.param) {
        case FloatParam(:final id):
          out[i] = getFloat(id);
        case BoolParam(:final id):
          out[i] = getBool(id) ? 1 : 0;
        case ChoiceParam(:final id):
          out[i] = getChoice(id).toDouble();
        case ColorParam(:final id):
          final c = getColor(id);
          out[i] = c.r;
          out[i + 1] = c.g;
          out[i + 2] = c.b;
          out[i + 3] = c.a;
        case TextureParam():
          break;
      }
    }
    return out;
  }
}
