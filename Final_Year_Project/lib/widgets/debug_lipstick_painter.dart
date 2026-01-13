import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/mlkit_face_mesh_service.dart';
import '../services/ml_kit_types_stub.dart';  // iOS: stub types

/// DEBUG painter - shows WHERE Face Mesh detects lips with RED DOTS
class DebugLipstickPainter extends CustomPainter {
  final FaceMeshLipResult lipResult;
  final Rect previewRect;
  final Color shade;
  final double intensity;

  DebugLipstickPainter({
    required this.lipResult,
    required this.previewRect,
    required this.shade,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, ui.Size size) {
    // Draw RED DOTS on each lip landmark to SEE where they are
    final dotPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    for (final pt in lipResult.outerLip) {
      double u = pt.x;
      double v = pt.y;

      // Mirror for front camera
      if (lipResult.mirrored) {
        u = 1.0 - u;
      }

      // Map to screen
      final screenX = previewRect.left + u * previewRect.width;
      final screenY = previewRect.top + v * previewRect.height;

      // Draw BIG red dot so we can SEE it
      canvas.drawCircle(Offset(screenX, screenY), 8, dotPaint);
    }

    // Draw WHITE outline around preview rect for reference
    final rectPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(previewRect, rectPaint);

    // Draw coordinate info text
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Lip Y range: ${lipResult.outerLip.map((p) => p.y.toStringAsFixed(2)).join(", ")}',
        style: TextStyle(color: Colors.yellow, fontSize: 12, backgroundColor: Colors.black),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(10, 100));
  }

  @override
  bool shouldRepaint(DebugLipstickPainter oldDelegate) => true;
}
