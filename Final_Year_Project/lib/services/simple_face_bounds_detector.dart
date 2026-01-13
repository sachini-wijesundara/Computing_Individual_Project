// Stub for iOS - ML Kit not available, using native renderer
import 'dart:ui';
import 'package:camera/camera.dart';

class SimpleFaceBoundsDetector {
  Future<Rect?> detectFaceBounds(CameraImage image, {int rotation = 0}) async {
    // iOS uses native MediaPipe renderer, this is not called
    return null;
  }

  void dispose() {}
}
