import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'controls_panel.dart';
import 'experiment.dart';
import 'lab_errors.dart';
import 'lab_shaders.dart';
import 'lab_textures.dart';
import 'params.dart';

class LabApp extends StatelessWidget {
  const LabApp({
    super.key,
    required this.experiments,
    this.initialExperiment = '',
  });

  final List<LabExperiment> experiments;

  /// Name of the experiment to open first, or empty for the first one.
  final String initialExperiment;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shader Lab',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: LabShell(
        experiments: experiments,
        initialExperiment: initialExperiment,
      ),
    );
  }
}

class LabShell extends StatefulWidget {
  const LabShell({
    super.key,
    required this.experiments,
    this.initialExperiment = '',
  });

  final List<LabExperiment> experiments;
  final String initialExperiment;

  @override
  State<LabShell> createState() => _LabShellState();
}

class _LabShellState extends State<LabShell>
    with SingleTickerProviderStateMixin {
  final LabErrors _errors = LabErrors();
  final ValueNotifier<double> _time = ValueNotifier(0);
  final ValueNotifier<LabMouse> _mouse = ValueNotifier(
    const LabMouse(Offset(0.5, 0.5)),
  );
  final Map<int, LabValues> _values = {};

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  bool _paused = false;
  int _selected = 0;

  LabExperiment get _experiment => widget.experiments[_selected];
  LabValues get _currentValues =>
      _values.putIfAbsent(_selected, () => LabValues(_experiment.params));

  @override
  void initState() {
    super.initState();
    final start = widget.experiments.indexWhere(
      (e) => e.name == widget.initialExperiment,
    );
    if (start >= 0) _selected = start;
    _ticker = createTicker((elapsed) {
      if (!_paused) _time.value += (elapsed - _lastTick).inMicroseconds / 1e6;
      _lastTick = elapsed;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    for (final v in _values.values) {
      v.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    try {
      LabShaders.reload();
      LabTextures.clearCache();
      _errors.value = const {};
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shader bundle reloaded'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      _errors.report('refresh', '$e');
    }
  }

  void _onPointer(PointerEvent event, Size size) {
    if (size.isEmpty) return;
    _mouse.value = LabMouse(
      Offset(
        (event.localPosition.dx / size.width).clamp(0.0, 1.0),
        (event.localPosition.dy / size.height).clamp(0.0, 1.0),
      ),
      pressed: event.down,
    );
  }

  @override
  Widget build(BuildContext context) {
    final experiment = _experiment;
    final values = _currentValues;
    final lab = LabContext(
      values: values,
      time: _time,
      mouse: _mouse,
      errors: _errors,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Shader Lab · ${experiment.name}'),
        actions: [
          IconButton(
            tooltip: _paused ? 'Resume time' : 'Pause time',
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
            onPressed: () => setState(() => _paused = !_paused),
          ),
          IconButton(
            tooltip: 'Reset parameters',
            icon: const Icon(Icons.restart_alt),
            onPressed: values.reset,
          ),
          IconButton(
            tooltip: 'Reload shader bundle',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          ValueListenableBuilder<Map<String, String>>(
            valueListenable: _errors,
            builder: (context, errors, _) => errors.isEmpty
                ? const SizedBox.shrink()
                : Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 140),
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          errors.values.join('\n\n'),
                          style: const TextStyle(
                            fontFamily: 'Menlo',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 200,
                  child: ListView(
                    children: [
                      for (final (i, e) in widget.experiments.indexed)
                        ListTile(
                          dense: true,
                          selected: i == _selected,
                          title: Text(e.name),
                          onTap: () => setState(() => _selected = i),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) => Listener(
                            onPointerHover: (e) =>
                                _onPointer(e, constraints.biggest),
                            onPointerMove: (e) =>
                                _onPointer(e, constraints.biggest),
                            onPointerDown: (e) =>
                                _onPointer(e, constraints.biggest),
                            onPointerUp: (e) =>
                                _onPointer(e, constraints.biggest),
                            child: ClipRect(
                              child: experiment.buildView(context, lab),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          experiment.description,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 300,
                  child: ControlsPanel(
                    key: ValueKey(_selected),
                    values: values,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
