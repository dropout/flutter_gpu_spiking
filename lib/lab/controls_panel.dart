import 'package:flutter/material.dart';

import 'lab_textures.dart';
import 'params.dart';

/// Generic controls for an experiment's [LabValues].
class ControlsPanel extends StatelessWidget {
  const ControlsPanel({super.key, required this.values});

  final LabValues values;

  @override
  Widget build(BuildContext context) {
    final slots = {for (final s in values.slots) s.param.id: s};
    return ListenableBuilder(
      listenable: values,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final param in values.params) ...[
            _control(context, param, slots[param.id]),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _control(BuildContext context, LabParam param, ParamSlot? slot) {
    final caption = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontFamily: 'Menlo',
      color: Theme.of(context).colorScheme.outline,
    );
    Widget header(String trailing) => Row(
      children: [
        Expanded(child: Text(param.label)),
        Text(trailing, style: caption),
      ],
    );
    final glsl = slot?.glsl ?? 'u_texture${_textureIndex(param)}';

    switch (param) {
      case FloatParam():
        final v = values.getFloat(param.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header('$glsl  ${v.toStringAsFixed(param.decimals)}'),
            Slider(
              value: v.clamp(param.min, param.max),
              min: param.min,
              max: param.max,
              divisions: param.divisions,
              onChanged: (x) => values.set(param.id, x),
            ),
          ],
        );
      case IntParam():
        final v = values.getInt(param.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header('$glsl  $v'),
            Slider(
              value: v.clamp(param.min, param.max).toDouble(),
              min: param.min.toDouble(),
              max: param.max.toDouble(),
              divisions: param.max - param.min,
              onChanged: (x) => values.set(param.id, x.round()),
            ),
          ],
        );
      case BoolParam():
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(param.label),
          subtitle: Text(glsl, style: caption),
          value: values.getBool(param.id),
          onChanged: (x) => values.set(param.id, x),
        );
      case ChoiceParam():
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(glsl),
            const SizedBox(height: 4),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (var i = 0; i < param.options.length; i++)
                  ButtonSegment(value: i, label: Text(param.options[i])),
              ],
              selected: {values.getChoice(param.id)},
              onSelectionChanged: (s) => values.set(param.id, s.first),
            ),
          ],
        );
      case ColorParam():
        final c = values.getColor(param.id);
        void channel(int index, double x) {
          final rgba = [c.r, c.g, c.b, c.a]..[index] = x;
          values.set(
            param.id,
            Color.from(
              alpha: rgba[3],
              red: rgba[0],
              green: rgba[1],
              blue: rgba[2],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: c,
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(param.label)),
                Text(glsl, style: caption),
              ],
            ),
            for (final (i, name) in ['R', 'G', 'B'].indexed)
              Row(
                children: [
                  SizedBox(width: 16, child: Text(name, style: caption)),
                  Expanded(
                    child: Slider(
                      value: [c.r, c.g, c.b][i],
                      onChanged: (x) => channel(i, x),
                    ),
                  ),
                ],
              ),
          ],
        );
      case TextureParam():
        return FutureBuilder<List<String>>(
          future: LabTextures.list(),
          builder: (context, snapshot) {
            final textures = snapshot.data ?? const <String>[];
            final selected = values.getTexture(param.id);
            // Default to the first texture once the list is known.
            if (selected == null && textures.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => values.set(param.id, textures.first),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header(glsl),
                const SizedBox(height: 4),
                DropdownButton<String>(
                  isExpanded: true,
                  value: textures.contains(selected) ? selected : null,
                  hint: Text(
                    snapshot.hasData && textures.isEmpty
                        ? 'No textures in ${LabTextures.directory}'
                        : 'Loading...',
                  ),
                  items: [
                    for (final t in textures)
                      DropdownMenuItem(
                        value: t,
                        child: Text(LabTextures.displayName(t)),
                      ),
                  ],
                  onChanged: (t) => values.set(param.id, t),
                ),
              ],
            );
          },
        );
    }
  }

  int _textureIndex(LabParam param) =>
      values.params.whereType<TextureParam>().toList().indexOf(
        param as TextureParam,
      );
}
