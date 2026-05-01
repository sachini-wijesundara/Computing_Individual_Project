import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// MediaPipe hand fingertips from a saved image (Android / iOS native).
class HandNailTip {
  final double nx;
  final double ny;
  final double r;
  final double angle;

  const HandNailTip({
    required this.nx,
    required this.ny,
    required this.r,
    required this.angle,
  });
}

class HandLandmarkerPlatform {
  static const _channel = MethodChannel('la_vogue_vista/hand_landmarker');

  static Future<List<HandNailTip>> detectTips(String imagePath) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return const [];
    }
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('detectTips', {
        'path': imagePath,
      });
      if (raw == null || raw.isEmpty) return const [];
      final out = <HandNailTip>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        out.add(
          HandNailTip(
            nx: (m['nx'] as num?)?.toDouble() ?? 0,
            ny: (m['ny'] as num?)?.toDouble() ?? 0,
            r: (m['r'] as num?)?.toDouble() ?? 0.04,
            angle: (m['angle'] as num?)?.toDouble() ?? 0,
          ),
        );
      }
      return out;
    } catch (e, st) {
      debugPrint('HandLandmarkerPlatform.detectTips: $e\n$st');
      return const [];
    }
  }
}
