// Compile-time secrets from `--dart-define=...` (see `.env.example` + `ios_quick_run.sh`).

abstract final class AppSecrets {
  /// Google AI Studio / Gemini: https://aistudio.google.com/app/apikey
  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  /// OpenRouter (Hair Style Matcher): https://openrouter.ai/keys
  static const String openRouterApiKey = String.fromEnvironment(
    'OPENROUTER_API_KEY',
    defaultValue: '',
  );

  static const String openRouterModel = String.fromEnvironment(
    'OPENROUTER_MODEL',
    defaultValue: 'google/gemini-2.0-flash-001',
  );
}
