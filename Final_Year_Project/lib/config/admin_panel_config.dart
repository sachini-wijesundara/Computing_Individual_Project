class AdminPanelConfig {
  AdminPanelConfig._();

  static const String _raw = String.fromEnvironment(
    'ADMIN_PANEL_EMAILS',
    defaultValue: 'lavougevistaofficial@gmail.com',
  );

  static bool isAllowedAdminEmail(String? email) {
    if (email == null || email.trim().isEmpty) return false;
    final value = email.trim().toLowerCase();
    final allowed = _raw
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty);
    return allowed.contains(value);
  }
}
