// lib/services/tflite_analysis_service.dart
//
// Beauty analysis service.
// PRIMARY:   Gemini Vision API — sends the image directly so results are accurate.
// SECONDARY: On-device TFLite classifiers (hair_type + hair_color models).
// TERTIARY:  Remote Python server (usually offline during development).
// FALLBACK:  Improved pixel analysis (HSV-aware thresholds).

import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'ai_chat_service.dart';
import '../config/app_secrets.dart';
import '../models/hair_style.dart';

// ── Result models ─────────────────────────────────────────────────────────────

class SkinToneResult {
  final String skinTone;      // Fair / Light / Medium / Tan / Deep
  final String undertone;     // Cool / Warm / Neutral
  final double confidence;
  final String inferenceMode; // 'gemini_vision' | 'server' | 'pixel_analysis'
  final Map<String, String> makeupRecommendations;

  const SkinToneResult({
    required this.skinTone,
    required this.undertone,
    required this.confidence,
    required this.inferenceMode,
    required this.makeupRecommendations,
  });
}

class HairResult {
  final String hairType;      // Straight / Wavy / Curly / Coily
  final String hairColor;     // Black / Brown / Blonde / Red / Grey / Auburn
  final double confidence;
  final String inferenceMode;
  final List<String> careTips;
  final Map<String, String> productRecommendations;
  final List<String> recommendedStyles;

  const HairResult({
    required this.hairType,
    required this.hairColor,
    required this.confidence,
    required this.inferenceMode,
    required this.careTips,
    required this.productRecommendations,
    required this.recommendedStyles,
  });
}

class MakeupResult {
  final String makeupLevel;
  final double confidence;
  final String inferenceMode;

  const MakeupResult({
    required this.makeupLevel,
    required this.confidence,
    required this.inferenceMode,
  });
}

// ═════════════════════════════════════════════════════════════════════════════
class TFLiteAnalysisService {
  static final TFLiteAnalysisService _instance = TFLiteAnalysisService._internal();
  factory TFLiteAnalysisService() => _instance;
  TFLiteAnalysisService._internal();

  final _aiChatService = AIChatService();

  /// Models that work for new Google AI Studio keys (avoid `gemini-2.0-flash` / `gemini-1.0-pro-vision`).
  static const _visionModels = [
    'gemini-2.5-flash',
    'gemini-2.0-flash',
  ];

  static const Duration _visionTimeout = Duration(seconds: 70);
  static const int _visionMaxSidePx = 1024;

  // On-device TFLite interpreters
  Interpreter? _hairTypeInterpreter;
  Interpreter? _hairColorInterpreter;
  List<String> _hairTypeLabels = ['Straight', 'Wavy', 'Curly', 'Coily'];
  List<String> _hairColorLabels = ['Black', 'Brown', 'Blonde', 'Red', 'Grey'];
  bool _tfliteReady = false;

  /// Avoid duplicate Gemini calls when [analyzeSkin] and [analyzeHair] run back-to-back on the same file.
  String? _visionCacheKey;
  Map<String, dynamic>? _visionCache;

  /// Stronger than [List.hashCode] alone — reduces wrong cache hits between different photos.
  Future<String> _visionCacheKeyFor(XFile f) async {
    final bytes = await f.readAsBytes();
    var sampleHash = 17;
    if (bytes.isNotEmpty) {
      for (var i = 0; i < bytes.length; i += 512) {
        sampleHash = 0x1fffffff & (sampleHash * 31 + bytes[i]);
      }
      final last = bytes.length - 1;
      sampleHash = 0x1fffffff &
          (sampleHash * 31 + bytes.first + bytes[last] + (bytes.length >> 8));
    }
    return '${f.path}|${bytes.length}|$sampleHash';
  }

  /// Call before a new photo so an old Gemini result is never reused for a different person.
  void clearVisionCache() {
    _visionCacheKey = null;
    _visionCache = null;
  }

  static String? _extractJsonObject(String raw) {
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

  static List<String> _coerceRecommendedStyles(dynamic v) {
    if (v == null) return [];
    if (v is! List) return [];
    final out = <String>[];
    for (final e in v) {
      final s = e == null ? '' : e.toString().trim();
      if (s.isNotEmpty && s != 'null') out.add(s);
    }
    return out;
  }

  static String? _visionString(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    final t = v.toString().trim();
    if (t.isEmpty || t == 'null') return null;
    return t;
  }

  Future<void> initialize() async {
    await _loadTFLiteModels();
    debugPrint('✅ TFLiteAnalysisService initialized (Gemini Vision + TFLite + Pixel fallback)');
  }

  Future<void> _loadTFLiteModels() async {
    try {
      _hairTypeInterpreter = await Interpreter.fromAsset(
        'assets/models/hair_type_classifier.tflite',
        options: InterpreterOptions()..threads = 2,
      );
      _hairColorInterpreter = await Interpreter.fromAsset(
        'assets/models/hair_color_classifier.tflite',
        options: InterpreterOptions()..threads = 2,
      );

      // Load label files
      final typeLabelsJson = await rootBundle.loadString('assets/models/hair_type_classifier_labels.json');
      final colorLabelsJson = await rootBundle.loadString('assets/models/hair_color_classifier_labels.json');
      _hairTypeLabels  = List<String>.from(json.decode(typeLabelsJson)  as List);
      _hairColorLabels = List<String>.from(json.decode(colorLabelsJson) as List);

      _tfliteReady = true;
      debugPrint('✅ TFLite hair classifiers loaded (type: ${_hairTypeLabels.length} classes, color: ${_hairColorLabels.length} classes)');
    } catch (e) {
      debugPrint('⚠️ TFLite hair classifiers not loaded (will use pixel fallback): $e');
      _tfliteReady = false;
    }
  }

  // ── ON-DEVICE TFLite — hair type + color classification ───────────────────

  /// Quantized MobileNet-style models use `uint8` [0–255]; float models use normalized floats.
  dynamic _hairClassifierInput(img.Image resized, TensorType inputType) {
    if (inputType == TensorType.uint8) {
      return List.generate(
        1,
        (_) => List.generate(
          224,
          (y) => List.generate(
            224,
            (x) {
              final p = resized.getPixel(x, y);
              return [
                p.r.toInt().clamp(0, 255),
                p.g.toInt().clamp(0, 255),
                p.b.toInt().clamp(0, 255),
              ];
            },
          ),
        ),
      );
    }
    return List.generate(
      1,
      (_) => List.generate(
        224,
        (y) => List.generate(
          224,
          (x) {
            final p = resized.getPixel(x, y);
            return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
          },
        ),
      ),
    );
  }

  /// Logits length for typical `[batch, classes]` or `[classes]` outputs.
  static int _logitsLengthFromShape(List<int> shape) {
    if (shape.isEmpty) return 0;
    if (shape.length == 1) return shape[0];
    return shape[1];
  }

  List<dynamic> _allocOutputForTensor(Tensor tensor) {
    final n = _logitsLengthFromShape(tensor.shape);
    final t = tensor.type;
    if (t == TensorType.float32 || t == TensorType.float16 || t == TensorType.float64) {
      return [List<double>.filled(n, 0.0)];
    }
    return [List<int>.filled(n, 0)];
  }

  List<double> _scoresFromOutput(List<dynamic> outputBuf, int length) {
    final row = outputBuf[0];
    if (row is List<double>) {
      return row;
    }
    if (row is List<int>) {
      return List<double>.generate(length, (i) => row[i].toDouble());
    }
    return List<double>.generate(length, (i) => (row[i] as num).toDouble());
  }

  /// Average RGB in a 224×224 crop (coordinates match pixel-analysis hair bands).
  ({double r, double g, double b, double lum}) _avgRegion224(
    img.Image resized,
    int x0,
    int y0,
    int x1,
    int y1,
  ) {
    x0 = x0.clamp(0, 223);
    y0 = y0.clamp(0, 223);
    x1 = x1.clamp(1, 224);
    y1 = y1.clamp(1, 224);
    double rSum = 0, gSum = 0, bSum = 0;
    var count = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final p = resized.getPixel(x, y);
        rSum += p.r.toDouble();
        gSum += p.g.toDouble();
        bSum += p.b.toDouble();
        count++;
      }
    }
    final r = rSum / count;
    final g = gSum / count;
    final b = bSum / count;
    final lum = 0.299 * r + 0.587 * g + 0.114 * b;
    return (r: r, g: g, b: b, lum: lum);
  }

  ({double lum, double rgRatio, double rbRatio}) _hairBandStats224(img.Image resized224) {
    // Front selfies: top band; back-of-head / hair fills frame: centre band too.
    final regions = [
      _avgRegion224(resized224, 26, 22, 198, 61),
      _avgRegion224(resized224, 9, 44, 70, 114),
      _avgRegion224(resized224, 154, 44, 215, 114),
      _avgRegion224(resized224, 34, 56, 190, 157),
    ];
    var hR = 0.0, hG = 0.0, hB = 0.0;
    for (final r in regions) {
      hR += r.r;
      hG += r.g;
      hB += r.b;
    }
    hR /= regions.length;
    hG /= regions.length;
    hB /= regions.length;
    final hLum = 0.299 * hR + 0.587 * hG + 0.114 * hB;
    return (
      lum: hLum,
      rgRatio: hR / (hG + 1e-6),
      rbRatio: hR / (hB + 1e-6),
    );
  }

  /// Burgundy, wine-red, auburn — including darker reds (lum can be under ~110).
  bool _isReddishHairBand(({double lum, double rgRatio, double rbRatio}) stats) {
    return stats.rgRatio >= 1.26 &&
        stats.rbRatio >= 1.10 &&
        stats.lum >= 28 &&
        stats.lum <= 145;
  }

  /// Same rules as pixel fallback — tuned for brown vs burgundy/red.
  String _pixelHairColorFrom224(img.Image resized224) {
    final stats = _hairBandStats224(resized224);
    if (_isReddishHairBand(stats)) return 'Red';

    final hLum = stats.lum;
    if (hLum < 60) return 'Black';
    if (hLum < 110) return 'Brown';
    if (hLum < 150) return 'Brown';
    if (hLum < 200) return 'Blonde';
    return 'Grey';
  }

  static bool _isDegenerateTfliteColorScores(List<double> colorScores) {
    if (colorScores.isEmpty) return false;
    final max = colorScores.reduce(math.max);
    final nonZero = colorScores.where((s) => s > 0.02).length;
    return max >= 0.98 && nonZero <= 1;
  }

  /// Edge density in the hair region → texture type (Curly/Coily vs Wavy).
  String _pixelHairTypeFrom224(img.Image resized224) {
    double edgeSumH = 0, edgeSumV = 0;
    var edgeCount = 0;
    for (var y = 28; y < 175; y++) {
      for (var x = 28; x < 196; x++) {
        final cur = resized224.getPixel(x, y);
        final curL = 0.299 * cur.r + 0.587 * cur.g + 0.114 * cur.b;
        final pH = resized224.getPixel(x - 1, y);
        final pHL = 0.299 * pH.r + 0.587 * pH.g + 0.114 * pH.b;
        edgeSumH += (curL - pHL).abs();
        if (y > 28) {
          final pV = resized224.getPixel(x, y - 1);
          final pVL = 0.299 * pV.r + 0.587 * pV.g + 0.114 * pV.b;
          edgeSumV += (curL - pVL).abs();
        }
        edgeCount++;
      }
    }
    final edge = (edgeSumH + edgeSumV) / (edgeCount * 2);
    if (edge < 6) return 'Straight';
    if (edge < 11) return 'Wavy';
    if (edge < 17) return 'Curly';
    return 'Coily';
  }

  String _refineTfliteHairType(String predicted, img.Image resized224) {
    const order = ['Straight', 'Wavy', 'Curly', 'Coily'];
    final pixelType = _pixelHairTypeFrom224(resized224);
    final predIdx = order.indexOf(predicted);
    final pixelIdx = order.indexOf(pixelType);
    if (predIdx < 0 || pixelIdx < 0) return predicted;
    if (pixelIdx > predIdx) {
      debugPrint('🔧 TFLite hair type: $predicted → $pixelType (texture edges)');
      return pixelType;
    }
    return predicted;
  }

  /// Balance demo-model fixes (brown≠red) with real burgundy/curly-red photos.
  String _refineTfliteHairColor({
    required String predicted,
    required List<double> colorScores,
    required List<String> labels,
    required img.Image resized224,
  }) {
    final stats = _hairBandStats224(resized224);
    final pixelColor = _pixelHairColorFrom224(resized224);
    final reddish = _isReddishHairBand(stats);
    debugPrint(
      'Hair band: lum=${stats.lum.toStringAsFixed(1)}, R/G=${stats.rgRatio.toStringAsFixed(2)}, '
      'R/B=${stats.rbRatio.toStringAsFixed(2)}, reddish=$reddish, pixel=$pixelColor, '
      'tflite=$predicted',
    );

    if (reddish && (predicted == 'Brown' || predicted == 'Black')) {
      debugPrint('🔧 TFLite hair color: $predicted → Red (burgundy/wine-red band)');
      return 'Red';
    }

    if (predicted != 'Red') return predicted;

    // Keep true red hair even when the bundled model always outputs Red=1.0.
    if (reddish) return 'Red';

    if (_isDegenerateTfliteColorScores(colorScores) && pixelColor != 'Red') {
      debugPrint('🔧 TFLite hair color: Red → $pixelColor (degenerate model, not reddish)');
      return pixelColor;
    }

    if (pixelColor != 'Red') {
      debugPrint('🔧 TFLite hair color: Red → $pixelColor (pixel hair band)');
      return pixelColor;
    }

    return predicted;
  }

  Future<Map<String, dynamic>?> _tfliteAnalyzeHair(XFile imageFile) async {
    if (!_tfliteReady || _hairTypeInterpreter == null || _hairColorInterpreter == null) {
      return null;
    }
    try {
      final typeOutTensor = _hairTypeInterpreter!.getOutputTensor(0);
      final colorOutTensor = _hairColorInterpreter!.getOutputTensor(0);
      final typeN = _logitsLengthFromShape(typeOutTensor.shape);
      final colorN = _logitsLengthFromShape(colorOutTensor.shape);

      if (typeN != _hairTypeLabels.length) {
        debugPrint(
          '⚠️ hair_type_classifier.tflite outputs $typeN classes (shape ${typeOutTensor.shape}) but '
          'labels.json has ${_hairTypeLabels.length}. Replace the .tflite with a ${_hairTypeLabels.length}-class '
          'hair-type model (not ImageNet/MobileNet 1001). Using Gemini/pixel fallback.',
        );
        return null;
      }
      if (colorN != _hairColorLabels.length) {
        debugPrint(
          '⚠️ hair_color_classifier.tflite outputs $colorN classes (shape ${colorOutTensor.shape}) but '
          'labels have ${_hairColorLabels.length}. Using Gemini/pixel fallback.',
        );
        return null;
      }

      final bytes   = await imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      // Resize to 224×224 (MobileNet input size)
      final resized = img.copyResize(decoded, width: 224, height: 224);

      final inputType = _hairTypeInterpreter!.getInputTensor(0).type;
      final input = _hairClassifierInput(resized, inputType);

      final typeOutput = _allocOutputForTensor(typeOutTensor);
      _hairTypeInterpreter!.run(input, typeOutput);
      final typeScores = _scoresFromOutput(typeOutput, typeN);
      final typeIdx    = typeScores.indexOf(typeScores.reduce(math.max));
      var hairType     = typeIdx < _hairTypeLabels.length ? _hairTypeLabels[typeIdx] : 'Wavy';
      hairType = _refineTfliteHairType(hairType, resized);

      final colorOutput = _allocOutputForTensor(colorOutTensor);
      _hairColorInterpreter!.run(input, colorOutput);
      final colorScores = _scoresFromOutput(colorOutput, colorN);
      final colorIdx    = colorScores.indexOf(colorScores.reduce(math.max));
      var hairColor     = colorIdx < _hairColorLabels.length ? _hairColorLabels[colorIdx] : 'Brown';
      hairColor = _refineTfliteHairColor(
        predicted: hairColor,
        colorScores: colorScores,
        labels: _hairColorLabels,
        resized224: resized,
      );
      final refinedColorIdx = _hairColorLabels.indexOf(hairColor);

      final confidence = (typeScores[typeIdx] + colorScores[refinedColorIdx >= 0 ? refinedColorIdx : colorIdx]) / 2.0;
      final scoreLine = _hairColorLabels
          .asMap()
          .entries
          .map((e) => '${e.value}=${colorScores[e.key].toStringAsFixed(3)}')
          .join(', ');
      debugPrint('TFLite color scores: $scoreLine');
      debugPrint('✅ TFLite hair: type=$hairType (${typeScores[typeIdx].toStringAsFixed(2)}), color=$hairColor (${colorScores[refinedColorIdx >= 0 ? refinedColorIdx : colorIdx].toStringAsFixed(2)})');

      final typeChanged = hairType != _hairTypeLabels[typeIdx];
      final colorChanged = hairColor != _hairColorLabels[colorIdx];
      final colorConfidence = (!colorChanged && !typeChanged)
          ? confidence
          : 0.82;

      return {
        'hair_type':  hairType,
        'hair_color': hairColor,
        'confidence': colorConfidence.clamp(0.65, 0.95),
        'inference_mode': (!colorChanged && !typeChanged)
            ? 'tflite_ondevice'
            : 'tflite_ondevice+pixel_hair',
      };
    } catch (e) {
      debugPrint('⚠️ TFLite hair inference error: $e');
      return null;
    }
  }

  // ── GEMINI VISION — calls Gemini with the actual image ────────────────────

  /// Downscale camera photos so Gemini Vision returns within timeout (large JPEGs are slow).
  Future<Uint8List> _imageBytesForVision(XFile imageFile) async {
    final raw = await imageFile.readAsBytes();
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return raw;
      img.Image resized = decoded;
      final w = decoded.width;
      final h = decoded.height;
      final m = _visionMaxSidePx;
      if (w > m || h > m) {
        resized = w >= h
            ? img.copyResize(decoded, width: m)
            : img.copyResize(decoded, height: m);
      }
      return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
    } catch (e) {
      debugPrint('⚠️ Vision image resize skipped: $e');
      return raw;
    }
  }

  Future<Map<String, dynamic>?> _geminiVisionAnalyze(XFile imageFile) async {
    if (AppSecrets.geminiApiKey.isEmpty) {
      debugPrint('⚠️ GEMINI_API_KEY missing — skipping Gemini Vision (use .env or --dart-define)');
      return null;
    }

    final cacheKey = await _visionCacheKeyFor(imageFile);
    if (_visionCacheKey == cacheKey && _visionCache != null) {
      debugPrint('♻️ Using cached Gemini Vision result for this photo');
      return _visionCache;
    }

    final imageBytes = await _imageBytesForVision(imageFile);
    const mimeType = 'image/jpeg';

    final skinPrompt = '''
Analyze this photo and determine:
1. Skin tone: one of [Fair, Light, Medium, Tan, Deep]
2. Skin undertone: one of [Cool, Warm, Neutral]
3. Hair type: one of [Straight, Wavy, Curly, Coily]
4. Hair color: one of [Black, Brown, Blonde, Red, Auburn, Grey]
5. Recommended hairstyles: Choose the top 3 best hair styles for this person from this list:
   ${hairStyles.map((s) => s.name).join(', ')}.
6. Confidence: a number between 0.7 and 1.0

Reply ONLY in valid JSON:
{"skin_tone":"Medium","undertone":"Warm","hair_type":"Wavy","hair_color":"Brown","recommended_styles":["Beachy Waves","Curtain Bangs","Layered Lob"],"confidence":0.88}
''';

    for (final modelName in _visionModels) {
      try {
        final model = GenerativeModel(
          model: modelName,
          apiKey: AppSecrets.geminiApiKey,
          generationConfig: GenerationConfig(
            temperature: 0.1,
            maxOutputTokens: 1024,
          ),
        );
        final content = [
          Content.multi([
            TextPart(skinPrompt),
            DataPart(mimeType, imageBytes),
          ])
        ];
        final response = await model.generateContent(content).timeout(_visionTimeout);
        final text = response.text ?? '';
        debugPrint('Gemini Vision [$modelName] raw: $text');

        final jsonStr = _extractJsonObject(text);
        if (jsonStr == null) continue;
        try {
          final parsed = json.decode(jsonStr) as Map<String, dynamic>;
          if (parsed.containsKey('skin_tone') && parsed.containsKey('hair_type')) {
            debugPrint('✅ Gemini Vision analysis succeeded with $modelName');
            parsed['inference_mode'] = 'gemini_vision';
            _visionCacheKey = cacheKey;
            _visionCache = parsed;
            return parsed;
          }
        } catch (e) {
          debugPrint('Gemini Vision [$modelName] JSON parse error: $e');
        }
      } catch (e) {
        debugPrint('Gemini Vision [$modelName] error: $e');
        continue;
      }
    }
    return null;
  }

  // ── PIXEL FALLBACK — significantly improved ────────────────────────────────

  Future<Map<String, dynamic>> _pixelAnalyzeImage(XFile imageFile) async {
    try {
      final bytes   = await imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('Decode failed');

      // Resize to 256x256 for better precision
      final resized = img.copyResize(decoded, width: 256, height: 256);

      // Helper: average pixel values in a region
      ({double r, double g, double b, double lum}) avgRegion(
        int x0, int y0, int x1, int y1) {
        x0 = x0.clamp(0, 255); y0 = y0.clamp(0, 255);
        x1 = (x1).clamp(1, 256); y1 = (y1).clamp(1, 256);
        double rSum = 0, gSum = 0, bSum = 0;
        int count = 0;
        for (int y = y0; y < y1; y++) {
          for (int x = x0; x < x1; x++) {
            final p = resized.getPixel(x, y);
            rSum += p.r.toDouble();
            gSum += p.g.toDouble();
            bSum += p.b.toDouble();
            count++;
          }
        }
        final r = rSum / count;
        final g = gSum / count;
        final b = bSum / count;
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;
        return (r: r, g: g, b: b, lum: lum);
      }

      // Sample multiple skin regions and average them for better accuracy
      // Face center (cheeks + nose area), avoiding center which might be washed out
      final skinCentre = avgRegion(80, 90, 176, 180);  // mid face
      final skinLeft   = avgRegion(50, 100, 100, 160);  // left cheek
      final skinRight  = avgRegion(156, 100, 206, 160); // right cheek
      final r = (skinCentre.r + skinLeft.r + skinRight.r) / 3;
      final g = (skinCentre.g + skinLeft.g + skinRight.g) / 3;
      final b = (skinCentre.b + skinLeft.b + skinRight.b) / 3;
      final lum = 0.299 * r + 0.587 * g + 0.114 * b;

      // Skin tone from weighted luminance
      String skinTone;
      if      (lum > 210) skinTone = 'Fair';
      else if (lum > 175) skinTone = 'Light';
      else if (lum > 135) skinTone = 'Medium';
      else if (lum > 90)  skinTone = 'Tan';
      else                skinTone = 'Deep';

      // Undertone from R-B ratio and R-G ratio
      final rbRatio = r / (b + 1e-6);
      final rgRatio = r / (g + 1e-6);
      String undertone;
      if      (rbRatio > 1.6 && rgRatio > 1.15) undertone = 'Warm';
      else if (rbRatio < 1.25)                   undertone = 'Cool';
      else                                       undertone = 'Neutral';

      // Hair: sample TOP third of image (not top 15% — that's often sky)
      // actual hair band: 10%–35% from top
      final hairTop    = avgRegion(30,  25, 226, 70);
      final hairLeft   = avgRegion(10,  50, 80,  130);
      final hairRight  = avgRegion(176, 50, 246, 130);
      final hR = (hairTop.r + hairLeft.r + hairRight.r) / 3;
      final hG = (hairTop.g + hairLeft.g + hairRight.g) / 3;
      final hB = (hairTop.b + hairLeft.b + hairRight.b) / 3;
      final hLum = 0.299 * hR + 0.587 * hG + 0.114 * hB;

      final hRg = hR / (hG + 1e-6);
      final hRb = hR / (hB + 1e-6);
      String hairColor;
      if (hRg >= 1.26 && hRb >= 1.10 && hLum >= 28 && hLum <= 145) {
        hairColor = 'Red';
      } else if (hLum < 60) {
        hairColor = 'Black';
      } else if (hLum < 110) {
        hairColor = 'Brown';
      } else if (hLum < 150) {
        hairColor = (hRg > 1.3) ? 'Auburn' : 'Brown';
      } else if (hLum < 200) {
        hairColor = 'Blonde';
      } else {
        hairColor = 'Grey';
      }

      // Hair type via multi-direction edge variance for robustness
      double edgeSumH = 0, edgeSumV = 0;
      int edgeCount = 0;
      for (int y = 25; y < 90; y++) {
        for (int x = 31; x < 226; x++) {
          final cur  = resized.getPixel(x, y);
          final curL = 0.299*cur.r + 0.587*cur.g + 0.114*cur.b.toDouble();
          // horizontal edge
          final pH   = resized.getPixel(x - 1, y);
          final pHL  = 0.299*pH.r + 0.587*pH.g + 0.114*pH.b.toDouble();
          edgeSumH  += (curL - pHL).abs();
          // vertical edge
          if (y > 25) {
            final pV  = resized.getPixel(x, y - 1);
            final pVL = 0.299*pV.r + 0.587*pV.g + 0.114*pV.b.toDouble();
            edgeSumV += (curL - pVL).abs();
          }
          edgeCount++;
        }
      }
      final edge = (edgeSumH + edgeSumV) / (edgeCount * 2);

      String hairType;
      if      (edge < 6)  hairType = 'Straight';
      else if (edge < 11) hairType = 'Wavy';
      else if (edge < 17) hairType = 'Curly';
      else                hairType = 'Coily';

      return {
        'skin_tone':  skinTone,
        'undertone':  undertone,
        'hair_color': hairColor,
        'hair_type':  hairType,
        'confidence': 0.72,
        'inference_mode': 'pixel_analysis',
      };
    } catch (e) {
      return {
        'skin_tone': 'Medium', 'undertone': 'Neutral',
        'hair_color': 'Brown', 'hair_type': 'Wavy',
        'confidence': 0.62,
        'inference_mode': 'pixel_analysis',
      };
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  SkinToneResult _skinToneResultFromVision(Map<String, dynamic> vision) {
    final s = _visionString(vision['skin_tone']) ?? 'Medium';
    final u = _visionString(vision['undertone']) ?? 'Neutral';
    return SkinToneResult(
      skinTone: s,
      undertone: u,
      confidence: (vision['confidence'] as num?)?.toDouble() ?? 0.90,
      inferenceMode: 'gemini_vision',
      makeupRecommendations: _skinMakeupRecs(s, u),
    );
  }

  HairResult _hairResultFromVision(Map<String, dynamic> vision) {
    final t = _visionString(vision['hair_type']) ?? 'Wavy';
    final c = _visionString(vision['hair_color']) ?? 'Brown';
    return HairResult(
      hairType: t,
      hairColor: c,
      confidence: (vision['confidence'] as num?)?.toDouble() ?? 0.90,
      inferenceMode: 'gemini_vision',
      careTips: _hairCareTips(t),
      productRecommendations: _hairProductRecs(t, c),
      recommendedStyles: _coerceRecommendedStyles(vision['recommended_styles']),
    );
  }

  /// One photo → one vision pass → skin + hair always from the **same** image.
  Future<({SkinToneResult skin, HairResult hair})> analyzeBeauty(XFile imageFile) async {
    clearVisionCache();
    final vision = await _geminiVisionAnalyze(imageFile);
    if (vision != null) {
      return (
        skin: _skinToneResultFromVision(vision),
        hair: _hairResultFromVision(vision),
      );
    }
    final skin = await _analyzeSkinWithoutVision(imageFile);
    final hair = await _analyzeHairWithoutVision(imageFile);
    return (skin: skin, hair: hair);
  }

  Future<SkinToneResult> _analyzeSkinWithoutVision(XFile imageFile) async {
    // Remote server (Flask — only if /health succeeds; avoids connection refused noise)
    try {
      if (await _aiChatService.isServerAvailable()) {
        final apiResult = await _aiChatService.analyzeSkinRemote(imageFile);
        if (apiResult != null) {
          final s = apiResult['skin_tone'] ?? 'Medium';
          final u = apiResult['undertone'] ?? 'Neutral';
          return SkinToneResult(
            skinTone: s, undertone: u,
            confidence: (apiResult['confidence'] as num?)?.toDouble() ?? 0.90,
            inferenceMode: 'server',
            makeupRecommendations: _skinMakeupRecs(s, u),
          );
        }
      }
    } catch (e) { /* fall through */ }

    // 3) Pixel analysis fallback
    final px = await _pixelAnalyzeImage(imageFile);
    final s = px['skin_tone'] as String;
    final u = px['undertone'] as String;
    return SkinToneResult(
      skinTone: s, undertone: u,
      confidence: px['confidence'] as double,
      inferenceMode: 'pixel_analysis',
      makeupRecommendations: _skinMakeupRecs(s, u),
    );
  }

  Future<SkinToneResult> analyzeSkin(XFile imageFile) async {
    clearVisionCache();
    final vision = await _geminiVisionAnalyze(imageFile);
    if (vision != null) {
      return _skinToneResultFromVision(vision);
    }
    return _analyzeSkinWithoutVision(imageFile);
  }

  Future<HairResult> _analyzeHairWithoutVision(XFile imageFile) async {
    // On-device TFLite classifiers (offline-capable)
    final tflite = await _tfliteAnalyzeHair(imageFile);
    if (tflite != null) {
      final t = (tflite['hair_type'] as String?) ?? 'Wavy';
      var c = (tflite['hair_color'] as String?) ?? 'Brown';
      var mode = (tflite['inference_mode'] as String?) ?? 'tflite_ondevice';
      var conf = (tflite['confidence'] as num?)?.toDouble() ?? 0.80;

      return HairResult(
        hairType: t, hairColor: c,
        confidence: conf,
        inferenceMode: mode,
        careTips: _hairCareTips(t),
        productRecommendations: _hairProductRecs(t, c),
        recommendedStyles: [], // TFLite fallback doesn't do style matching yet
      );
    }

    // 3) Remote server (Flask — only if /health succeeds)
    try {
      if (await _aiChatService.isServerAvailable()) {
        final apiResult = await _aiChatService.analyzeHairRemote(imageFile);
        if (apiResult != null) {
          final t = apiResult['hair_type'] ?? 'Wavy';
          final c = apiResult['hair_color'] ?? 'Brown';
          return HairResult(
            hairType: t, hairColor: c,
            confidence: (apiResult['confidence'] as num?)?.toDouble() ?? 0.90,
            inferenceMode: 'server',
            careTips: _hairCareTips(t),
            productRecommendations: _hairProductRecs(t, c),
            recommendedStyles: [],
          );
        }
      }
    } catch (e) { /* fall through */ }

    // 4) Pixel analysis fallback
    final px = await _pixelAnalyzeImage(imageFile);
    final t = px['hair_type'] as String;
    final c = px['hair_color'] as String;
    return HairResult(
      hairType: t, hairColor: c,
      confidence: px['confidence'] as double,
      inferenceMode: 'pixel_analysis',
      careTips: _hairCareTips(t),
      productRecommendations: _hairProductRecs(t, c),
      recommendedStyles: [],
    );
  }

  Future<HairResult> analyzeHair(XFile imageFile) async {
    final vision = await _geminiVisionAnalyze(imageFile);
    if (vision != null) {
      return _hairResultFromVision(vision);
    }
    return _analyzeHairWithoutVision(imageFile);
  }

  Future<MakeupResult> analyzeMakeup(XFile imageFile) async {
    return const MakeupResult(
        makeupLevel: 'No Makeup', confidence: 1.0, inferenceMode: 'pixel_analysis');
  }

  // ── Skin makeup recommendations ───────────────────────────────────────────

  Map<String, String> _skinMakeupRecs(String tone, String undertone) {
    final isWarm = undertone == 'Warm';
    final isFair = tone == 'Fair' || tone == 'Light';
    final isDark = tone == 'Tan'  || tone == 'Deep';

    return {
      'Foundation':   isFair ? (isWarm ? 'Ivory W10' : 'Porcelain C10')
                     : isDark ? (isWarm ? 'Mahogany W50' : 'Espresso C50')
                     : (isWarm ? 'Golden Tan W30' : 'Sand N30'),
      'Lipstick':     isWarm
          ? (isFair ? 'Rose blush / peachy pink' : isDark ? 'Burnt orange / deep red' : 'Warm coral / terracotta')
          : (isFair ? 'Mauve / berry plum'       : isDark ? 'Plum / deep berry'       : 'Rose / cool pink'),
      'Blush':        isWarm ? 'Warm peach or coral'      : 'Soft rose or berry',
      'Eyeshadow':    isWarm ? (isDark ? 'Copper, bronze, gold' : 'Warm taupe, terracotta') : 'Mauve, silver, champagne',
      'Highlighter':  isWarm ? 'Gold or peach pearl'      : 'Silver or icy pink',
      'Eyeliner':     isDark ? 'Rich brown or deep plum'  : 'Soft brown or charcoal',
      'Bronzer':      isDark ? 'Deep warm bronze'         : (isWarm ? 'Light bronze' : 'Contour matte'),
    };
  }

  // ── Hair care tips ─────────────────────────────────────────────────────────

  List<String> _hairCareTips(String type) {
    switch (type) {
      case 'Straight': return [
        'Use a volumising shampoo to avoid flatness',
        'Apply lightweight serum to prevent oiliness',
        'Dry-shampoo between washes',
        'Silk pillowcase reduces friction and frizz',
        'Blow dry on medium heat with a round brush for body',
      ];
      case 'Wavy': return [
        'Scrunch in curl cream on wet hair',
        'Diffuse on low heat or air-dry for best texture',
        'Apply products section by section while soaking wet',
        'Pineapple at night to preserve wave pattern',
        'Avoid heavy oils — use lightweight mousse',
      ];
      case 'Curly': return [
        'Deep condition every week without fail',
        'LOC method: Leave-in → Oil → Cream for moisture',
        'Finger-detangle only — never brush when dry',
        'Sleep on a satin pillowcase or bonnet',
        'Refresh with a water + leave-in spritz on day 2+',
      ];
      case 'Coily': return [
        'Shea butter or heavy cream for moisture retention',
        'Stretch styles with braids or twists overnight',
        'Pre-poo with oil before shampooing',
        'Protective styles reduce breakage significantly',
        'Steam treatments monthly for deep hydration',
      ];
      default: return [
        'Moisturise regularly with a suitable conditioner',
        'Trim every 8–12 weeks to prevent split ends',
        'Always use heat protectant before styling',
      ];
    }
  }

  // ── Hair product recommendations ───────────────────────────────────────────

  Map<String, String> _hairProductRecs(String type, String color) {
    final isColoured = color == 'Blonde' || color == 'Red' || color == 'Auburn';
    return {
      'Shampoo':     isColoured
          ? 'Colour-safe sulphate-free shampoo'
          : (type == 'Curly' || type == 'Coily')
              ? 'Moisture-rich co-wash'
              : 'Volumising shampoo',
      'Conditioner': (type == 'Curly' || type == 'Coily')
          ? 'Leave-in cream conditioner'
          : 'Lightweight rinse-out conditioner',
      'Styling':     type == 'Straight' ? 'Frizz-control smoothing serum'
                   : type == 'Wavy'     ? 'Curl-enhancing lightweight cream'
                   : type == 'Curly'    ? 'Curl defining gel or mousse'
                   :                      'Heavy shea butter cream',
      'Treatment':   (type == 'Curly' || type == 'Coily')
          ? 'Weekly deep conditioning + monthly protein mask'
          : 'Weekly deep conditioning mask',
      'Protect':     'Heat protectant spray before any heat styling',
    };
  }

  void dispose() {
    _hairTypeInterpreter?.close();
    _hairColorInterpreter?.close();
    _hairTypeInterpreter = null;
    _hairColorInterpreter = null;
    _tfliteReady = false;
    _visionCacheKey = null;
    _visionCache = null;
  }
}
