import 'package:flutter/material.dart';
import 'full_makeup_screen.dart';
import 'nail_tryon_landing.dart';

// ── Brand colours ──────────────────────────────────────────────────────────────
const _maroon  = Color(0xFF7C150D);
const _roseTop = Color(0xFFF8E4E4);
const _roseMid = Color(0xFFEBABAD);
const _roseBot = Color(0xFFD47070);

/// Full-screen virtual try-on landing page (shown from nav bar).
/// Matches the La Vogue Vista "VIRTUAL TRY-ON" brand screen.
class VirtualTryOnLandingPage extends StatelessWidget {
  const VirtualTryOnLandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_roseTop, _roseMid, _roseBot],
            stops: [0.0, 0.65, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Close button ───────────────────────────────────────────────
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 12),
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: _maroon, size: 26),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),

              // ── Logo + brand name ──────────────────────────────────────────
              const Spacer(),
              _BrandLogo(),
              const SizedBox(height: 12),
              const Text(
                'LA VOGUE VISTA',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: _maroon,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 40),

              // ── Tagline ────────────────────────────────────────────────────
              const Text(
                'VIRTUAL TRY - ON',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _maroon,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'Try on any product instantly with our AI-powered camera.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: _maroon, height: 1.5),
                ),
              ),
              const Spacer(),

              // ── Action buttons ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    // Live Try-ON
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const FullMakeupTryOnScreen(mode: TryOnMode.live),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _maroon,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 4,
                          shadowColor: _maroon.withValues(alpha: 0.4),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt_rounded, size: 20),
                            SizedBox(width: 8),
                            Text('Live Try-ON',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Upload Photo
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const FullMakeupTryOnScreen(mode: TryOnMode.uploadPhoto),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _maroon,
                          side: const BorderSide(color: _maroon, width: 1.8),
                          backgroundColor: Colors.white.withValues(alpha: 0.55),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.photo_library_outlined, size: 20),
                            SizedBox(width: 8),
                            Text('Upload Photo',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Nail try-on (hand photo or live camera)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => showNailTryOnEntry(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _maroon,
                          side: BorderSide(color: _maroon.withValues(alpha: 0.85), width: 1.8),
                          backgroundColor: Colors.white.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.auto_awesome_outlined, size: 20),
                            SizedBox(width: 8),
                            Text('Nail try-on',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Brand logo widget (monogram LW in a circle) ───────────────────────────────
class _BrandLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.4),
        border: Border.all(color: _maroon.withValues(alpha: 0.3), width: 2),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Stylised "LW" monogram drawn with text
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [_maroon, Color(0xFFB84A4A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: const Text(
                'LW',
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -4,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
