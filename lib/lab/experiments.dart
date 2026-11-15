import 'package:flutter/material.dart';

import 'experiment.dart';
import 'params.dart';
import 'scene_toon_experiment.dart';

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
];
