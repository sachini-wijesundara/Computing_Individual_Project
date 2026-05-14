import 'package:flutter/material.dart';

/// Deterministic lip colours derived from analysed skin tone + undertone.
/// Matches the family of shades in [TFLiteAnalysisService] `_skinMakeupRecs` so the
/// same profile always maps to the same live-try-on colour (reduces “random” feel).
class BeautyProfileShades {
  BeautyProfileShades._();

  static Color lipPrimaryForProfile(String skinTone, String undertone) {
    final isWarm = undertone.toLowerCase() == 'warm';
    final tone = skinTone.toLowerCase();
    final isFair = tone == 'fair' || tone == 'light';
    final isDark = tone == 'tan' || tone == 'deep';

    if (isWarm) {
      if (isFair) return const Color(0xFFD4778E);
      if (isDark) return const Color(0xFF8B2500);
      return const Color(0xFFB85C38);
    }
    if (isFair) return const Color(0xFF9B4D6F);
    if (isDark) return const Color(0xFF5C1A3D);
    return const Color(0xFFC75B7A);
  }

  /// Human-readable lip shade label (same matrix as [lipPrimaryForProfile]).
  static String lipShadeNameForProfile(String skinTone, String undertone) {
    final isWarm = undertone.toLowerCase() == 'warm';
    final tone = skinTone.toLowerCase();
    final isFair = tone == 'fair' || tone == 'light';
    final isDark = tone == 'tan' || tone == 'deep';

    if (isWarm) {
      if (isFair) return 'Soft rose mauve';
      if (isDark) return 'Spiced terracotta';
      return 'Warm brick rose';
    }
    if (isFair) return 'Cool berry pink';
    if (isDark) return 'Deep wine berry';
    return 'Mauve rose';
  }

  /// Second option (slightly deeper / alternate family) for UI chips.
  static Color lipAltForProfile(String skinTone, String undertone) {
    final isWarm = undertone.toLowerCase() == 'warm';
    final tone = skinTone.toLowerCase();
    final isFair = tone == 'fair' || tone == 'light';
    final isDark = tone == 'tan' || tone == 'deep';

    if (isWarm) {
      if (isFair) return const Color(0xFFE8A598);
      if (isDark) return const Color(0xFF6B1F0F);
      return const Color(0xFF9E3D2C);
    }
    if (isFair) return const Color(0xFF7A3D5C);
    if (isDark) return const Color(0xFF3D1028);
    return const Color(0xFFA84868);
  }

  static String hexRgb(Color c) {
    final r = (c.r * 255.0).round().clamp(0, 255);
    final g = (c.g * 255.0).round().clamp(0, 255);
    final b = (c.b * 255.0).round().clamp(0, 255);
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }
}
