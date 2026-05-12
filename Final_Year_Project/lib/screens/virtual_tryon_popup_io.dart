import 'package:flutter/material.dart';
import 'full_makeup_screen.dart';
import 'hair_color_tryon_screen.dart';
import 'selfie_capture_screen.dart';

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
                  'Try makeup live or on a photo, or preview hair colours with our AI camera.',
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
                    // Makeup — live camera
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
                            Icon(Icons.face_retouching_natural_rounded, size: 20),
                            SizedBox(width: 8),
                            Text('Makeup — Live try-on',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Makeup — selfie mode (capture → use / retake → then try-on)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () async {
                          final path = await SelfieCaptureScreen.capture(context);
                          if (!context.mounted || path == null) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => FullMakeupTryOnScreen(
                                mode: TryOnMode.selfie,
                                initialSelfiePath: path,
                              ),
                            ),
                          );
                        },
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
                            Icon(Icons.camera_alt_outlined, size: 20),
                            SizedBox(width: 8),
                            Text('Makeup — Selfie mode',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Hair colour try-on
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const HairColorTryOnScreen(),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _maroon,
                          side: const BorderSide(color: _maroon, width: 1.8),
                          backgroundColor: Colors.white.withValues(alpha: 0.75),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.brush_rounded, size: 20),
                            SizedBox(width: 8),
                            Text('Hair color try-on',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w800)),
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
