// Common stub types for iOS compatibility (ML Kit not available)
import 'dart:ui';

/// Stub class for face mesh lip results
class FaceMeshLipResult {
  final List<Offset> upperLipPoints;
  final List<Offset> lowerLipPoints;
  final Rect bounds;
  final bool mirrored;

  FaceMeshLipResult({
    required this.upperLipPoints,
    required this.lowerLipPoints,
    required this.bounds,
    this.mirrored = false,
  });

  // Compatibility getters
  List<LipLandmark> get outerLip => upperLipPoints.map((p) => LipLandmark(x: p.dx, y: p.dy, index: 0)).toList();
  List<LipLandmark> get innerLip => lowerLipPoints.map((p) => LipLandmark(x: p.dx, y: p.dy, index: 0)).toList();
}

/// Stub class for face bounds
class FaceBounds {
  final Rect bounds;
  final double confidence;

  FaceBounds({
    required this.bounds,
    this.confidence = 1.0,
  });

  // Compatibility getters
  double get left => bounds.left;
  double get top => bounds.top;
  double get width => bounds.width;
  double get height => bounds.height;
}

/// Stub class for lip landmarks
class LipLandmark {
  final double x;
  final double y;
  final int index;

  LipLandmark({
    required this.x,
    required this.y,
    required this.index,
  });
}
