// lib/screens/mens_shade_matcher_screen.dart
import 'package:flutter/material.dart';

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

const _step2Options = [
  _QuizOption('Light Brown', Color(0xFF332D28)),
  _QuizOption('Dark Blond',  Color(0xFF575048)),
  _QuizOption('Light Blond', Color(0xFF9E8F7A)),
];

const _step3Options = [
  _QuizOption('A few',       Color(0xFF3A3837)),
  _QuizOption('Fair amount', Color(0xFF6F6A65)),
  _QuizOption('A lot',       Color(0xFF9A9692)),
];

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

  @override
  Widget build(BuildContext context) {
    if (_step == 4) return _buildResult();

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            // App bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Stack(
                children: [
                  Container(height: 3, color: Colors.white30),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 3,
                    width: MediaQuery.of(context).size.width * (_step / 3.0),
                    color: _orange,
                  )
                ],
              ),
            ),
            // Top Content
            Container(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 30),
              color: _bg,
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
                          fontSize: 72,
                          fontWeight: FontWeight.w600,
                          height: 0.9,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6, left: 8),
                        child: Text(
                          '/ 03',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text(
                    _getTitle(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _getSubtitle(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            // Bottom White Area
            Expanded(
              child: Container(
                color: _white,
                width: double.infinity,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 30),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: _getOptions().map((opt) {
                            bool isSelected = _currentSelection == opt.label;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _currentSelection = opt.label),
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: isSelected ? Border.all(color: _orange, width: 3) : Border.all(color: Colors.white, width: 3),
                                  ),
                                  child: Column(
                                    children: [
                                      Container(
                                        height: 150,
                                        color: opt.color,
                                        // Adding a subtle gradient noise pattern effect to look like hair flow
                                        child: CustomPaint(painter: _HairPainter()),
                                      ),
                                      Container(
                                        color: isSelected ? _orange : Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        alignment: Alignment.center,
                                        child: Text(
                                          opt.label,
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      // Expert Tips
                      if (_step == 2 && _currentSelection != null)
                         _buildExpertTip('If you were born blonde but your hair has\ndarkened over the years, this is the shade for you!'),
                      if (_step == 3 && _currentSelection == 'Fair amount')
                         _buildExpertTip("If you fall into this category, you've got 20-40%\ngray hair with visible patches, most likely around\nthe temples and crown."),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),
            // Bottom Bar Button
            SizedBox(
              height: 64,
              child: Row(
                children: [
                  if (_step == 2)
                    Expanded(
                      flex: 1,
                      child: GestureDetector(
                        onTap: () {
                          // Unsure try it on logic
                        },
                        child: Container(
                          color: Colors.black,
                          alignment: Alignment.center,
                          child: const Text(
                            'UNSURE ? TRY IT\nON',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    flex: 1,
                    child: GestureDetector(
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
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildExpertTip(String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Container(
        width: double.infinity,
        color: _orange,
        padding: const EdgeInsets.all(24),
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
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/mens_one_twist.png', height: 320),
            const SizedBox(height: 40),
            const Text(
              'Men Expert',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'One-Twist',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Permanent Hair Color',
              style: TextStyle(
                fontSize: 22,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.star, color: _orange, size: 28),
                const Icon(Icons.star, color: _orange, size: 28),
                const Icon(Icons.star, color: _orange, size: 28),
                const Icon(Icons.star, color: _orange, size: 28),
                const Icon(Icons.star_border, color: _orange, size: 28),
                const SizedBox(width: 12),
                const Text(
                  '4.1/5',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  String _getTitle() {
    switch (_step) {
      case 1: return 'How would you\ndescribe your natural\nhair color?';
      case 2: 
        String base = _baseColor ?? 'Blonde';
        return '$base it is. But which\nkind of ${base.toLowerCase()}?';
      case 3: return 'So, about those grays\n- how much do you\nhave?';
      default: return '';
    }
  }

  String _getSubtitle() {
    switch (_step) {
      case 1: return 'If you already have some grays, this might be tricky to\nidentify. Refer to your eyebrows for your natural color.';
      case 2: 
        String base = (_baseColor ?? 'Blonde').toLowerCase();
        return 'There are different types of $base shades, some\ndarker, some lighter. Choose the shade of $base that\nbest matches your natural hair color. If you hesitate\nbetween 2 shades, choose the lightest one.';
      case 3: return 'No worries, you don\'t have to count every gray hair! All\nwe need is your rough estimation.';
      default: return '';
    }
  }

  List<_QuizOption> _getOptions() {
    switch (_step) {
      case 1: return _step1Options;
      case 2: return _step2Options;
      case 3: return _step3Options;
      default: return [];
    }
  }
}

class _HairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Add subtle vertical lines to simulate hair texture
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.15)
      ..strokeWidth = 1.0;
    for (double i = 0; i < size.width; i += 3) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
