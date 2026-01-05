import 'package:flutter/material.dart';

import 'blank.dart';
import 'cube.dart';
import 'triangle.dart';

void main() {
  runApp(const FlutterGpuSpikingApp());
}

class FlutterGpuSpikingApp extends StatelessWidget {
  const FlutterGpuSpikingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter GPU Test',
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
  int widgetIndex = 0;

  @override
  Widget build(BuildContext context) {
    final widgets = [
      const BlankPage(),
      const TrianglePage(),
    ];
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
