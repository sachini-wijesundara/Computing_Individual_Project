// lib/widgets/simple_lip_painter.dart
//
// A simple custom painter that renders a lipstick overlay from normalised
// lip landmark points.  Used by LipOverlayPainter.

import 'dart:ui' as ui;
import 'package:flutter/material.dart';

  final List<Offset> lipPoints;
  final Color color;
  final double opacity;
  final ui.Size frameSize;

    required this.lipPoints,
    required this.color,
    required this.opacity,
    required this.frameSize,
  });

  @override
  void paint(Canvas canvas, ui.Size size) {
    if (lipPoints.length < 3) return;

    // Map normalised [0-1] coordinates to canvas pixels
    final scaleX = size.width  / (frameSize.width  > 0 ? frameSize.width  : 1);
    final scaleY = size.height / (frameSize.height > 0 ? frameSize.height : 1);

    final pixelPoints = lipPoints
        .map((p) => Offset(p.dx * scaleX, p.dy * scaleY))
        .toList();

    final path = Path()..moveTo(pixelPoints.first.dx, pixelPoints.first.dy);
    for (final pt in pixelPoints.skip(1)) {
      path.lineTo(pt.dx, pt.dy);
    }
    path.close();

    // Fill
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.multiply,
    );

    // Soft edge glow
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: (opacity * 0.3).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
      old.lipPoints != lipPoints ||
      old.color != color ||
      old.opacity != opacity;
}
