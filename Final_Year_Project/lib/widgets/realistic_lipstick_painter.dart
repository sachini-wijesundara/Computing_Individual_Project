import 'package:flutter/material.dart';
import '../services/simple_lip_detector.dart';
import '../services/landmark_smoother.dart';

class RealisticLipstickPainter extends CustomPainter {
  // Centralized tuning knobs (adjust here when calibrating on device).
  static const double kMaxFillAlpha = 0.55; // cap opacity to keep skin texture
  static const double kHighlightStrength = 0.14;
  static const double kInnerShadowStrength = 0.03;

  final LipRegion lipRegion;
  final Rect previewRectOnScreen;
  final Color shade;
  final double intensity;
  final bool isFrontFacing;
  final bool showLandmarks;
  // Optional inner-lip path; if present we subtract to avoid filling the mouth.
  final List<Offset>? innerLipPoints;
  // Fine‑tune placement (fraction of mask width/height). Negative = left/up.
  final double offsetDXFraction;
  final double offsetDYFraction;
  // Uniform scaling around centroid to better fit lips.
  final double scaleX;
  final double scaleY;

  static final LandmarkSmoother _outerSmoother =
      LandmarkSmoother(
        minAlpha: 0.3,   // Stable during stillness
        maxAlpha: 0.85,  // Highly responsive during movement
        velocityThreshold: 0.008,
        enablePrediction: true,
      );

  RealisticLipstickPainter({
    required this.lipRegion,
    required this.previewRectOnScreen,
    required this.shade,
    required this.intensity,
    this.isFrontFacing = true,
    this.showLandmarks = false,
    this.innerLipPoints,
    this.offsetDXFraction = 0.0,  // RESET: was -0.04
    this.offsetDYFraction = 0.0,  // RESET: was -0.12  
    this.scaleX = 1.0,            // RESET: was 0.95
    this.scaleY = 1.0,            // RESET: was 0.95
  });

  @override
  void paint(Canvas canvas, Size size) {
    final outer = _outerSmoother.smooth(_toOffsets(lipRegion.points));
    if (outer.length < 3) return;

    final outerSmooth = _smooth(outer, iterations: 1); // lighter for FPS
    final outerScaled = _scale(
      outerSmooth,
      scaleX: scaleX,
      scaleY: scaleY,
    );
    final outerAdjusted = _nudge(
      outerScaled,
      dxFrac: offsetDXFraction,
      dyFrac: offsetDYFraction,
    );

    // Debug mode: just show landmarks and skip rendering
    if (showLandmarks) {
      _drawLandmarks(canvas, outer, Colors.yellow); // Raw smoothed points
      _drawLandmarks(canvas, outerAdjusted, Colors.red); // Final adjusted points
      
      // Draw bounds for debugging
      final paint = Paint()
        ..color = Colors.green.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(previewRectOnScreen, paint);
      return;
    }

    final path = Path()..addPolygon(outerAdjusted, true);
    if (innerLipPoints != null && innerLipPoints!.length > 3) {
      final inner = _scale(
        _nudge(
          _smooth(_toOffsets(innerLipPoints!), iterations: 1),
          dxFrac: offsetDXFraction * 0.5,
          dyFrac: offsetDYFraction * 0.5,
        ),
        scaleX: scaleX * 0.98,
        scaleY: scaleY * 0.98,
      );
      path.addPath(Path()..addPolygon(inner, true), Offset.zero);
      path.fillType = PathFillType.evenOdd; // subtract inner
    }

    // Validate lip path bounds to prevent rendering artifacts
    final pathBounds = path.getBounds();
    if (!_isValidLipBounds(pathBounds, previewRectOnScreen)) {
      // Skip rendering if bounds seem erroneous
      return;
    }

    final clamped = intensity.clamp(0.0, 1.0);
    final baseAlpha = (kMaxFillAlpha * clamped).clamp(0.0, kMaxFillAlpha);
    final edgeAlpha = 0.18 * clamped;

    // Clip to preview bounds to prevent bleeding outside camera preview
    canvas.save();
    canvas.clipRect(previewRectOnScreen);
    
    canvas.saveLayer(previewRectOnScreen.inflate(8), Paint());

    // Feathered fill
    final fillPaint = Paint()
      ..color = shade.withOpacity(baseAlpha)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(path, fillPaint);

    // Slight darker outline for definition
    final edgePaint = Paint()
      ..color = shade.withOpacity(edgeAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..isAntiAlias = true;
    canvas.drawPath(path, edgePaint);

    // Minimal highlight to keep texture
    final lipBounds = path.getBounds();
    final Shader highlightShader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.white12, Colors.transparent],
      stops: [0.0, 0.15],
    ).createShader(lipBounds);
    final Paint highlight = Paint()..shader = highlightShader;
    canvas.drawPath(path, highlight);

    canvas.restore();
    canvas.restore();
  }

  /// Validates that lip bounds are reasonable to prevent rendering artifacts.
  /// Returns false if bounds seem erroneous (too large or outside preview).
  bool _isValidLipBounds(Rect lipBounds, Rect previewBounds) {
    // Very relaxed tolerance - we rely on clipping to prevent bleeding
    final tolerance = 200.0; // pixels - allow more flexibility
    if (lipBounds.left < previewBounds.left - tolerance ||
        lipBounds.right > previewBounds.right + tolerance ||
        lipBounds.top < previewBounds.top - tolerance ||
        lipBounds.bottom > previewBounds.bottom + tolerance) {
      return false;
    }

    // Relaxed size constraints - lips can be larger on screen
    final maxWidth = previewBounds.width * 0.6; // increased from 0.4
    final maxHeight = previewBounds.height * 0.5; // increased from 0.3
    if (lipBounds.width > maxWidth || lipBounds.height > maxHeight) {
      return false;
    }

    // Very minimal size check - only reject obviously wrong detections
    final minWidth = previewBounds.width * 0.03; // reduced from 0.05
    final minHeight = previewBounds.height * 0.01; // reduced from 0.02
    if (lipBounds.width < minWidth || lipBounds.height < minHeight) {
      return false;
    }

    return true;
  }

  List<Offset> _toOffsets(List<Offset> normPts) {
    return normPts.map((p) {
      double u = p.dx;
      double v = p.dy;

      // Flip horizontally for front camera
      if (isFrontFacing) {
        u = 1.0 - u;
      }

      // Use coordinates EXACTLY as ML Kit provides them
      return Offset(
        previewRectOnScreen.left + u * previewRectOnScreen.width,
        previewRectOnScreen.top + v * previewRectOnScreen.height,
      );
    }).toList(growable: false);
  }

  void _drawLandmarks(Canvas canvas, List<Offset> points, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final point in points) {
      canvas.drawCircle(point, 2.0, paint);
    }
  }

  List<Offset> _smooth(List<Offset> pts, {int iterations = 1}) {
    if (pts.length < 4 || iterations <= 0) return pts;
    var current = List<Offset>.from(pts);
    for (int k = 0; k < iterations; k++) {
      final output = <Offset>[];
      for (int i = 0; i < current.length; i++) {
        final a = current[i];
        final b = current[(i + 1) % current.length];
        output.add(Offset(
          0.75 * a.dx + 0.25 * b.dx,
          0.75 * a.dy + 0.25 * b.dy,
        ));
        output.add(Offset(
          0.25 * a.dx + 0.75 * b.dx,
          0.25 * a.dy + 0.75 * b.dy,
        ));
      }
      current = output;
    }
    return current;
  }

  // Shift polygon by a fraction of its width/height to fine‑tune placement.
  List<Offset> _nudge(List<Offset> pts,
      {double dxFrac = 0.0, double dyFrac = 0.0}) {
    if (pts.isEmpty) return pts;
    double minX = pts.first.dx, maxX = pts.first.dx;
    double minY = pts.first.dy, maxY = pts.first.dy;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final width = (maxX - minX).abs();
    final height = (maxY - minY).abs();
    final dx = width * dxFrac;
    final dy = height * dyFrac;
    return pts
        .map((p) => Offset(p.dx + dx, p.dy + dy))
        .toList(growable: false);
  }

  // Scale polygon around its centroid.
  List<Offset> _scale(List<Offset> pts,
      {double scaleX = 1.0, double scaleY = 1.0}) {
    if (pts.isEmpty) return pts;
    double cx = 0, cy = 0;
    for (final p in pts) {
      cx += p.dx;
      cy += p.dy;
    }
    cx /= pts.length;
    cy /= pts.length;
    return pts
        .map((p) => Offset(
              cx + (p.dx - cx) * scaleX,
              cy + (p.dy - cy) * scaleY,
            ))
        .toList(growable: false);
  }

  @override
  bool shouldRepaint(covariant RealisticLipstickPainter oldDelegate) {
    return oldDelegate.lipRegion != lipRegion ||
        oldDelegate.shade != shade ||
        oldDelegate.intensity != intensity ||
        oldDelegate.previewRectOnScreen != previewRectOnScreen ||
        oldDelegate.isFrontFacing != isFrontFacing ||
        oldDelegate.showLandmarks != showLandmarks ||
        oldDelegate.innerLipPoints != innerLipPoints ||
        oldDelegate.offsetDXFraction != offsetDXFraction ||
        oldDelegate.offsetDYFraction != offsetDYFraction ||
        oldDelegate.scaleX != scaleX ||
        oldDelegate.scaleY != scaleY;
  }
}
