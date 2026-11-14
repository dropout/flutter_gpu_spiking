import 'package:flutter/widgets.dart';

import 'app/demo_app.dart';
import 'blank.dart';
import 'cube.dart';
import 'quad.dart';
import 'textured_cube.dart';
import 'textured_quad.dart';
import 'triangle.dart';

/// Basic Flutter GPU examples that don't use flutter_scene.
///
/// Run with: flutter run -t lib/basic_examples.dart
void main() => runDemoApp(
  title: 'Basic Examples',
  pages: const <Widget>[
    BlankPage(),
    TrianglePage(),
    QuadPage(),
    TexturedQuadPage(),
    CubePage(),
    TexturedCubePage(),
  ],
);
