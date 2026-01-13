import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Advanced adaptive smoother for landmark tracking with motion-based adjustment.
/// Dynamically adjusts smoothing strength based on movement velocity to eliminate
/// lag during face movement while maintaining stability during stillness.
class LandmarkSmoother {
  LandmarkSmoother({
    this.minAlpha = 0.3,     // Lower bound for slow/static movements (more smoothing)
    this.maxAlpha = 0.85,    // Upper bound for fast movements (more responsive)
    this.velocityThreshold = 0.01, // Threshold to detect motion
    this.enablePrediction = true,  // Enable velocity-based prediction
  });

  final double minAlpha;
  final double maxAlpha;
  final double velocityThreshold;
  final bool enablePrediction;

  List<Offset>? _last;
  List<Offset>? _velocity;
  List<double>? _velocityMagnitudes;

  /// Smooths landmarks with adaptive alpha based on motion velocity
  List<Offset> smooth(List<Offset> current) {
    if (_last == null || _last!.length != current.length) {
      _last = List<Offset>.from(current);
      _velocity = List.filled(current.length, Offset.zero);
      _velocityMagnitudes = List.filled(current.length, 0.0);
      return current;
    }

    final out = <Offset>[];
    final newVelocities = <Offset>[];
    final newVelocityMagnitudes = <double>[];

    for (int i = 0; i < current.length; i++) {
      final c = current[i];
      final p = _last![i];

      // Calculate instantaneous velocity
      final velocityX = c.dx - p.dx;
      final velocityY = c.dy - p.dy;
      final velocity = Offset(velocityX, velocityY);
      final velocityMag = math.sqrt(velocityX * velocityX + velocityY * velocityY);

      // Smooth velocity to avoid jitter in alpha calculation
      final smoothedVelocityMag = _velocityMagnitudes![i] * 0.7 + velocityMag * 0.3;
      newVelocityMagnitudes.add(smoothedVelocityMag);

      // Adaptive alpha: higher velocity = higher alpha (more responsive)
      // Maps velocity range [0, velocityThreshold*3] to alpha range [minAlpha, maxAlpha]
      final normalizedVelocity = (smoothedVelocityMag / (velocityThreshold * 3)).clamp(0.0, 1.0);
      final adaptiveAlpha = minAlpha + (maxAlpha - minAlpha) * normalizedVelocity;

      // Apply exponential smoothing with adaptive alpha
      Offset smoothed = Offset(
        adaptiveAlpha * c.dx + (1 - adaptiveAlpha) * p.dx,
        adaptiveAlpha * c.dy + (1 - adaptiveAlpha) * p.dy,
      );

      // Optional: Add velocity-based prediction for very fast movements
      if (enablePrediction && smoothedVelocityMag > velocityThreshold * 2) {
        // Predict next position based on velocity (reduces perceived lag)
        final predictionFactor = 0.3; // Conservative prediction
        smoothed = Offset(
          smoothed.dx + _velocity![i].dx * predictionFactor,
          smoothed.dy + _velocity![i].dy * predictionFactor,
        );
      }

      // Update velocity history
      newVelocities.add(Offset(
        smoothed.dx - p.dx,
        smoothed.dy - p.dy,
      ));

      out.add(smoothed);
    }

    _last = out;
    _velocity = newVelocities;
    _velocityMagnitudes = newVelocityMagnitudes;
    return out;
  }

  void reset() {
    _last = null;
    _velocity = null;
    _velocityMagnitudes = null;
  }
}
