import 'package:flutter/material.dart';
import 'dart:async';

class OnboardingScreen extends StatefulWidget {
  @override
  _OnboardingScreenState createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _fadeController;
  
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<double> _fadeOpacity;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startOnboarding();
  }

  void _setupAnimations() {
    // Logo animation
    _logoController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _logoScale = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _logoController,
      curve: Curves.elasticOut,
    ));
    
    _logoOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _logoController,
      curve: Curves.easeInOut,
    ));

    // Text animation
    _textController = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _textOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: Curves.easeInOut,
    ));

    // Fade out animation
    _fadeController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );
    
    _fadeOpacity = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));
  }

  void _startOnboarding() async {
    // Start logo animation
    try {
      _logoController.forward();
    } catch (e) {
      // Controller might be disposed
    }
    
    // Wait 800ms then start text animation
    await Future.delayed(Duration(milliseconds: 800));
    try {
      _textController.forward();
    } catch (e) {
      // Controller might be disposed
    }
    
    // Wait 2.2 seconds then fade out
    await Future.delayed(Duration(milliseconds: 2200));
    try {
      _fadeController.forward();
    } catch (e) {
      // Controller might be disposed
    }
    
    // Wait 500ms then navigate to login
    await Future.delayed(Duration(milliseconds: 500));
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF5F5F5), // Light pink at top
              Color(0xFFEE8985), // More saturated pink at bottom
            ],
          ),
        ),
        child: AnimatedBuilder(
          animation: _fadeOpacity,
          builder: (context, child) {
            return Opacity(
              opacity: _fadeOpacity.value,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  // Logo Animation
                  AnimatedBuilder(
                    animation: _logoController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _logoScale.value,
                        child: Opacity(
                          opacity: _logoOpacity.value,
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 30,
                                  offset: Offset(0, 15),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/logo.png',
                                width: 200,
                                height: 200,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [Color(0xFFB8860B), Color(0xFFDAA520)],
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'LV',
                                        style: TextStyle(
                                          fontSize: 80,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: 4,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                    
                    SizedBox(height: 40),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// Custom painter for L and V monogram
class LVMonogramPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Color(0xFFD4AF37) // Gold color
      ..style = PaintingStyle.fill
      ..strokeWidth = 4;

    // Draw L
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.1, size.height * 0.1, size.width * 0.15, size.height * 0.7),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.1, size.height * 0.7, size.width * 0.4, size.height * 0.15),
      paint,
    );
    
    // Draw V
    final vPath = Path();
    vPath.moveTo(size.width * 0.6, size.height * 0.1);
    vPath.lineTo(size.width * 0.7, size.height * 0.8);
    vPath.lineTo(size.width * 0.8, size.height * 0.1);
    vPath.close();
    canvas.drawPath(vPath, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
