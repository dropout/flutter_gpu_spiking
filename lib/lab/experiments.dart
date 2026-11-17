import 'package:flutter/material.dart';

import 'experiment.dart';
import 'params.dart';
import 'scene_toon_experiment.dart';
import 'sparkler_experiment.dart';

/// Every experiment in the lab. Add new ones here.
const List<LabExperiment> labExperiments = [
  FragmentExperiment(
    name: 'Plasma',
    description:
        'Procedural fragment shader: no textures, just time and parameters.',
    fragmentShader: 'LabPlasmaFragment',
    params: [
      FloatParam('scale', 'Scale', min: 1, max: 20, initial: 6),
      FloatParam('speed', 'Speed', min: 0, max: 4, initial: 1),
      FloatParam('mouse', 'Mouse influence', min: 0, max: 2, initial: 0.5),
      BoolParam('invert', 'Invert'),
      ColorParam('a', 'Color A', initial: Color(0xFF1A237E)),
      ColorParam('b', 'Color B', initial: Color(0xFFFF4081)),
    ],
  ),
  FragmentExperiment(
    name: 'Texture warp',
    description:
        'Distorts a texture around the pointer. Pick the texture in the panel.',
    fragmentShader: 'LabTextureWarpFragment',
    params: [
      TextureParam('texture', 'Texture'),
      FloatParam('amount', 'Amount', min: 0, max: 4, initial: 1),
      FloatParam('frequency', 'Frequency', min: 1, max: 60, initial: 25),
      FloatParam('speed', 'Speed', min: 0, max: 8, initial: 3),
      ChoiceParam('mode', 'Mode', options: ['Ripple', 'Swirl']),
      ColorParam('tint', 'Tint', initial: Color(0xFFFFFFFF)),
    ],
  ),
  ToonSceneExperiment(),
  SparklerExperiment(),
  FragmentExperiment(
    name: 'Transition',
    description:
        'Top-to-bottom image transition with a gradient height measured in '
        'viewport heights. Progress runs from 0 to 1; auto-play ping-pongs it.',
    fragmentShader: 'LabTransitionFragment',
    params: [
      FloatParam('progress', 'Progress', min: 0, max: 1, initial: 0),
      BoolParam('auto', 'Auto-play'),
      FloatParam('period', 'Auto-play seconds', min: 0.2, max: 8, initial: 2),
      TextureParam('from', 'From', initial: 'assets/lab/textures/sweet.jpg'),
      TextureParam('to', 'To', initial: 'assets/lab/textures/green.jpeg'),
      FloatParam('sweepLength', 'Sweep length', min: 0, max: 1, initial: 0.5),
      FloatParam('softness', 'Smoothing', min: 0, max: 1, initial: 1),
      FloatParam('wobble', 'Edge wobble', min: 0, max: 0.5, initial: 0.1),
      FloatParam('wobbleScale', 'Wobble scale', min: 0.5, max: 20, initial: 4),
      FloatParam('grain', 'Grain', min: 0, max: 0.2, initial: 0.04),
    ],
  ),
  FragmentExperiment(
    name: 'Parchment',
    description:
        'Cheap procedural paper background. Scroll over the viewport to move '
        'it; the seed reproduces the same paper. Scroll is in viewport '
        'heights (scroll offset / viewport height).',
    fragmentShader: 'LabParchmentFragment',
    scrollParam: 'scroll',
    renderScale: 0.5,
    params: [
      FloatParam('scroll', 'Scroll (screens)', min: 0, max: 40, initial: 0),
      FloatParam('parallax', 'Parallax', min: 0, max: 1, initial: 0.4),
      FloatParam(
        'seed',
        'Seed',
        min: 0,
        max: 9999,
        initial: 42,
        decimals: 0,
        divisions: 9999,
      ),
      FloatParam('aged', 'Age', min: 0, max: 1.5, initial: 0.8),
      FloatParam('mottle', 'Mottle scale', min: 0.5, max: 12, initial: 3),
      FloatParam('grain', 'Grain', min: 0, max: 0.5, initial: 0.12),
      FloatParam('vignette', 'Edge darkening', min: 0, max: 1, initial: 0.4),
      FloatParam(
        'grainScale',
        'Grain frequency',
        min: 50,
        max: 800,
        initial: 300,
        decimals: 0,
      ),
      ColorParam('paper', 'Paper', initial: Color(0xFFEBD9A9)),
      ColorParam('dark', 'Aged tone', initial: Color(0xFF8A5A2B)),
    ],
  ),
  FragmentExperiment(
    name: 'Domain warp',
    description:
        'Fractal Brownian motion folded through itself: f(p + w*f(p + w*f(p))). '
        'Raise the octaves for detail, the warp for swirl; depth chooses how '
        'many times the field is fed back into itself. Relief lights the field '
        'like a surface.',
    fragmentShader: 'LabFbmWarpFragment',
    renderScale: 0.5,
    params: [
      FloatParam('scale', 'Scale', min: 0.5, max: 12, initial: 3),
      FloatParam('octaves', 'Octaves', min: 1, max: 8, initial: 5),
      FloatParam('lacunarity', 'Lacunarity', min: 1.2, max: 3.5, initial: 2),
      FloatParam('gain', 'Gain', min: 0.2, max: 0.9, initial: 0.5),
      FloatParam('warp', 'Warp amount', min: 0, max: 8, initial: 4),
      FloatParam('speed', 'Speed', min: 0, max: 4, initial: 1),
      ChoiceParam(
        'depth',
        'Warp depth',
        options: ['None', 'Single', 'Double'],
        initial: 2,
      ),
      BoolParam('relief', 'Relief lighting'),
      ColorParam('a', 'Color A', initial: Color(0xFF101030)),
      ColorParam('b', 'Color B', initial: Color(0xFFD8A657)),
      ColorParam('c', 'Color C', initial: Color(0xFF1F6F8B)),
      ColorParam('d', 'Color D', initial: Color(0xFFF3EFE0)),
    ],
  ),
];
