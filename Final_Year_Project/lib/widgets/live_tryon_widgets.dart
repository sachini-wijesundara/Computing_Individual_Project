// lib/widgets/live_tryon_widgets.dart
//
// Shared widgets + enums used by live_tryon_screen.dart
// Defines: FinishPreset, Hud, CircleButton, BottomTray

import 'package:flutter/material.dart';

// ── Finish preset enum ────────────────────────────────────────────────────────
enum FinishPreset { matte, satin, gloss, metallic }

extension FinishPresetLabel on FinishPreset {
  String get label {
    switch (this) {
      case FinishPreset.matte:     return 'Matte';
      case FinishPreset.satin:     return 'Satin';
      case FinishPreset.gloss:     return 'Gloss';
      case FinishPreset.metallic:  return 'Metallic';
    }
  }
}

// ── HUD overlay ───────────────────────────────────────────────────────────────
class Hud extends StatelessWidget {
  const Hud({
    super.key,
    required this.ready,
    required this.fps,
    required this.frames,
    required this.det,
    this.compact = false,
  });

  final bool   ready;
  final double fps;
  final int    frames;
  final int    det;
  /// When true, only shows READY/DETECTING (no fps line) — fits narrow top bars.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final statusRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: ready ? Colors.greenAccent : Colors.redAccent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          ready ? 'READY' : 'DETECTING…',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      constraints: const BoxConstraints(minHeight: 28, maxHeight: 36),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: (compact || fps <= 0)
          ? statusRow
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                statusRow,
                const SizedBox(height: 2),
                Text(
                  '${fps.toStringAsFixed(1)} fps  |  $det det',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
    );
  }
}

// ── Circle icon button ────────────────────────────────────────────────────────
class CircleButton extends StatelessWidget {
  const CircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 44.0,
    this.iconColor = Colors.white,
    this.backgroundColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color  iconColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: backgroundColor ?? Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: size * 0.5),
      ),
    );
  }
}

// ── Bottom tray ───────────────────────────────────────────────────────────────
class BottomTray extends StatelessWidget {
  const BottomTray({
    super.key,
    required this.height,
    required this.shades,
    required this.selectedIndex,
    required this.intensity,
    required this.onSelect,
    required this.onIntensityChange,
    required this.isCompareMode,
    required this.onModeChange,
    required this.splitPosition, // Added
    required this.onSplitChange, // Added
    this.productImage,
  });

  final double height;
  final List<Map<String, String>> shades;
  final int selectedIndex;
  final double intensity;
  final ValueChanged<int> onSelect;
  final ValueChanged<double> onIntensityChange;
  final bool isCompareMode;
  final ValueChanged<bool> onModeChange;
  final double splitPosition; // Added
  final ValueChanged<double> onSplitChange; // Added
  final String? productImage;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Tab Header ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildTab(context, "SHADES", !isCompareMode, () => onModeChange(false)),
                const SizedBox(width: 32),
                _buildTab(context, "COMPARE", isCompareMode, () => onModeChange(true)),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 0.5),

          const SizedBox(height: 16),

          // ── Content: compare scrolls; shades = horizontal strip only (slider below, not in ListView) ─
          Expanded(
            child: isCompareMode
                ? _buildCompareContent(context)
                : _buildShadeStrip(context),
          ),

          if (!isCompareMode) ...[
            const SizedBox(height: 10),
            Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                0,
                24,
                MediaQuery.paddingOf(context).bottom + 16,
              ),
              child: _buildIntensityRow(context),
            ),
          ],
        ],
      ),
    );
  }

  /// Horizontal shade swatches only — keeps vertical scroll away from the intensity [Slider] below.
  /// Uses [LayoutBuilder] so the horizontal [ListView] always gets a finite width (required for layout).
  Widget _buildShadeStrip(BuildContext context) {
    if (shades.isEmpty) {
      return const Center(child: Text('No shades available'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.center,
          child: SizedBox(
            height: 56,
            width: constraints.maxWidth,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: shades.length,
              itemBuilder: (context, i) {
                final hex = _shadeHex(shades[i]) ?? '#D4717A';
                final color = _hexToColor(hex);
                final selected = i == selectedIndex;
                return GestureDetector(
                  onTap: () => onSelect(i),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? const Color(0xFF8B0000) : Colors.transparent,
                            width: 2,
                          ),
                          boxShadow: selected
                              ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)]
                              : null,
                        ),
                      ),
                      if (selected) const Icon(Icons.check, color: Colors.white, size: 18),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildIntensityRow(BuildContext context) {
    return Row(
      children: [
        const Text(
          'INTENSITY',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: const Color(0xFF8B0000),
              inactiveTrackColor: Colors.black12,
              thumbColor: const Color(0xFF8B0000),
              overlayColor: const Color(0xFF8B0000).withOpacity(0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: intensity,
              min: 0.1,
              max: 1.0,
              onChanged: onIntensityChange,
            ),
          ),
        ),
        Text(
          '${(intensity * 100).toInt()}%',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildTab(BuildContext context, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: active ? Colors.black : Colors.black38,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: active ? 24 : 0,
            height: 2,
            color: const Color(0xFF8B0000), // La Vogue Vista Burgundy
          ),
        ],
      ),
    );
  }

  Widget _buildCompareContent(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      children: [
        const Text(
          "COMPARE MODE",
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
        ),
        const SizedBox(height: 8),
        const Text(
          "Slide the handle across your face to compare with and without makeup.",
          style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.4),
        ),
        const SizedBox(height: 12),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFF8B0000),
            inactiveTrackColor: Colors.black12,
            thumbColor: Colors.white,
            overlayColor: const Color(0xFF8B0000).withOpacity(0.1),
          ),
          child: Slider(
            value: splitPosition,
            onChanged: onSplitChange,
            min: 0.0,
            max: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: OutlinedButton(
            onPressed: () => onModeChange(false),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF8B0000),
              side: const BorderSide(color: Color(0xFF8B0000)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("EXIT COMPARE"),
          ),
        ),
      ],
    );
  }

  Color _hexToColor(String hex) {
    var s = hex.replaceAll('#', '');
    if (s.length == 6) s = 'FF$s';
    return Color(int.parse(s, radix: 16));
  }

  String? _shadeHex(Map<String, String> shade) {
    final raw = shade['hex'] ??
        shade['colorHex'] ??
        shade['colourHex'] ??
        shade['color'] ??
        shade['colour'] ??
        shade['value'];
    if (raw == null || raw.isEmpty) return null;
    var s = raw.trim();
    if (s.startsWith('0x') || s.startsWith('0X')) s = s.substring(2);
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 8) s = s.substring(2);
    if (s.length != 6 || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s)) return null;
    return '#${s.toUpperCase()}';
  }
}
