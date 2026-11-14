import 'package:flutter/widgets.dart';

import 'app/demo_app.dart';
import 'disco_floor.dart';

/// Bigger experiments and ideas, built on flutter_scene.
///
/// Run with: flutter run -t lib/ideas.dart
void main() => runDemoApp(
  title: 'Ideas',
  pages: const <Widget>[DiscoFloorPage()],
);
