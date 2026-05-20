import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Web stub: same result types as IO implementation for API compatibility.
class SkinToneResult {
  final String skinTone;
  final String undertone;
  final double confidence;
  final String inferenceMode;
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
  final String hairType;
  final String hairColor;
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

/// Web: no TFLite / Gemini pipeline in this stub — returns safe placeholder values.
class TFLiteAnalysisService {
  static final TFLiteAnalysisService _instance = TFLiteAnalysisService._internal();
  factory TFLiteAnalysisService() => _instance;
  TFLiteAnalysisService._internal();

  Future<void> initialize() async {
    debugPrint('TFLiteAnalysisService (web stub): initialize no-op');
  }

  void clearVisionCache() {}

  Future<({SkinToneResult skin, HairResult hair})> analyzeBeauty(XFile file) async {
    final skin = await analyzeSkin(file);
    final hair = await analyzeHair(file);
    return (skin: skin, hair: hair);
  }

  Future<SkinToneResult> analyzeSkin(XFile file) async {
    return const SkinToneResult(
      skinTone: '—',
      undertone: '—',
      confidence: 0,
      inferenceMode: 'web_stub',
      makeupRecommendations: {},
    );
  }

  Future<HairResult> analyzeHair(XFile file) async {
    return const HairResult(
      hairType: '—',
      hairColor: '—',
      confidence: 0,
      inferenceMode: 'web_stub',
      careTips: [],
      productRecommendations: {},
      recommendedStyles: [],
    );
  }
}
