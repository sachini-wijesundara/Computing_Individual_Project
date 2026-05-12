import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SelfieCaptureScreen extends StatefulWidget {
  const SelfieCaptureScreen({super.key, required this.imagePath});
  final String imagePath;

  static Future<void> _captureQueue = Future<void>.value();

  /// Opens the front camera, then review (use / retake). Requests are queued so
  /// two picks never run at once (avoids iOS `multiple_request` from `image_picker`).
  static Future<String?> capture(BuildContext context) {
    final result = Completer<String?>();
    _captureQueue = _captureQueue.then((_) async {
      try {
        result.complete(await _captureWithReview(context));
      } catch (e, s) {
        if (!result.isCompleted) result.completeError(e, s);
      }
    });
    return result.future;
  }

  static Future<String?> _captureWithReview(BuildContext context) async {
    final picker = ImagePicker();
    final nav = Navigator.of(context);
    while (true) {
      XFile? f;
      for (var attempt = 0; attempt < 6; attempt++) {
        try {
          f = await picker.pickImage(
            source: ImageSource.camera,
            imageQuality: 100,
            preferredCameraDevice: CameraDevice.front,
          );
          break;
        } on PlatformException catch (e) {
          if (e.code != 'multiple_request') rethrow;
          if (attempt == 5) return null;
          await Future<void>.delayed(Duration(milliseconds: 200 + 150 * attempt));
        }
      }
      if (f == null) return null; // user cancelled or exhausted retries

      final persisted = await _persistCapturedPath(f.path);
      if (!context.mounted) return null;
      final action = await nav.push<_ReviewAction>(
        MaterialPageRoute(
          builder: (_) => SelfieCaptureScreen(imagePath: persisted),
        ),
      );
      if (action == _ReviewAction.usePhoto) return persisted;
      if (action == _ReviewAction.retake) continue;
      return null;
    }
  }

  static Future<String> _persistCapturedPath(String originalPath) async {
    final src = File(originalPath);
    if (!await src.exists()) return originalPath;
    final dir = await getTemporaryDirectory();
    final ext = p.extension(originalPath).isEmpty ? '.jpg' : p.extension(originalPath);
    final targetPath = p.join(
      dir.path,
      'selfie_${DateTime.now().millisecondsSinceEpoch}$ext',
    );
    final copied = await src.copy(targetPath);
    return copied.path;
  }

  @override
  State<SelfieCaptureScreen> createState() => _SelfieCaptureScreenState();
}

enum _ReviewAction { retake, usePhoto }

class _SelfieCaptureScreenState extends State<SelfieCaptureScreen> {
  final bool _mirror = true;

  @override
  Widget build(BuildContext context) {
    final image = Image.file(File(widget.imagePath), fit: BoxFit.cover);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Review your selfie'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _mirrorIfNeeded(image),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(_ReviewAction.retake),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                          minimumSize: const Size(0, 48),
                        ),
                        child: const Text('Retake photo'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(_ReviewAction.usePhoto),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(0, 48),
                        ),
                        child: const Text('Use photo'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mirrorIfNeeded(Widget child) {
    if (!_mirror) return child;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
      child: child,
    );
  }
}

