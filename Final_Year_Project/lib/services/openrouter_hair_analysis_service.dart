import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../config/app_secrets.dart';

/// Result of OpenRouter vision + JSON hair analysis.
class OpenRouterHairAnalysisResult {
  final String? faceShape;
  final String? hairType;
  final String? hairLength;
  final List<({String style, String reason})> recommendations;
  final String? errorMessage;

  const OpenRouterHairAnalysisResult({
    this.faceShape,
    this.hairType,
    this.hairLength,
    this.recommendations = const [],
    this.errorMessage,
  });

  factory OpenRouterHairAnalysisResult.error(String msg) =>
      OpenRouterHairAnalysisResult(errorMessage: msg);
}

/// Calls [OpenRouter](https://openrouter.ai/) chat completions with a vision model.
class OpenRouterHairAnalysisService {
  OpenRouterHairAnalysisService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _endpoint = 'https://openrouter.ai/api/v1/chat/completions';

  /// Normalized key (trim, strip quotes, strip accidental `Bearer `). Use for UI + requests.
  static String get apiKey => _normalizeOpenRouterKey(AppSecrets.openRouterApiKey);

  /// Optional override, e.g. `openai/gpt-4o-mini`
  static String get model =>
      AppSecrets.openRouterModel.replaceAll('\r', '').trim();

  static String _normalizeOpenRouterKey(String raw) {
    var k = raw.replaceAll('\r', '').replaceAll('\n', '').trim();
    if (k.length >= 2) {
      final dq = k.startsWith('"') && k.endsWith('"');
      final sq = k.startsWith("'") && k.endsWith("'");
      if (dq || sq) k = k.substring(1, k.length - 1).trim();
    }
    const bearer = 'bearer ';
    if (k.toLowerCase().startsWith(bearer)) {
      k = k.substring(bearer.length).trim();
    }
    return k;
  }

  static String? _openRouterJsonMessage(String body) {
    try {
      final m = json.decode(body);
      if (m is Map) {
        final err = m['error'];
        if (err is Map && err['message'] is String) return err['message'] as String;
      }
    } catch (_) {}
    return null;
  }

  static const int _maxVisionSide = 1600;

  static img.Image _maybeDownscale(img.Image src) {
    final w = src.width;
    final h = src.height;
    final m = math.max(w, h);
    if (m <= _maxVisionSide) return src;
    final scale = _maxVisionSide / m;
    return img.copyResize(
      src,
      width: (w * scale).round(),
      height: (h * scale).round(),
    );
  }

  /// Decodes gallery picks (JPEG, PNG, WebP, **HEIC on iOS**, etc.) and returns JPEG bytes for the API.
  static Future<Uint8List?> normalizeToJpegAsync(List<int> raw) async {
    final u8 = raw is Uint8List ? raw : Uint8List.fromList(raw);
    var decoded = img.decodeImage(u8);
    if (decoded != null) {
      return Uint8List.fromList(img.encodeJpg(_maybeDownscale(decoded), quality: 85));
    }
    if (u8.length > 3 && u8[0] == 0xFF && u8[1] == 0xD8 && u8[2] == 0xFF) {
      return u8;
    }
    try {
      final codec = await ui.instantiateImageCodec(
        u8,
        targetWidth: _maxVisionSide,
        targetHeight: _maxVisionSide,
      );
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;
      final bd = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      uiImage.dispose();
      if (bd == null) return null;
      decoded = img.decodeImage(bd.buffer.asUint8List());
      if (decoded == null) return null;
      return Uint8List.fromList(img.encodeJpg(_maybeDownscale(decoded), quality: 85));
    } catch (_) {
      return null;
    }
  }

  static String? extractJsonObject(String raw) {
    var s = raw.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', multiLine: true);
    final m = fence.firstMatch(s);
    if (m != null) s = m.group(1)!.trim();

    final start = s.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    for (var i = start; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x7B) depth++;
      if (c == 0x7D) {
        depth--;
        if (depth == 0) return s.substring(start, i + 1);
      }
    }
    return null;
  }

  Future<OpenRouterHairAnalysisResult> analyzeHairPhoto({
    required List<int> jpegBytes,
    required String catalogStyleNames,
  }) async {
    if (apiKey.isEmpty) {
      return OpenRouterHairAnalysisResult.error(
        'Missing OpenRouter API key.\n\n'
        'Add OPENROUTER_API_KEY to your project `.env` (see `.env.example`) or run:\n'
        'flutter run --dart-define=OPENROUTER_API_KEY=sk-or-v1-YOUR_KEY\n\n'
        'You must fully restart the app (./ios_quick_run.sh) after editing `.env` — '
        'hot reload and `flutter attach` do not update compile-time keys.\n\n'
        'Optional: OPENROUTER_MODEL=openai/gpt-4o-mini',
      );
    }

    final normalized = await normalizeToJpegAsync(jpegBytes);
    if (normalized == null || normalized.isEmpty || img.decodeImage(normalized) == null) {
      return OpenRouterHairAnalysisResult.error(
        'Could not read this image. On iPhone, try a photo taken as “Most Compatible” (JPEG) '
        'or pick an image that opens in Photos; HEIC is supported on device but some formats may fail.',
      );
    }

    final b64 = base64Encode(normalized);
    final prompt = '''
You are a hair stylist assistant. Look at this photo.

1) Estimate face shape (one of: Oval, Round, Square, Heart, Oblong, Diamond, or best short label).
2) Estimate current hair type: straight, wavy, curly, or coily.
3) Estimate current hair length: short, medium, or long.
4) Pick exactly 3 best matching styles from this list ONLY (use exact names):
$catalogStyleNames

Return a single JSON object with keys:
face_shape (string), hair_type (string), hair_length (string),
recommendations (array of exactly 3 objects, each with "style" and "reason" strings).
No other keys. No markdown.''';

    final body = <String, dynamic>{
      'model': model,
      'temperature': 0.35,
      'max_tokens': 2048,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/jpeg;base64,$b64',
              },
            },
          ],
        },
      ],
    };

    try {
      final res = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
              'HTTP-Referer': 'https://github.com/la-vogue-vista',
              'X-Title': 'La Vogue Vista Hair Analysis',
            },
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 60));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        final apiMsg = _openRouterJsonMessage(res.body);
        if (res.statusCode == 401) {
          return OpenRouterHairAnalysisResult.error(
            'OpenRouter rejected your API key (401${apiMsg != null ? ': $apiMsg' : ''}).\n\n'
            'Usually this means the key is wrong, expired, or copied with extra characters.\n\n'
            'Fix:\n'
            '• Create a new key at https://openrouter.ai/keys\n'
            '• In `.env` use exactly: OPENROUTER_API_KEY=sk-or-v1-… (no quotes, no "Bearer ")\n'
            '• Fully restart the app after editing `.env` (not hot reload)\n\n'
            'If you use Xcode, add the same value under Run → Arguments → --dart-define.',
          );
        }
        final tail = res.body.length > 400 ? '${res.body.substring(0, 400)}…' : res.body;
        return OpenRouterHairAnalysisResult.error(
          apiMsg != null
              ? 'OpenRouter HTTP ${res.statusCode}: $apiMsg'
              : 'OpenRouter HTTP ${res.statusCode}: $tail',
        );
      }

      final map = json.decode(res.body) as Map<String, dynamic>;
      final choices = map['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        return OpenRouterHairAnalysisResult.error('No response choices from OpenRouter.');
      }
      final first = choices.first;
      if (first is! Map) {
        return OpenRouterHairAnalysisResult.error('Unexpected OpenRouter response shape.');
      }
      final msg = Map<String, dynamic>.from(first);
      final messageRaw = msg['message'];
      final message =
          messageRaw is Map ? Map<String, dynamic>.from(messageRaw) : null;
      String? text;
      if (message != null) {
        final c = message['content'];
        if (c is String) {
          text = c;
        } else if (c is List) {
          final buf = StringBuffer();
          for (final part in c) {
            if (part is Map && part['type'] == 'text' && part['text'] is String) {
              buf.write(part['text']);
            }
          }
          text = buf.toString();
        }
      }
      text = text?.trim();
      if (text == null || text.isEmpty) {
        return OpenRouterHairAnalysisResult.error('Empty model reply.');
      }

      final jsonStr = extractJsonObject(text);
      if (jsonStr == null) {
        return OpenRouterHairAnalysisResult.error(
          'Could not parse JSON from model.\n${text.length > 500 ? '${text.substring(0, 500)}…' : text}',
        );
      }

      final data = json.decode(jsonStr) as Map<String, dynamic>;
      final recList = <({String style, String reason})>[];
      final rawRecs = data['recommendations'] ?? data['styles'] ?? data['suggested_styles'];
      if (rawRecs is List) {
        for (final r in rawRecs) {
          if (r is String) {
            final s = r.trim();
            if (s.isNotEmpty) recList.add((style: s, reason: ''));
          } else if (r is Map) {
            final m = Map<String, dynamic>.from(r);
            final style = _str(m['style'] ?? m['name'] ?? m['hairstyle']) ?? '';
            final reason = _str(m['reason'] ?? m['why'] ?? m['explanation']) ?? '';
            if (style.isNotEmpty) {
              recList.add((style: style, reason: reason));
            }
          }
        }
      }

      return OpenRouterHairAnalysisResult(
        faceShape: _str(data['face_shape'] ?? data['faceShape']),
        hairType: _str(data['hair_type'] ?? data['hairType']),
        hairLength: _str(data['hair_length'] ?? data['hairLength']),
        recommendations: recList,
        errorMessage: recList.isEmpty ? 'No recommendations in JSON.' : null,
      );
    } catch (e) {
      return OpenRouterHairAnalysisResult.error('$e');
    }
  }

  static String? _str(dynamic v) {
    final s = '$v'.trim();
    if (s.isEmpty || s == 'null') return null;
    return s;
  }

  void dispose() => _client.close();
}
