import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/simple_lip_detector.dart';
import 'simple_lip_painter.dart';

/// Wrapper that transforms lip coordinates for camera rotation and mirroring
class LipOverlayPainter extends CustomPainter {
  final LipRegion lipRegion;
  final Color color;
  final double opacity;
  final int cameraRotation;
  final bool isFrontCamera;

  LipOverlayPainter({
    required this.lipRegion,
    required this.color,
    required this.opacity,
    required this.cameraRotation,
    required this.isFrontCamera,
  });

  @override
  void paint(Canvas canvas, ui.Size size) {
    // Transform points for front camera mirroring only
    // ML Kit already handles rotation internally
    final transformedPoints = lipRegion.points.map((point) {
      double x = point.dx;
      double y = point.dy;

      // Apply mirroring for front camera
      if (isFrontCamera) {
        x = 1.0 - x;
      }

      return Offset(x, y);
    }).toList();

    // Now use SimpleLipPainter with transformed coordinates
    SimpleLipPainter(
      lipPoints: transformedPoints,
      color: color,
      opacity: opacity,
      frameSize: ui.Size(1.0, 1.0), // Already normalized
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(LipOverlayPainter oldDelegate) {
    return oldDelegate.lipRegion != lipRegion ||
        oldDelegate.color != color ||
        oldDelegate.opacity != opacity;
  }
}
