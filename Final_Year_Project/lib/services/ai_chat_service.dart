import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Configuration — change baseUrl to your Mac's IP when testing on a real device
class AIChatConfig {
  // Simulator: localhost works fine
  // Real device: use your Mac's IP e.g. http://192.168.1.100:5000
  static const String baseUrl = 'http://localhost:5000';
  static const int timeoutSeconds = 30;
}

class SkinAnalysisResult {
  final String skinTone;
  final String undertone;
  final double confidence;
  final Map<String, String> makeupRecommendations;
  final String inferenceMode;

  const SkinAnalysisResult({
    required this.skinTone,
    required this.undertone,
    required this.confidence,
    required this.makeupRecommendations,
    required this.inferenceMode,
  });

  factory SkinAnalysisResult.fromJson(Map<String, dynamic> j) {
    return SkinAnalysisResult(
      skinTone:              j['skin_tone']  as String? ?? 'Medium',
      undertone:             j['undertone']  as String? ?? 'Neutral',
      confidence:            (j['confidence'] as num?)?.toDouble() ?? 0.75,
      makeupRecommendations: Map<String, String>.from(
        (j['makeup_recommendations'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ) ?? {},
      ),
      inferenceMode: j['inference_mode'] as String? ?? 'pixel_analysis',
    );
  }
}

class HairAnalysisResult {
  final String hairType;
  final String hairColor;
  final double confidence;
  final Map<String, String> productRecommendations;
  final List<String> careTips;
  final String inferenceMode;

  const HairAnalysisResult({
    required this.hairType,
    required this.hairColor,
    required this.confidence,
    required this.productRecommendations,
    required this.careTips,
    required this.inferenceMode,
  });

  factory HairAnalysisResult.fromJson(Map<String, dynamic> j) {
    return HairAnalysisResult(
      hairType:   j['hair_type']  as String? ?? 'Wavy',
      hairColor:  j['hair_color'] as String? ?? 'Brown',
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0.70,
      productRecommendations: Map<String, String>.from(
        (j['product_recommendations'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ) ?? {},
      ),
      careTips: List<String>.from(j['care_tips'] as List? ?? []),
      inferenceMode: j['inference_mode'] as String? ?? 'pixel_analysis',
    );
  }
}

class ChatResponse {
  final String reply;
  final List<String> suggestions;

  const ChatResponse({required this.reply, required this.suggestions});

  factory ChatResponse.fromJson(Map<String, dynamic> j) {
    return ChatResponse(
      reply:       j['reply'] as String? ?? '',
      suggestions: List<String>.from(j['suggestions'] as List? ?? []),
    );
  }
}

class AIChatService {
  static final AIChatService _instance = AIChatService._internal();
  factory AIChatService() => _instance;
  AIChatService._internal();

  late final Dio _dio = Dio(BaseOptions(
    baseUrl:        AIChatConfig.baseUrl,
    connectTimeout: Duration(seconds: AIChatConfig.timeoutSeconds),
    receiveTimeout: Duration(seconds: AIChatConfig.timeoutSeconds),
    headers:        {'Content-Type': 'application/json'},
  ));

  /// Send image to Flask AI server for Skin/Undertone analysis
  Future<Map<String, dynamic>?> analyzeSkinRemote(File imageFile) async {
    try {
      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(imageFile.path, filename: 'skin.jpg'),
      });
      final response = await _dio.post('/analyze_skin', data: formData);
      if (response.statusCode == 200) {
        return response.data;
      }
    } catch (e) {
      debugPrint('Remote skin analysis error: $e');
    }
    return null;
  }

  /// Send image to Flask AI server for Hair Type/Color analysis
  Future<Map<String, dynamic>?> analyzeHairRemote(File imageFile) async {
    try {
      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(imageFile.path, filename: 'hair.jpg'),
      });
      final response = await _dio.post('/analyze_hair', data: formData);
      if (response.statusCode == 200) {
        return response.data;
      }
    } catch (e) {
      debugPrint('Remote hair analysis error: $e');
    }
    return null;
  }

  bool _serverAvailable = false;
  DateTime? _lastHealthCheck;

  /// Check if the Python API server is running
  Future<bool> isServerAvailable() async {
    // Cache health check for 30 seconds
    if (_lastHealthCheck != null &&
        DateTime.now().difference(_lastHealthCheck!).inSeconds < 30) {
      return _serverAvailable;
    }
    try {
      final resp = await _dio.get(
        '/health',
        options: Options(sendTimeout: const Duration(seconds: 5)),
      );
      _serverAvailable = resp.statusCode == 200;
    } catch (_) {
      _serverAvailable = false;
    }
    _lastHealthCheck = DateTime.now();
    return _serverAvailable;
  }

  /// Send a chat message to the beauty AI chatbot
  Future<ChatResponse> sendMessage(String message) async {
    final available = await isServerAvailable();

    if (!available) {
      return _offlineChatResponse(message);
    }

    try {
      final resp = await _dio.post('/chat', data: {'message': message});
      return ChatResponse.fromJson(resp.data as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Chat API error: $e');
      return _offlineChatResponse(message);
    }
  }

  /// Analyse skin tone from an image file
  Future<SkinAnalysisResult> analyzeSkin(File imageFile) async {
    final available = await isServerAvailable();

    if (!available) {
      return _offlineSkinAnalysis();
    }

    try {
      final bytes  = await imageFile.readAsBytes();
      final b64    = base64Encode(bytes);
      final resp   = await _dio.post('/analyze_skin', data: {'image_base64': b64});
      return SkinAnalysisResult.fromJson(resp.data as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Skin analysis API error: $e');
      return _offlineSkinAnalysis();
    }
  }

  /// Analyse hair type and color from an image file
  Future<HairAnalysisResult> analyzeHair(File imageFile) async {
    final available = await isServerAvailable();

    if (!available) {
      return _offlineHairAnalysis();
    }

    try {
      final bytes = await imageFile.readAsBytes();
      final b64   = base64Encode(bytes);
      final resp  = await _dio.post('/analyze_hair', data: {'image_base64': b64});
      return HairAnalysisResult.fromJson(resp.data as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Hair analysis API error: $e');
      return _offlineHairAnalysis();
    }
  }

  // ── Offline fallbacks ────────────────────────────────────────────────────────

  ChatResponse _offlineChatResponse(String message) {
    final lower = message.toLowerCase();

    String reply;
    if (lower.contains('curly') || lower.contains('curl')) {
      reply = "Curly hair needs moisture above all! 🌀\n\n"
              "• Use sulfate-free shampoo & co-wash\n"
              "• Deep condition weekly\n"
              "• LOC method: Leave-in → Oil → Cream\n"
              "• Diffuse on low or air-dry\n"
              "• Sleep on satin pillowcase\n\n"
              "💡 Start the Beauty AI server to get full personalised recommendations!";
    } else if (lower.contains('hair')) {
      reply = "For hair care, knowing your hair type is key! Try these basics:\n\n"
              "• **Straight**: Volumising products\n"
              "• **Wavy**: Curl-enhancing cream\n"
              "• **Curly**: LOC method + deep conditioning\n"
              "• **Coily**: Shea butter & protective styles\n\n"
              "Which type are you? I can give more specific tips! 💇‍♀️";
    } else if (lower.contains('skin') || lower.contains('makeup') || lower.contains('foundation')) {
      reply = "Great beauty starts with knowing your skin tone! 💄\n\n"
              "To find your undertone, check your wrist veins:\n"
              "• Blue/purple → Cool\n"
              "• Green → Warm\n"
              "• Mix of both → Neutral\n\n"
              "Use the AI Skin Analysis for an instant reading! 📸";
    } else {
      reply = "Hello! I'm your La Vogue Vista Beauty Assistant ✨\n\n"
              "I can help with:\n"
              "• 💇 Hair type & care recommendations\n"
              "• 💄 Makeup colour matching\n"
              "• ✨ Skincare routines\n"
              "• 🌟 Beauty trends\n\n"
              "*(Running offline mode — start the AI server for full features)*";
    }

    return ChatResponse(
      reply:       reply,
      suggestions: ['My hair type', 'Skin tone analysis', 'Lipstick colours', 'Beauty trends'],
    );
  }

  SkinAnalysisResult _offlineSkinAnalysis() {
    return const SkinAnalysisResult(
      skinTone:  'Medium',
      undertone: 'Warm',
      confidence: 0.72,
      makeupRecommendations: {
        'foundation':  'Golden Tan or Honey — warm undertones',
        'blush':       'Terracotta or warm coral',
        'lipstick':    'Warm red, burnt sienna, or caramel nude',
        'eyeshadow':   'Copper, terracotta, warm gold',
        'highlighter': 'Gold or copper',
        'bronzer':     'Medium warm bronze',
        'eyeliner':    'Brown, dark olive, or bronze',
      },
      inferenceMode: 'offline',
    );
  }

  HairAnalysisResult _offlineHairAnalysis() {
    return const HairAnalysisResult(
      hairType:   'Wavy',
      hairColor:  'Brown',
      confidence: 0.68,
      productRecommendations: {
        'shampoo':     'Sulfate-free moisturising shampoo',
        'conditioner': 'Medium-weight conditioner, focus on ends',
        'styling':     'Curl-enhancing cream or light gel',
        'treatment':   'Bi-weekly protein treatment',
        'avoid':       'Brushing when dry (causes frizz)',
      },
      careTips: [
        'Scrunch with a microfibre towel, never rub',
        'Apply products to soaking wet hair',
        'Air-dry or diffuse on low heat',
        'Pineapple hair at night to preserve waves',
      ],
      inferenceMode: 'offline',
    );
  }
}
