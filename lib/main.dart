import 'package:flutter/material.dart';
import 'package:flutter_gpu_spiking/cube.dart';
import 'package:flutter_gpu_spiking/textured_cube.dart';

import 'blank.dart';
import 'disco_floor.dart';
import 'triangle.dart';
import 'quad.dart';
import 'shader_library.dart';
import 'textured_quad.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadShaderLibrary();
  runApp(const FlutterGpuSpikingApp());
}

class FlutterGpuSpikingApp extends StatelessWidget {
  const FlutterGpuSpikingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {

  final List<Widget> widgets = [
    const BlankPage(),
    const TrianglePage(),
    const QuadPage(),
    const TexturedQuadPage(),
    const CubePage(),
    const TexturedCubePage(),
    const DiscoFloorPage(),
  ];

  int widgetIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: widgetIndex,
            children: widgets,
          ),
          Positioned(
            bottom: 32,
            right: 32,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                iconSize: 32,
                onPressed: () => setState(() {
                  widgetIndex = (widgetIndex + 1) % widgets.length;
                }),
                icon: const Icon(Icons.arrow_forward),
              ),
            )
          )
        ],
      ),
    );
  }
}
