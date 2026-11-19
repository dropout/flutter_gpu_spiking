import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_gpu_spiking/lab/boids_sim.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'experiment.dart';
import 'params.dart';

class BoidsExperiment extends LabExperiment {
  const new();

  @override
  String get name => 'Boids Experiment';

  @override
  String get description => 'An experiment simulating boids behavior';

  @override
  List<LabParam> get params => [
    // simulation
    FloatParam('separation', 'Separation', min: 0.0, max: 4.0, initial: 1.5),
    FloatParam('alignment', 'Alignment', min: 0.0, max: 4.0, initial: 1.0),
    FloatParam('cohesion', 'Cohesion', min: 0.0, max: 4.0, initial: 1.0),
    FloatParam(
      'neighborRadius',
      'Neighbor Radius',
      min: 0.0,
      max: 10.0,
      initial: 2.0,
    ),
    FloatParam(
      'separationRadius',
      'Separation Radius',
      min: 0.05,
      max: 10.0,
      initial: 1.0,
    ),

    FloatParam('minSpeed', 'Min Speed', min: 0.0, max: 10.0, initial: 0.5),
    FloatParam('maxSpeed', 'Max Speed', min: 0.1, max: 10.0, initial: 2.0),
    FloatParam('maxForce', 'Max Force', min: 0.1, max: 10.0, initial: 0.03),
    FloatParam('size', 'Size', min: 0.01, max: 0.15, initial: 0.04),

    // reactivity
    FloatParam('stretch', 'Speed stretch', min: 0, max: 2, initial: 0.8),
    FloatParam('squash', 'Speed squash', min: 0, max: 0.8, initial: 0.3),
    FloatParam('crowdTint', 'Crowd brightness', min: 0, max: 1, initial: 0.5),
    ColorParam('slowColor', 'Slow color', initial: Color(0xFF3B82F6)),
    ColorParam('fastColor', 'Fast color', initial: Color(0xFFFFB347)),
  ];

  @override
  Widget buildView(BuildContext context, LabContext lab) =>
      _BoidsView(key: const ValueKey('boids_view'), lab: lab);
}

class const _BoidsView({required final LabContext lab, super.key})
    extends StatefulWidget {
  @override
  State<_BoidsView> createState() => _BoidsViewState();
}

class _BoidsViewState extends State<_BoidsView> {
  static const int _count = 200;

  final Scene _scene = Scene();
  final OrthographicCamera _camera = OrthographicCamera(
    projection: OrthographicProjection(size: const OrthographicSize.height(2)),
    position: vm.Vector3(0, 0, -5),
    target: vm.Vector3.zero(),
  );

  late final BoidsSim _sim;
  final BoidsParams _params = BoidsParams();
  late final InstancedMesh _mesh;
  final vm.Vector4 _scratch = vm.Vector4.zero();

  bool _built = false;
  bool _started = false;
  double _aspect = 1;

  @override
  void initState() {
    super.initState();
    Scene.initializeStaticResources().then((_) {
      if (!mounted) return;
      _build();
      setState(() => _built = true);
    });
  }

  void _build() {
    // Build the scene
    final material = UnlitMaterial();
    _mesh = InstancedMesh(geometry: buildBoidGeometry(), material: material);
    for (var i = 0; i < _count; i++) {
      _mesh.addInstance(vm.Matrix4.identity(), color: vm.Vector4(1, 1, 1, 1));
    }
    _scene.add(Node()..addComponent(InstancedMeshComponent(_mesh)));

    // Build the simulation
    _sim = BoidsSim(count: _count, minSpeed: 0.5, maxSpeed: 2.0);
    _sim.reset(_params);
  }

  @override
  Widget build(BuildContext context) {
    if (!_built) {
      return const Center(child: CircularProgressIndicator());
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          radius: 1.1,
          colors: [Color(0xFF0B1020), Color(0xFF020308)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxHeight > 0) {
            _aspect = constraints.maxWidth / constraints.maxHeight;
          }
          return SceneView(
            _scene,
            camera: _camera,
            onTick: (elapsed, dt) => _onTick(dt),
          );
        },
      ),
    );
  }

  void _onTick(double dt) {
    _syncParams();

    // update bound to match the aspect ratio of the view
    _sim.halfWidth = _aspect;
    _sim.halfHeight = 1;

    // reset the simulation if it hasn't started yet
    if (!_started) {
      _sim.reset(_params);
      _started = true;
    }

    // advance the simulation
    _sim.step(dt, _params);

    // sync the transforms with the updated simulation state
    // _syncTransforms(widget.lab.values.getFloat('size'));
    _syncTransforms(0.04);
  }

  void _syncParams() {
    final v = widget.lab.values;
    _params
      ..separationWeight = v.getFloat('separation')
      ..alignmentWeight = v.getFloat('alignment')
      ..cohesionWeight = v.getFloat('cohesion')
      ..neighborRadius = v.getFloat('neighborRadius')
      ..separationRadius = v.getFloat('separationRadius')
      ..maxSpeed = v.getFloat('maxSpeed')
      ..minSpeed = v.getFloat('minSpeed')
      ..maxForce = v.getFloat('maxForce');
  }

  void _syncTransforms(double size) {
    _mesh.updateInstanceTransforms((list) {
      for (var i = 0; i < _count; i++) {
        // range convert speeds to create a value that goes between
        // 0.0 and 1.0 based on the speed of the boid relative to min and max speed
        final range = math.max(_params.maxSpeed - _params.minSpeed, 1e-6);
        final t = ((_sim.speed[i] - _params.minSpeed) / range).clamp(0.0, 1.0);
        final boidSize = widget.lab.values.getFloat('size');

        // angle of the boid based on its velocity
        final angle = math.atan2(_sim.velY[i], _sim.velX[i]);

        // compute the stretch and squash based on the speed
        // length grows with speed, creating a stretch effect
        final stretch = boidSize * (1.0 + widget.lab.values.getFloat('stretch') * t);
        // width shrinks with speed, creating a squash effect
        final squash = boidSize * (1.0 - widget.lab.values.getFloat('squash') * t);

        // instance transform matrix for the current boid
        final vm.Matrix4 m = list[i];
        m
          ..setIdentity()
          ..translateByDouble(_sim.posX[i], _sim.posY[i], 0, 1)
          ..rotateZ(angle)
          ..scaleByDouble(stretch, squash, boidSize, 1.0);
        
        // onto the colors
        final slowColor = widget.lab.values.getColor('slowColor');
        final fastColor = widget.lab.values.getColor('fastColor');
        final crowdTint = widget.lab.values.getFloat('crowdTint');

        final r = slowColor.r + (fastColor.r - slowColor.r) * t;
        final g = slowColor.g + (fastColor.g - slowColor.g) * t;
        final b = slowColor.b + (fastColor.b - slowColor.b) * t;

        // 0..1 based on crowding 0..12
        final crowd = (_sim.neighbors[i] / 12).clamp(0.0, 1.0);
        final k = 1 + crowdTint * crowd; // assuming crowdTint is used as a multiplier for the red channel
        
        _scratch.setValues(r * k, g * k, b * k, 1.0);
        _mesh.setInstanceColor(i, _scratch);

      }
    }, recomputeWinding: false);
  }

  @override
  void dispose() {
    _scene.dispose();
    super.dispose();
  }
}

MeshGeometry buildBoidGeometry() {
  // Arrowhead vertex points
  final vertexPositions = Float32List.fromList([
    0.5,
    0.0,
    0.0,
    -0.5,
    0.3,
    0.0,
    -0.25,
    0.0,
    0.0,
    -0.5,
    -0.3,
    0.0,
  ]);

  const indices = [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2];

  return MeshGeometry.fromArrays(positions: vertexPositions, indices: indices);
}
