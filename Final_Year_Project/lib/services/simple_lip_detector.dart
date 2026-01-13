// Stub for iOS - ML Kit not available, using native renderer
import 'dart:ui';
import 'package:camera/camera.dart';

class SimpleLipDetector {
  Future<LipRegion?> detectLips(CameraImage image, {int rotation = 0}) async {
    // iOS uses native MediaPipe renderer, this is not called
    return null;
  }

  // Stub method for compatibility - matches actual usage signature
  Future<LipRegion?> detectLipsFromYuv(
    CameraImage image,
    {int? rotationDegrees, bool? frontCamera}
  ) async {
    return null;
  }

  void dispose() {}
}

class LipRegion {
  final List<Offset> outerPoints;
  final List<Offset>? innerPoints;
  final Rect bounds;
  final Size imageSize;

  LipRegion({
    required this.outerPoints,
    this.innerPoints,
    required this.bounds,
    Size? imageSize,
  }) : imageSize = imageSize ?? const Size(1920, 1080);

  // Compatibility getter for code expecting 'points'
  List<Offset> get points => outerPoints;
}
