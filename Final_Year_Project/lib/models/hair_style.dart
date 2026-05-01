import 'package:flutter/material.dart';

class HairStyle {
  final String id, name, description, bestFor, overlayShape;
  final Color accent;
  final List<String> tags;

  const HairStyle({
    required this.id,
    required this.name,
    required this.description,
    required this.bestFor,
    required this.accent,
    required this.tags,
    this.overlayShape = 'long',
  });
}

const hairStyles = [
  HairStyle(id: 'blunt_bob',      name: 'Blunt Bob',
    description: 'Clean, straight cut at the jaw. Timeless and bold.',
    bestFor: 'Oval, Square, Heart',
    accent: Color(0xFFC41E3A), tags: ['Short', 'Classic', 'Low Maintenance'],
    overlayShape: 'bob'),
  HairStyle(id: 'beachy_waves',   name: 'Beachy Waves',
    description: 'Effortless textured waves for a relaxed, sun-kissed look.',
    bestFor: 'All face shapes',
    accent: Color(0xFF4A90D9), tags: ['Medium', 'Casual', 'Volume'],
    overlayShape: 'waves'),
  HairStyle(id: 'curtain_bangs',  name: 'Curtain Bangs',
    description: 'Parted fringe framing the face. Vintage chic meets modern.',
    bestFor: 'Oval, Square',
    accent: Color(0xFF9B59B6), tags: ['Bangs', 'Trendy', 'Face-Framing'],
    overlayShape: 'bangs'),
  HairStyle(id: 'layer_lob',      name: 'Layered Lob',
    description: 'Long bob with movement-adding layers for effortless texture.',
    bestFor: 'Round, Heart',
    accent: Color(0xFF27AE60), tags: ['Medium', 'Volume', 'Natural'],
    overlayShape: 'waves'),
  HairStyle(id: 'sleek_straight', name: 'Sleek Straight',
    description: 'Ultra-polished, straight strands for a powerful statement.',
    bestFor: 'Oval, Oblong',
    accent: Color(0xFF2C3E50), tags: ['Polished', 'Formal', 'Low Frizz'],
    overlayShape: 'straight'),
  HairStyle(id: 'big_curls',      name: 'Big Voluminous Curls',
    description: 'Bouncy, defined curls with maximum volume and drama.',
    bestFor: 'Oval, Long',
    accent: Color(0xFFE67E22), tags: ['Curly', 'Volume', 'Glam'],
    overlayShape: 'curly'),
  HairStyle(id: 'braid_crown',    name: 'Braided Crown',
    description: 'Halo braid for an ethereal, bohemian goddess look.',
    bestFor: 'Oval, Heart, Square',
    accent: Color(0xFFD4A843), tags: ['Updo', 'Bridal', 'Bohemian'],
    overlayShape: 'braid'),
  HairStyle(id: 'wolf_cut',       name: 'Wolf Cut',
    description: 'Shaggy layers blending 70s rocker vibes with modern texture.',
    bestFor: 'Oval, Square',
    accent: Color(0xFF6C3483), tags: ['Edgy', 'Trendy', 'Layers'],
    overlayShape: 'wolf'),
  HairStyle(id: 'slick_bun',      name: 'Slick Bun',
    description: 'Polished high bun for a clean, editorial look.',
    bestFor: 'All face shapes',
    accent: Color(0xFFC0392B), tags: ['Updo', 'Sleek', 'Professional'],
    overlayShape: 'bun'),
  HairStyle(id: 'textured_pixie', name: 'Textured Pixie',
    description: 'Bold short cut with tousled layers for a daring edge.',
    bestFor: 'Oval, Heart',
    accent: Color(0xFF16A085), tags: ['Short', 'Bold', 'Edgy'],
    overlayShape: 'pixie'),
  HairStyle(id: 'shaggy_mullet',  name: 'Shaggy Mullet',
    description: 'Modern rocker vibes with texture and movement.',
    bestFor: 'Oval, Square',
    accent: Color(0xFFE74C3C), tags: ['Edgy', 'Medium', 'Trendy'],
    overlayShape: 'wolf'),
  HairStyle(id: 'french_bob',     name: 'French Bob',
    description: 'Chic, chin-length bob with effortless European elegance.',
    bestFor: 'Oval, Heart',
    accent: Color(0xFF8E44AD), tags: ['Short', 'Chic', 'Classic'],
    overlayShape: 'bob'),
  HairStyle(id: 'long_layers',    name: 'Long Layers',
    description: 'Flowing length with face-framing layers for soft movement.',
    bestFor: 'All face shapes',
    accent: Color(0xFF3498DB), tags: ['Long', 'Volume', 'Natural'],
    overlayShape: 'long'),
  HairStyle(id: 'side_swept',     name: 'Side Swept',
    description: 'Dramatic side part for a sophisticated, asymmetrical look.',
    bestFor: 'Round, Heart',
    accent: Color(0xFFF39C12), tags: ['Sophisticated', 'Formal', 'Asymmetrical'],
    overlayShape: 'waves'),
  HairStyle(id: 'buzz_cut',       name: 'Buzz Cut',
    description: 'Minimalist, ultra-short length for a bold, powerful look.',
    bestFor: 'Oval, Rectangular',
    accent: Color(0xFF95A5A6), tags: ['Ultra-Short', 'Bold', 'Minimalist'],
    overlayShape: 'buzz'),
];

class HairIconPainter extends CustomPainter {
  final String shape;
  final Color color;
  const HairIconPainter({required this.shape, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeWidth = 2;
    final w = size.width;
    final h = size.height;

    switch (shape) {
      case 'bob':
        final path = Path()
          ..moveTo(w * .15, 0)
          ..quadraticBezierTo(w * .5, -h * .1, w * .85, 0)
          ..lineTo(w * .85, h * .6)
          ..quadraticBezierTo(w * .5, h * .75, w * .15, h * .6)
          ..close();
        canvas.drawPath(path, paint);
        break;
      case 'pixie':
      case 'buzz':
        final path = Path()
          ..moveTo(w * .2, h * .4)
          ..quadraticBezierTo(w * .5, -h * .1, w * .8, h * .4)
          ..quadraticBezierTo(w * .5, h * .55, w * .2, h * .4)
          ..close();
        canvas.drawPath(path, paint);
        break;
      case 'bun':
        canvas.drawCircle(Offset(w * .5, h * .3), w * .22, paint);
        final headPaint = Paint()
          ..color = color.withOpacity(.4)
          ..style = PaintingStyle.fill;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(w * .5, h * .75),
              width: w * .55, height: h * .45),
          headPaint,
        );
        break;
      case 'braid':
        final ringPaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .13;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(w * .5, h * .42),
              width: w * .7, height: h * .5),
          ringPaint,
        );
        break;
      case 'curly':
        final path = Path()
          ..moveTo(w * .05, h * .3)
          ..quadraticBezierTo(-w * .1, -h * .2, w * .5, -h * .05)
          ..quadraticBezierTo(w * 1.1, -h * .2, w * .95, h * .3)
          ..quadraticBezierTo(w * .85, h * .9, w * .5, h)
          ..quadraticBezierTo(w * .15, h * .9, w * .05, h * .3)
          ..close();
        canvas.drawPath(path, paint);
        break;
      case 'waves':
        final path = Path()
          ..moveTo(w * .1, 0)
          ..quadraticBezierTo(w * .5, -h * .1, w * .9, 0)
          ..lineTo(w * .9, h * .7)
          ..quadraticBezierTo(w * .75, h * .85, w * .6, h * .7)
          ..quadraticBezierTo(w * .5, h * .6, w * .4, h * .7)
          ..quadraticBezierTo(w * .25, h * .85, w * .1, h * .7)
          ..close();
        canvas.drawPath(path, paint);
        break;
      case 'wolf':
        final path = Path()
          ..moveTo(w * .1, 0)
          ..quadraticBezierTo(w * .5, -h * .15, w * .9, 0)
          ..lineTo(w * .85, h * .5)
          ..lineTo(w * .95, h * .6)
          ..lineTo(w * .75, h * .55)
          ..lineTo(w * .8, h * .8)
          ..lineTo(w * .6, h * .65)
          ..lineTo(w * .5, h)
          ..lineTo(w * .4, h * .65)
          ..lineTo(w * .2, h * .8)
          ..lineTo(w * .25, h * .55)
          ..lineTo(w * .05, h * .6)
          ..lineTo(w * .15, h * .5)
          ..close();
        canvas.drawPath(path, paint);
        break;
      case 'bangs':
        final path = Path()
          ..moveTo(w * .1, 0)
          ..quadraticBezierTo(w * .5, -h * .1, w * .9, 0)
          ..lineTo(w * .9, h)
          ..lineTo(w * .1, h)
          ..close();
        canvas.drawPath(path, paint);
        final linePaint = Paint()
          ..color = Colors.white.withOpacity(.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        final line = Path()
          ..moveTo(w * .5, 0)
          ..quadraticBezierTo(w * .35, h * .2, w * .1, h * .3);
        canvas.drawPath(line, linePaint);
        final line2 = Path()
          ..moveTo(w * .5, 0)
          ..quadraticBezierTo(w * .65, h * .2, w * .9, h * .3);
        canvas.drawPath(line2, linePaint);
        break;
      case 'straight':
        final path = Path()
          ..moveTo(w * .12, 0)
          ..quadraticBezierTo(w * .5, -h * .12, w * .88, 0)
          ..lineTo(w * .82, h * .92)
          ..quadraticBezierTo(w * .5, h, w * .18, h * .92)
          ..close();
        canvas.drawPath(path, paint);
        break;
      default:
        final path = Path()
          ..moveTo(w * .15, 0)
          ..quadraticBezierTo(w * .5, -h * .1, w * .85, 0)
          ..lineTo(w * .85, h)
          ..lineTo(w * .15, h)
          ..close();
        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(HairIconPainter old) =>
      old.shape != shape || old.color != color;
}
