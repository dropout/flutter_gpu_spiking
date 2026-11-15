import 'dart:async';

import 'package:flutter/foundation.dart';

/// Runtime errors reported by lab experiments (missing shader, pipeline
/// creation failure, missing uniform slot, ...), keyed by source.
///
/// Shader *compile* errors come from the build hook and show up in the
/// `flutter run` console, not here.
class LabErrors extends ValueNotifier<Map<String, String>> {
  LabErrors() : super(const {});

  /// Reports [message] for [key]. Safe to call while painting.
  void report(String key, String message) {
    if (value[key] == message) return;
    scheduleMicrotask(() {
      if (value[key] == message) return;
      debugPrint('[lab] $key: $message');
      value = {...value, key: message};
    });
  }

  /// Clears the error for [key], if any. Safe to call while painting.
  void clear(String key) {
    if (!value.containsKey(key)) return;
    scheduleMicrotask(() {
      if (!value.containsKey(key)) return;
      value = {...value}..remove(key);
    });
  }
}
