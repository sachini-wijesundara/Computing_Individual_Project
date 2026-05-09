class EmailJsConfig {
  EmailJsConfig._();

  static const String publicKey = String.fromEnvironment(
    'EMAILJS_PUBLIC_KEY',
    defaultValue: 'H5aUi2jyiEX1PO_Ec',
  );

  /// Private key for REST API (only if enabled in EmailJS dashboard).
  static const String accessToken = String.fromEnvironment(
    'EMAILJS_ACCESS_TOKEN',
    defaultValue: 'c-uQtBica-pxrtnGgJQdt',
  );

  static const String serviceId = String.fromEnvironment(
    'EMAILJS_SERVICE_ID',
    defaultValue: 'service_2gzjnz9',
  );

  static const String templateId = String.fromEnvironment(
    'EMAILJS_TEMPLATE_ID',
    defaultValue: 'template_czd3rm5',
  );

  static bool get isConfigured =>
      publicKey.isNotEmpty && serviceId.isNotEmpty && templateId.isNotEmpty;
}
