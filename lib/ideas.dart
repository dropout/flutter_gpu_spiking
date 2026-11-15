import 'package:flutter/widgets.dart';

import 'app/demo_app.dart';
import 'chladni.dart';
import 'disco_floor.dart';
import 'epicycles.dart';
import 'harmonograph.dart';
import 'membrane.dart';
import 'pendulum_wave.dart';

/// Bigger experiments and ideas, built on flutter_scene.
///
/// Run with: flutter run -t lib/ideas.dart
void main() => runDemoApp(
  title: 'Ideas',
  pages: const <Widget>[DiscoFloorPage(), ChladniPage(), HarmonographPage(), MembranePage(), EpicyclesPage(), PendulumWavePage()],
);
