import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

class BoidsParams {
  double separationWeight = 1.5;
  double alignmentWeight = 1.0;
  double cohesionWeight = 1.0;

  double neighborRadius = .25;
  double separationRadius = .1;

  double maxSpeed = 0.8;
  double minSpeed = 0.3;
  double maxForce = 2.0;
}

class BoidsSim({
  required final int count,
  final int seed = 1,
  final double minSpeed = 0.3,
  final double maxSpeed = 0.8,
}) {
  final math.Random _rng = math.Random(seed);

  final Float32List posX = Float32List(count);
  final Float32List posY = Float32List(count);

  final Float32List velX = Float32List(count);
  final Float32List velY = Float32List(count);

  final Float32List accX = Float32List(count);
  final Float32List accY = Float32List(count);

  final Float32List speed = Float32List(count);
  final Float32List neighbors = Float32List(count);

  double halfWidth = 1, halfHeight = 1;

  void reset(BoidsParams p) {
    for (int i = 0; i < count; i++) {
      final double angle = 2 * math.pi * _rng.nextDouble();
      posX[i] = _rng.nextDouble() * 2 * halfWidth - halfWidth;
      posY[i] = _rng.nextDouble() * 2 * halfHeight - halfHeight;

      final s = p.minSpeed + _rng.nextDouble() * (p.maxSpeed - p.minSpeed);
      velX[i] = math.cos(angle) * s;
      velY[i] = math.sin(angle) * s;

      accX[i] = 0.0;
      accY[i] = 0.0;
      speed[i] = 0.0;
      neighbors[i] = 0.0;
    }
  }

  void step(double dt, BoidsParams p) {
    // Step 1. Compute steering from neighbors for each boid
    for (int i = 0; i < count; i++) {
      // running sums for neighbor information
      var sumVx = 0.0, sumVy = 0.0;
      var sumPx = 0.0, sumPy = 0.0;
      var sepX = 0.0, sepY = 0.0;
      int neighborCount = 0;

      // start checking all other boids to find neighbors and compute separation
      for (int j = 0; j < count; j++) {
        if (i == j) continue;

        // compute distance between boids i and j
        final dx = posX[j] - posX[i];
        final dy = posY[j] - posY[i];
        final d2 = dx * dx + dy * dy;

        // check if j is a neighbor of i
        if (d2 > p.neighborRadius * p.neighborRadius) continue;

        // accumulate velocity and position of neighbor j
        sumVx += velX[j];
        sumVy += velY[j];
        sumPx += posX[j];
        sumPy += posY[j];
        neighborCount++;

        // check for separation
        final d = math.sqrt(d2);
        if (d > 1e-8 && d < p.separationRadius) {
          sepX += -dx / d;
          sepY += -dy / d;
        }
      }

      if (neighborCount > 0) {
        // current vector properties for boid
        final currentVel = Vector2(velX[i], velY[i]);

        // average raw vectors of neighbors
        final avgVel = Vector2(sumVx / neighborCount, sumVy / neighborCount);
        final avgPos = Vector2(sumPx / neighborCount, sumPy / neighborCount);

        // final forces with Reynolds steering behavior
        final alignment = avgVel.calculateReynoldsBehaviour(
          p.maxSpeed,
          currentVel,
        );
        final cohesion = (avgPos - Vector2(posX[i], posY[i]))
            .calculateReynoldsBehaviour(p.maxSpeed, currentVel);
        final separation = (sepX == 0.0 && sepY == 0.0)
            ? Vector2.zero()
            : (Vector2(sepX, sepY).calculateReynoldsBehaviour(p.maxSpeed, currentVel));

        // Accumulated force
        final accumulatedForce =
            (separation * p.separationWeight +
                    alignment * p.alignmentWeight +
                    cohesion * p.cohesionWeight)
                .limit(p.maxForce);

        // Update boid data with the computed acceleration
        // and neighbor count
        accX[i] = accumulatedForce.x;
        accY[i] = accumulatedForce.y;
        neighbors[i] = neighborCount.toDouble();
      } else {
        neighbors[i] = 0.0;
        accX[i] = 0.0;
        accY[i] = 0.0;
      }

      // Clamp the timestep
      final clampedDt = dt.clamp(0.0, 1 / 30).toDouble();

      // Calculate new velocity based on acceleration and time step
      // Clamp the velocity to the maximum speed
      velX[i] += accX[i] * clampedDt;
      velY[i] += accY[i] * clampedDt;

      final v = Vector2(velX[i], velY[i]);
      final s = v.length;

      if (s > p.maxSpeed) {
        v.scale(p.maxSpeed / s);
      } else if (s < p.minSpeed) {
        if (s > 1e-8) {
          v.scale(p.minSpeed / s);
        } else {
          // it's actually zero, has stopped: no direction, so we pick a random one
          final angle = _rng.nextDouble() * 2 * math.pi;   // stopped: no direction
          v.setValues(math.cos(angle) * p.minSpeed, math.sin(angle) * p.minSpeed);
        }
      } 
      velX[i] = v.x;
      velY[i] = v.y;
      speed[i] = v.length;

      // Calculate new position based on velocity and time step
      posX[i] += velX[i] * clampedDt;
      posY[i] += velY[i] * clampedDt;
    
      // horizontal bounds
      if (posX[i] > halfWidth) {
        posX[i] -= 2 * halfWidth;
      } else if (posX[i] < -halfWidth) {
        posX[i] += 2 * halfWidth;
      }

      // vertical bounds
      if (posY[i] > halfHeight) {
        posY[i] -= 2 * halfHeight;
      } else if (posY[i] < -halfHeight) {
        posY[i] += 2 * halfHeight;
      }
    }
  }
}

extension Vector2Extensions on Vector2 {
  Vector2 limit(double max) {
    final len2 = x * x + y * y;
    if (len2 <= max * max) return this;
    final scale = max / math.sqrt(len2);
    return Vector2(x * scale, y * scale);
  }

  Vector2 calculateReynoldsBehaviour(double maxSpeed, Vector2 currentVector) {
    final normalizedVector = normalized();
    final desired = normalizedVector * maxSpeed;
    return Vector2(desired.x - currentVector.x, desired.y - currentVector.y);
  }
}
