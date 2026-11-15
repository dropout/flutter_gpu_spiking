import 'package:flutter/material.dart';

import 'lab/experiments.dart';
import 'lab/lab_app.dart';
import 'lab/lab_shaders.dart';

/// Shader research lab: fragment-shader and flutter_scene experiments with a
/// generic controls panel.
///
/// Run with: flutter run -t lib/lab.dart --enable-flutter-gpu
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await LabShaders.load();
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(body: Center(child: SelectableText('$e'))),
      ),
    );
    return;
  }
  runApp(const LabApp(experiments: labExperiments));
}
