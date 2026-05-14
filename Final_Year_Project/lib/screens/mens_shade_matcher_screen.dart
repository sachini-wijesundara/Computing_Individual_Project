// lib/screens/mens_shade_matcher_screen.dart
//
// Men's hair shade quiz — step 2 branches on step 1; result reflects answers;
// "Unsure" opens live hair try-on. (Avoids missing bundled product PNG.)
import 'package:flutter/material.dart';

import 'hair_color_tryon_screen.dart';

const _orange = Color(0xFFE9651F);
const _bg = Colors.black;
const _white = Colors.white;

class _QuizOption {
  final String label;
  final Color color;
  const _QuizOption(this.label, this.color);
}

const _step1Options = [
  _QuizOption('Black', Color(0xFF2E2B2A)),
  _QuizOption('Brown', Color(0xFF5A4A41)),
  _QuizOption('Blonde', Color(0xFFB1A28A)),
  _QuizOption('Reddish', Color(0xFF8C3E21)),
];

const _step3Options = [
  _QuizOption('A few', Color(0xFF3A3837)),
  _QuizOption('Fair amount', Color(0xFF6F6A65)),
  _QuizOption('A lot', Color(0xFF9A9692)),
];

List<_QuizOption> _step2OptionsFor(String? base) {
  switch (base) {
    case 'Black':
      return const [
        _QuizOption('Natural black', Color(0xFF151515)),
        _QuizOption('Soft black', Color(0xFF2E2B2A)),
        _QuizOption('Blue-black', Color(0xFF0D1B2A)),
      ];
    case 'Brown':
      return const [
        _QuizOption('Light brown', Color(0xFF7D6148)),
        _QuizOption('Medium brown', Color(0xFF5A4A41)),
        _QuizOption('Dark brown', Color(0xFF3E2F26)),
      ];
    case 'Blonde':
      return const [
        _QuizOption('Light blonde', Color(0xFFEDE0C8)),
        _QuizOption('Dark blonde', Color(0xFF9E8F7A)),
        _QuizOption('Golden blonde', Color(0xFFC9A574)),
      ];
    case 'Reddish':
      return const [
        _QuizOption('Auburn', Color(0xFF6B3A2E)),
        _QuizOption('Copper', Color(0xFFB87333)),
        _QuizOption('Ginger', Color(0xFF8C3E21)),
      ];
    default:
      return const [
        _QuizOption('Light Brown', Color(0xFF332D28)),
        _QuizOption('Dark Blond', Color(0xFF575048)),
        _QuizOption('Light Blond', Color(0xFF9E8F7A)),
      ];
  }
}

class MensShadeMatcher extends StatefulWidget {
  const MensShadeMatcher({super.key});

  @override
  State<MensShadeMatcher> createState() => _MensShadeMatcherState();
}

class _MensShadeMatcherState extends State<MensShadeMatcher> {
  int _step = 1;
  String? _baseColor;
  String? _specificShade;
  String? _grayAmount;
  String? _currentSelection;

  void _openHairTryOn() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const HairColorTryOnScreen(),
      ),
    );
  }

  void _next() {
    if (_currentSelection == null && _step < 4) return;
    setState(() {
      if (_step == 1) _baseColor = _currentSelection;
      if (_step == 2) _specificShade = _currentSelection;
      if (_step == 3) _grayAmount = _currentSelection;
      _step++;
      _currentSelection = null;
    });
  }

  void _back() {
    if (_step == 1) {
      Navigator.pop(context);
    } else {
      setState(() {
        _step--;
        if (_step == 1) _currentSelection = _baseColor;
        if (_step == 2) _currentSelection = _specificShade;
        if (_step == 3) _currentSelection = _grayAmount;
      });
    }
  }

  Color _accentFromQuiz() {
    for (final o in _step2OptionsFor(_baseColor)) {
      if (o.label == _specificShade) return o.color;
    }
    return _orange;
  }

  String _recommendationTitle() {
    final gray = _grayAmount ?? '';
    if (gray == 'A lot') {
      return 'Full coverage colour';
    }
    if (gray == 'Fair amount') {
      return 'Blend & cover range';
    }
    return 'Natural depth refresh';
  }

  String _recommendationBody() {
    final base = _baseColor ?? 'your base';
    final tone = _specificShade ?? 'tone';
    final gray = _grayAmount ?? 'some';
    return 'For $base hair leaning $tone with $gray visible gray, '
        'choose a demi-permanent or permanent line one level deeper than '
        'your lengths for even coverage, then use the live hair try-on to '
        'preview tones on camera before you buy.';
  }

  @override
  Widget build(BuildContext context) {
    if (_step == 4) return _buildResult();

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                    onPressed: _back,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 26),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: LayoutBuilder(
                builder: (context, c) {
                  return Stack(
                    children: [
                      Container(height: 3, width: c.maxWidth, color: Colors.white30),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 3,
                        width: c.maxWidth * (_step.clamp(1, 3) / 3.0),
                        color: _orange,
                      ),
                    ],
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              color: _bg,
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '0$_step',
                        style: const TextStyle(
                          color: _orange,
                          fontSize: 64,
                          fontWeight: FontWeight.w600,
                          height: 0.9,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 4, left: 8),
                        child: Text(
                          '/ 03',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _getTitle(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _getSubtitle(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: _white,
                width: double.infinity,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: _getOptions().map((opt) {
                            final isSelected = _currentSelection == opt.label;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => setState(() => _currentSelection = opt.label),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected ? _orange : const Color(0xFFE0E0E0),
                                        width: isSelected ? 3 : 1,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        SizedBox(
                                          height: 88,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              ColoredBox(color: opt.color),
                                              CustomPaint(painter: _HairPainter()),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          color: isSelected ? _orange : Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          alignment: Alignment.center,
                                          child: Text(
                                            opt.label,
                                            style: TextStyle(
                                              color: isSelected ? Colors.black : Colors.black87,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      if (_step == 2 && _currentSelection != null)
                        _buildExpertTip(
                          'If you were born blonde but your hair has darkened over the years, '
                          'pick the lighter swatch — you can fine-tune in live try-on.',
                        ),
                      if (_step == 3 && _currentSelection == 'Fair amount')
                        _buildExpertTip(
                          'Roughly 20–40% gray often shows first at temples and crown — '
                          'a neutral-nuance permanent line usually covers evenly.',
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 64,
              child: Row(
                children: [
                  if (_step == 2)
                    Expanded(
                      child: InkWell(
                        onTap: _openHairTryOn,
                        child: Container(
                          color: Colors.black,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: const Text(
                            'UNSURE?\nTRY LIVE',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              letterSpacing: 0.8,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        if (_currentSelection != null) _next();
                      },
                      child: Container(
                        color: _orange,
                        alignment: Alignment.center,
                        child: Text(
                          _step == 3 ? 'FIND MY SHADE' : 'CONTINUE',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpertTip(String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: _orange,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'EXPERT TIPS',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final accent = _accentFromQuiz();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Text(
                _recommendationTitle(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_baseColor ?? ''} · ${_specificShade ?? ''} · ${_grayAmount ?? ''} gray',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 28),
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withValues(alpha: 0.35),
                      accent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const Icon(Icons.brush_rounded, size: 72, color: Colors.white),
              ),
              const SizedBox(height: 28),
              Text(
                _recommendationBody(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _openHairTryOn,
                  style: FilledButton.styleFrom(
                    backgroundColor: _orange,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text(
                    'PREVIEW ON CAMERA',
                    style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.6),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  setState(() {
                    _step = 1;
                    _baseColor = null;
                    _specificShade = null;
                    _grayAmount = null;
                    _currentSelection = null;
                  });
                },
                child: const Text('Start quiz again'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  String _getTitle() {
    switch (_step) {
      case 1:
        return 'How would you\ndescribe your natural\nhair color?';
      case 2:
        final base = _baseColor ?? 'your';
        return '$base it is. But which\nkind of ${base.toLowerCase()}?';
      case 3:
        return 'So, about those grays\n- how much do you\nhave?';
      default:
        return '';
    }
  }

  String _getSubtitle() {
    switch (_step) {
      case 1:
        return 'If you already have some grays, use your eyebrows as a guide for your natural depth.';
      case 2:
        final depth = (_baseColor ?? 'natural').toLowerCase();
        return 'Pick the swatch closest to your $depth roots. If you hesitate between two, choose the lighter one — you can refine in live try-on.';
      case 3:
        return 'Rough estimate is fine — we only use this to suggest coverage level.';
      default:
        return '';
    }
  }

  List<_QuizOption> _getOptions() {
    switch (_step) {
      case 1:
        return _step1Options;
      case 2:
        return _step2OptionsFor(_baseColor);
      case 3:
        return _step3Options;
      default:
        return [];
    }
  }
}

class _HairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (var i = 0.0; i < size.width; i += 3) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
