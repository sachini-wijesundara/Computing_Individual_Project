import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/simple_face_bounds_detector.dart';
import '../services/ml_kit_types_stub.dart';  // iOS: stub types

/// Simple lipstick overlay using face bounding box
/// No coordinate mapping - just position in lower face area!
class SimpleLipstickOverlay extends CustomPainter {
  final FaceBounds faceBounds;
  final Rect previewRect;
  final Color lipstickColor;
  final double intensity;
  final bool frontCamera;

  SimpleLipstickOverlay({
    required this.faceBounds,
    required this.previewRect,
    required this.lipstickColor,
    required this.intensity,
    required this.frontCamera,
  });

  @override
  void paint(Canvas canvas, ui.Size size) {
    // Calculate face position on screen
    double faceLeft = faceBounds.left;
    double faceTop = faceBounds.top;
    double faceWidth = faceBounds.width;
    double faceHeight = faceBounds.height;

    // Mirror for front camera
    if (frontCamera) {
      faceLeft = 1.0 - faceLeft - faceWidth;
    }

    // Convert to screen coordinates
    final faceRect = Rect.fromLTWH(
      previewRect.left + faceLeft * previewRect.width,
      previewRect.top + faceTop * previewRect.height,
      faceWidth * previewRect.width,
      faceHeight * previewRect.height,
    );

    // FIXED: Lips are in UPPER part of face (around mouth, not bottom)
    // Position lip region at ~40% from top of face where mouth actually is
    final lipTop = faceRect.top + faceRect.height * 0.40; // 40% down from top
    final lipHeight = faceRect.height * 0.12; // 12% of face height
    final lipWidth = faceRect.width * 0.4; // 40% of face width  
    final lipLeft = faceRect.left + (faceRect.width - lipWidth) / 2; // Centered

    final lipRect = Rect.fromLTWH(lipLeft, lipTop, lipWidth, lipHeight);

    // Draw lipstick as rounded rectangle
    final rRect = RRect.fromRectAndRadius(
      lipRect,
      Radius.circular(lipHeight * 0.5), // Make it pillshaped
    );

    // Fill with lipstick color
    final fillPaint = Paint()
      ..color = lipstickColor.withValues(alpha: intensity * 0.7)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawRRect(rRect, fillPaint);

    // Add highlight for gloss effect
    final highlightRect = Rect.fromLTWH(
      lipRect.left,
      lipRect.top,
      lipRect.width,
      lipRect.height * 0.4,
    );

    final highlightGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withValues(alpha: intensity * 0.3),
        Colors.transparent,
      ],
    );

    final highlightPaint = Paint()
      ..shader = highlightGradient.createShader(highlightRect);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        highlightRect,
        Radius.circular(lipHeight * 0.5),
      ),
      highlightPaint,
    );

    // DEBUG: Draw face rect outline
    if (false) { // Set to true for debugging
      final debugPaint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(faceRect, debugPaint);
    }
  }

  @override
  bool shouldRepaint(SimpleLipstickOverlay oldDelegate) {
    return faceBounds != oldDelegate.faceBounds ||
        lipstickColor != oldDelegate.lipstickColor ||
        intensity != oldDelegate.intensity;
  }
}
