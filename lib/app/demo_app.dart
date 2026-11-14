import 'package:flutter/material.dart';

import '../shader_library.dart';

/// Loads the shader library and runs a pager app over [pages].
Future<void> runDemoApp({
  required String title,
  required List<Widget> pages,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadShaderLibrary();
  runApp(DemoApp(title: title, pages: pages));
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key, required this.title, required this.pages});

  final String title;
  final List<Widget> pages;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: DemoPage(pages: pages),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key, required this.pages});

  final List<Widget> pages;

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: index, children: widget.pages),
          Positioned(
            bottom: 32,
            right: 32,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                iconSize: 32,
                onPressed: () => setState(() {
                  index = (index + 1) % widget.pages.length;
                }),
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
