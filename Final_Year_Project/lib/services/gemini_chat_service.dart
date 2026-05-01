// lib/services/gemini_chat_service.dart
//
// Gemini-powered beauty chatbot.
// Uses the user's TFLite-detected Beauty Profile as system context so every
// answer is personalised to their actual skin tone, undertone, and hair type.
//
// SETUP: Add GEMINI_API_KEY to `.env` (see `.env.example`) or pass
//   --dart-define=GEMINI_API_KEY=... when running Flutter.
//   https://aistudio.google.com/app/apikey

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/foundation.dart';

import '../config/app_secrets.dart';

class BeautyProfile {
  final String skinTone;
  final String undertone;
  final String hairType;
  final String hairColor;
  final String inferenceMode;

  const BeautyProfile({
    required this.skinTone,
    required this.undertone,
    required this.hairType,
    required this.hairColor,
    required this.inferenceMode,
  });
}

class GeminiChatService {
  static String get _apiKey => AppSecrets.geminiApiKey;

  GenerativeModel? _model;
  ChatSession? _chat;
  BeautyProfile? _profile;
  bool _initialized = false;
  // Ordered list of models to try — stops at first success.
  static const _models = [
    'gemini-2.5-flash',
    'gemini-1.5-pro',
    'gemini-1.0-pro',
  ];
  String _activeModel = _models[0];

  static final GeminiChatService _instance = GeminiChatService._internal();
  factory GeminiChatService() => _instance;
  GeminiChatService._internal();

  bool get isConfigured => _apiKey.isNotEmpty;

  /// Call this when the TFLite analysis finishes to personalise the chat.
  void setBeautyProfile(BeautyProfile profile) {
    _profile = profile;
    _initialized = false; // force re-init with new context
    _initChat();
  }

  void _initChat() {
    if (!isConfigured) return;

    final systemPrompt = _buildSystemPrompt(_profile);

    _model = GenerativeModel(
      model: _activeModel,
      apiKey: _apiKey,
      systemInstruction: Content.system(systemPrompt),
      generationConfig: GenerationConfig(
        temperature: 0.55,
        maxOutputTokens: 650,
      ),
    );

    _chat = _model!.startChat();
    _initialized = true;
    debugPrint('✅ Gemini chat initialised with beauty profile');
  }

  String _buildSystemPrompt(BeautyProfile? profile) {
    String base = '''
You are "Lumi", the AI Beauty Assistant for La Vogue Vista — a premium beauty app.
You are warm, friendly, knowledgeable, and speak like a professional makeup artist and hair stylist.
Keep answers concise and useful (3-8 lines unless the user asks for more).
Answer every user question directly. If off-topic, still answer briefly, then optionally connect back to beauty.
Use relevant emojis to make answers feel warm and engaging.
''';

    if (profile != null) {
      base += '''

IMPORTANT: The user has already been analysed by our on-device AI models.
Their beauty profile is:
  - Skin tone: ${profile.skinTone}
  - Undertone: ${profile.undertone}
  - Hair type: ${profile.hairType}
  - Hair colour: ${profile.hairColor}
  - Analysis mode: ${profile.inferenceMode}

Always tailor your recommendations to this specific profile.
When recommending foundation shades, lipstick colours, eyeshadow, blush, bronzer,
hair products, or skincare — make them specific to ${profile.skinTone} skin with
${profile.undertone} undertones and ${profile.hairType} ${profile.hairColor} hair.
Address the user as "you" and reference their profile naturally.
''';
    } else {
      base += '''

No beauty profile has been scanned yet. Encourage the user to tap the camera
button to get a personalised analysis, and answer general beauty questions in the meantime.
''';
    }

    return base;
  }

  Future<String> sendMessage(String message) async {
    if (!isConfigured) return _noApiKeyMessage();
    if (!_initialized) _initChat();

    // Try each model in sequence until one works.
    for (final model in _models) {
      if (_activeModel != model && _initialized) {
        // Already set to a different model from a previous call — skip earlier ones.
        if (_models.indexOf(model) < _models.indexOf(_activeModel)) continue;
      }
      _activeModel = model;
      _initialized = false;
      _initChat();
      try {
        final response = await _chat!.sendMessage(Content.text(message))
            .timeout(const Duration(seconds: 20));
        final text = response.text;
        if (text != null && text.isNotEmpty) {
          debugPrint('✅ Gemini replied using model: $model');
          return text;
        }
      } catch (e) {
        debugPrint('Gemini [$model] error: $e');
        continue; // try next model
      }
    }
    return _fallback(message);
  }

  /// Reset the conversation history (new session).
  void resetChat() {
    _initialized = false;
    _initChat();
  }

  // ── Fallback responses (when Gemini is unavailable) ────────────────────────

  String _noApiKeyMessage() {
    return "⚙️ **Almost there!** To enable the real AI chatbot:\n\n"
        "1. Go to **aistudio.google.com/app/apikey** (free)\n"
        "2. Click **Create API key**\n"
        "3. Add **GEMINI_API_KEY** to your project `.env` (see `.env.example`)\n"
        "   or run with `--dart-define=GEMINI_API_KEY=...`\n\n"
        "Until then, I can still answer beauty questions using your scanned profile 💄";
  }

  String _fallback(String message) {
    final p = _profile;
    final lower = message.toLowerCase();

    if (lower.contains('foundation') || lower.contains('base')) {
      return p != null
          ? "For your ${p.skinTone} skin with ${p.undertone} undertones, look for ${p.undertone == 'Warm' ? 'golden or yellow-based' : p.undertone == 'Cool' ? 'pink or rosy-based' : 'neutral'} foundations. A buildable medium-coverage formula works beautifully! ✨"
          : "Match your foundation to your undertone — check your wrist veins: blue = cool, green = warm, both = neutral! 💄";
    }
    if (lower.contains('lipstick') || lower.contains('lip')) {
      return p != null
          ? "With ${p.undertone} undertones, ${p.undertone == 'Warm' ? 'corals, warm reds, and terracotta nudes' : p.undertone == 'Cool' ? 'berries, mauves, and cool pinks' : 'classic reds, rosy nudes, and dusty roses'} will look stunning on you! 💋"
          : "Warm undertones → coral & terracotta. Cool undertones → berry & mauve. Neutral → almost anything goes! 💄";
    }
    if (lower.contains('hair')) {
      return p != null
          ? "For your ${p.hairType} hair: ${p.hairType == 'Curly' || p.hairType == 'Coily' ? 'deep condition weekly, use LOC method, and sleep on satin' : p.hairType == 'Wavy' ? 'scrunch in curl cream, diffuse on low heat' : 'volumising shampoo and lightweight serum'} 💇"
          : "Hair care starts with knowing your type — straight, wavy, curly, or coily. Each needs a different routine! 💇";
    }
    if (lower.contains('skin') || lower.contains('glow') || lower.contains('routine')) {
      return "A solid skincare routine: gentle cleanser → vitamin C or niacinamide serum → moisturiser → SPF 50+ in the morning. At night, swap SPF for retinol or a sleeping mask ✨";
    }

    return "I'm your beauty assistant! Ask me about skincare, makeup, hair care, foundation matching, lipstick shades, or beauty trends 💄✨";
  }
}
