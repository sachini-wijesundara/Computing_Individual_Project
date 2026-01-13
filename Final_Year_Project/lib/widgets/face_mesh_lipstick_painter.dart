import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/mlkit_face_mesh_service.dart';
import '../services/ml_kit_types_stub.dart';  // iOS: stub types';

/// Painter for lipstick using ML Kit Face Mesh landmarks (468 precise points)
class FaceMeshLipstickPainter extends CustomPainter {
  final FaceMeshLipResult lipResult;
  final Rect previewRectOnScreen;
  final Color shade;
  final double intensity;

  FaceMeshLipstickPainter({
    required this.lipResult,
    required this.previewRectOnScreen,
    required this.shade,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, ui.Size size) {
    // Convert normalized landmarks to screen coordinates
    final outerLipPoints = _landmarksToOffsets(lipResult.outerLip);
    final innerLipPoints = _landmarksToOffsets(lipResult.innerLip);

    if (outerLipPoints.length < 3) return;

    // Create lip path
    final path = Path();
    path.addPolygon(outerLipPoints, true);
    
    if (innerLipPoints.length >= 3) {
      path.addPath(Path()..addPolygon(innerLipPoints, true), Offset.zero);
      path.fillType = PathFillType.evenOdd; // Subtract inner lip
    }

    // Clip to preview bounds to prevent bleeding
    canvas.save();
    canvas.clipRect(previewRectOnScreen);
    
    canvas.saveLayer(previewRectOnScreen.inflate(8), Paint());

    // Apply lipstick color with transparency for natural look
    final fillPaint = Paint()
      ..color = shade.withValues(alpha: (intensity * 0.55).clamp(0.0, 1.0))
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(path, fillPaint);

    // Add subtle edge for definition
    final edgePaint = Paint()
      ..color = shade.withValues(alpha: (intensity * 0.18).clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..isAntiAlias = true;
    canvas.drawPath(path, edgePaint);

    // Add highlight for natural shine
    final lipBounds = path.getBounds();
    final highlightShader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.white12, Colors.transparent],
      stops: [0.0, 0.15],
    ).createShader(lipBounds);
    
    final highlightPaint = Paint()..shader = highlightShader;
    canvas.drawPath(path, highlightPaint);

    canvas.restore();
    canvas.restore();
  }

  /// Convert Face Mesh landmarks to screen coordinates
  List<Offset> _landmarksToOffsets(List<LipLandmark> landmarks) {
    return landmarks.map((lm) {
      double u = lm.x;
      double v = lm.y;

      // Mirror for front camera
      if (lipResult.mirrored) {
        u = 1.0 - u;
      }

      // Map to screen coordinates
      return Offset(
        previewRectOnScreen.left + u * previewRectOnScreen.width,
        previewRectOnScreen.top + v * previewRectOnScreen.height,
      );
    }).toList();
  }

  @override
  bool shouldRepaint(FaceMeshLipstickPainter oldDelegate) {
    return lipResult != oldDelegate.lipResult ||
        shade != oldDelegate.shade ||
        intensity != oldDelegate.intensity;
  }
}
