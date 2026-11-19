import 'dart:math' as math;

import 'package:flutter_gpu_spiking/lab/boids_sim.dart';
import 'package:flutter_test/flutter_test.dart';

// Float32 storage loses precision, so compare with a small tolerance.
const _eps = 1e-4;

BoidsSim _makeSim({int count = 200, int seed = 1}) {
  final sim = BoidsSim(count: count, seed: seed);
  sim.reset(BoidsParams());
  return sim;
}

double _speedOf(BoidsSim sim, int i) =>
    math.sqrt(sim.velX[i] * sim.velX[i] + sim.velY[i] * sim.velY[i]);

void _run(BoidsSim sim, BoidsParams p, int steps, {double dt = 1 / 60}) {
  for (var s = 0; s < steps; s++) {
    sim.step(dt, p);
  }
}

/// 0 = headings are random, 1 = everyone moves the same way.
double _alignment(BoidsSim sim) {
  var sx = 0.0, sy = 0.0, sumSpeed = 0.0;
  for (var i = 0; i < sim.count; i++) {
    sx += sim.velX[i];
    sy += sim.velY[i];
    sumSpeed += _speedOf(sim, i);
  }
  return math.sqrt(sx * sx + sy * sy) / sumSpeed;
}

void _expectSane(BoidsSim sim, BoidsParams p) {
  for (var i = 0; i < sim.count; i++) {
    for (final v in [sim.posX[i], sim.posY[i], sim.velX[i], sim.velY[i]]) {
      expect(v.isFinite, isTrue, reason: 'boid $i has a non-finite value');
    }
    expect(sim.posX[i].abs(), lessThanOrEqualTo(sim.halfWidth + _eps));
    expect(sim.posY[i].abs(), lessThanOrEqualTo(sim.halfHeight + _eps));

    final s = _speedOf(sim, i);
    expect(s, greaterThanOrEqualTo(p.minSpeed - _eps), reason: 'boid $i slow');
    expect(s, lessThanOrEqualTo(p.maxSpeed + _eps), reason: 'boid $i fast');
  }
}

void main() {
  test('reset scatters boids inside the bounds with valid speeds', () {
    final p = BoidsParams();
    final sim = _makeSim();
    _expectSane(sim, p);
  });

  test('stays finite, in bounds and within speed limits over time', () {
    final p = BoidsParams();
    final sim = _makeSim();
    _run(sim, p, 600);
    _expectSane(sim, p);
  });

  test('survives a large frame hitch without blowing up', () {
    final p = BoidsParams();
    final sim = _makeSim();
    // The sim should clamp dt itself; if it does not, this is the failure
    // you will see on screen when a frame takes 200 ms.
    sim.step(0.2, p);
    _expectSane(sim, p);
  });

  test('a lone boid keeps moving (min speed holds with no neighbours)', () {
    final p = BoidsParams();
    final sim = _makeSim(count: 1);
    _run(sim, p, 300);
    expect(_speedOf(sim, 0), greaterThanOrEqualTo(p.minSpeed - _eps));
    expect(sim.neighbors[0], 0);
  });

  test('step fills the renderer outputs', () {
    final p = BoidsParams();
    final sim = _makeSim();
    _run(sim, p, 60);
    for (var i = 0; i < sim.count; i++) {
      expect(sim.speed[i], closeTo(_speedOf(sim, i), _eps));
    }
    // Dense flock in a 2x2 box: somebody must have a neighbour.
    expect(sim.neighbors.any((n) => n > 0), isTrue);
  });

  test('alignment pulls headings together', () {
    final p = BoidsParams()
      ..alignmentWeight = 3
      ..separationWeight = 0.5
      ..cohesionWeight = 0.5;
    final sim = _makeSim();
    final before = _alignment(sim);
    _run(sim, p, 900);
    final after = _alignment(sim);
    // ignore: avoid_print
    print('alignment: ${before.toStringAsFixed(2)} -> ${after.toStringAsFixed(2)}');
    expect(after, greaterThan(before + 0.2));
  });

  test('separation pushes two close boids apart', () {
    final p = BoidsParams()
      ..alignmentWeight = 0
      ..cohesionWeight = 0
      ..separationWeight = 3;
    final sim = _makeSim(count: 2);
    // Place them closer than separationRadius, at rest-ish.
    sim.posX[0] = -0.02;
    sim.posY[0] = 0;
    sim.posX[1] = 0.02;
    sim.posY[1] = 0;
    sim.velX.fillRange(0, 2, 0);
    sim.velY.fillRange(0, 2, 0);

    double gap() => (sim.posX[1] - sim.posX[0]).abs();
    final before = gap();
    _run(sim, p, 30);
    expect(gap(), greaterThan(before));
  });

  test('same seed gives the same flock', () {
    final p = BoidsParams();
    final a = _makeSim(seed: 7);
    final b = _makeSim(seed: 7);
    _run(a, p, 120);
    _run(b, p, 120);
    for (var i = 0; i < a.count; i++) {
      expect(a.posX[i], b.posX[i]);
      expect(a.posY[i], b.posY[i]);
    }
  });
}
