// Stub for iOS - ML Kit not available, using native renderer
import 'dart:ui';
import 'package:camera/camera.dart';

class MLKitFaceMeshService {
  Future<void> initialize() async {
    // iOS uses native MediaPipe renderer, this is not called
  }

  Future<List<Offset>?> getLipLandmarks(CameraImage image, {int rotation = 0}) async {
    // iOS uses native MediaPipe renderer, this is not called
    return null;
  }

  void dispose() {}
}
