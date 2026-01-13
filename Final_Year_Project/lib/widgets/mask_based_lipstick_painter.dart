import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/mlkit_face_mesh_service.dart';
import '../services/ml_kit_types_stub.dart';  // iOS: stub types

/// Simple mask-based lipstick overlay - NO coordinate mapping!
/// Works like Snapchat/Instagram filters
class MaskBasedLipstickPainter extends CustomPainter {
  final FaceMeshLipResult lipResult;
  final Rect previewRect;
  final Color shade;
  final double intensity;

  MaskBasedLipstickPainter({
    required this.lipResult,
    required this.previewRect,
    required this.shade,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, ui.Size size) {
    // Get lip landmarks
    final outerLip = lipResult.outerLip;
    if (outerLip.length < 3) return;

    // Calculate bounding box of lips in normalized space
    double minX = 1.0, maxX = 0.0, minY = 1.0, maxY = 0.0;
    for (final pt in outerLip) {
      if (pt.x < minX) minX = pt.x;
      if (pt.x > maxX) maxX = pt.x;
      if (pt.y < minY) minY = pt.y;
      if (pt.y > maxY) maxY = pt.y;
    }

    // Convert to screen coordinates
    double u1 = minX;
    double u2 = maxX;
    double v1 = minY;
    double v2 = maxY;
    
    // Mirror X for front camera
    if (lipResult.mirrored) {
      final temp = u1;
      u1 = 1.0 - u2;
      u2 = 1.0 - temp;
    }
    
    // Map to screen space
    final lipBounds = Rect.fromLTRB(
      previewRect.left + u1 * previewRect.width,
      previewRect.top + v1 * previewRect.height,
      previewRect.left + u2 * previewRect.width,
      previewRect.top + v2 * previewRect.height,
    );

    // Expand bounds slightly for better coverage
    final expandedBounds = lipBounds.inflate(lipBounds.width * 0.1);

    // Draw lipstick as filled rectangle (simple approach)
    // In reality, you'd use a lip-shaped mask image here
    final paint = Paint()
      ..color = shade.withValues(alpha: intensity * 0.6)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Create rounded rectangle for lip shape
    final rRect = RRect.fromRectAndRadius(
      expandedBounds,
      Radius.circular(expandedBounds.height * 0.4),
    );

    canvas.drawRRect(rRect, paint);

    // Add highlight
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: intensity * 0.15)
      ..style = PaintingStyle.fill;
    
    final highlightRect = Rect.fromLTRB(
      expandedBounds.left,
      expandedBounds.top,
      expandedBounds.right,
      expandedBounds.top + expandedBounds.height * 0.3,
    );
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(highlightRect, Radius.circular(expandedBounds.height * 0.4)),
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(MaskBasedLipstickPainter oldDelegate) {
    return lipResult != oldDelegate.lipResult ||
        shade != oldDelegate.shade ||
        intensity != oldDelegate.intensity;
  }
}
