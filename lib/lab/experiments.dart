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
];
