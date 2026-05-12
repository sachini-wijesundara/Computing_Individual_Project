// API keys: `--dart-define=KEY=value` overrides bundled `.env` + `assets/env/local_keys.env`
// (merged in `main.dart` via flutter_dotenv).

import 'package:flutter_dotenv/flutter_dotenv.dart';

abstract final class AppSecrets {
  /// Google AI Studio / Gemini: https://aistudio.google.com/app/apikey
  static String get geminiApiKey {
    const fromDefine = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
    if (fromDefine.isNotEmpty) return fromDefine;
    return _dotenv('GEMINI_API_KEY');
  }

  /// OpenRouter (Hair Style Matcher): https://openrouter.ai/keys
  static String get openRouterApiKey {
    const fromDefine = String.fromEnvironment('OPENROUTER_API_KEY', defaultValue: '');
    if (fromDefine.isNotEmpty) return fromDefine;
    return _dotenv('OPENROUTER_API_KEY');
  }

  static String get openRouterModel {
    const fromDefine = String.fromEnvironment('OPENROUTER_MODEL', defaultValue: '');
    if (fromDefine.isNotEmpty) return fromDefine.replaceAll('\r', '').trim();
    final m = _dotenv('OPENROUTER_MODEL');
    if (m.isNotEmpty) return m;
    return 'google/gemini-2.0-flash-001';
  }

  static String _dotenv(String name) {
    if (!dotenv.isInitialized) return '';
    return dotenv.env[name]?.replaceAll('\r', '').trim() ?? '';
  }
}
