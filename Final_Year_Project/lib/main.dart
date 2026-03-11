import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/camera_screen.dart';
import 'screens/gallery_screen.dart';
import 'screens/live_tryon_screen.dart';
import 'screens/ai_beauty_assistant_screen.dart';
import 'screens/product_showcase_screen.dart';
import 'screens/onboarding_screen.dart';
import 'utils/fix_shades.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/dashboard_screen.dart';

import 'providers/makeup_provider.dart';
import 'providers/auth_provider.dart';

import 'firebase/firebase_config.dart';
import 'services/firestore_service.dart'; // exposes seedAllProductsOnce()
import 'utils/seed_products.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await FirebaseConfig.initialize();
    debugPrint('✅ Firebase initialized successfully');
  } catch (e, stackTrace) {
    debugPrint('⚠️ Firebase initialization error: $e');
    debugPrint('Stack trace: $stackTrace');
    // Continue anyway - app may work without Firebase features
  }

  // Best-effort seed (adds only missing SKUs) - never crash on failure
  try {
    await seedAllProductsOnce();
    debugPrint('✅ Products seeded successfully');
  } catch (e) {
    debugPrint('ℹ️ Seed skipped (Firestore not available): $e');
  }

  runApp(MyApp()); // <-- not const to avoid “const constructor” lints
}

class MyApp extends StatelessWidget {
  MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => MakeupProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'La Vogue Vista',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8B0000),
            primary: const Color(0xFF8B0000),
            secondary: const Color(0xFFB8860B),
          ),
          scaffoldBackgroundColor: const Color(0xFFF5E6E8),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF8B0000),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: AuthWrapper(), // not const
        routes: {
          '/onboarding': (_) => OnboardingScreen(),
          '/login': (_) => SignInPage(),
          '/signup': (_) => SignUpEmailPage(),
          '/dashboard': (_) => DashboardPage(),
          '/camera': (_) => CameraScreen(),
          '/gallery': (_) => GalleryScreen(),
          '/live_tryon': (_) => LiveTryOnScreen(),
          '/ai_assistant': (_) => AIBeautyAssistantScreen(),
          '/products': (_) => ProductShowcaseScreen(),
        },
      ),
    );
  }
}

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.pink.shade100, Colors.purple.shade100],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE91E63), Color(0xFFFF4081)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE91E63).withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.face_retouching_natural,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  'LW',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB8860B),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'LA VOGUE VISTA',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB8860B),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Try any makeup, before buying',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 50),
                _buildActionButton(
                  context,
                  icon: Icons.camera_alt,
                  title: 'Live Try-On',
                  subtitle: 'Real-time AR makeup',
                  onTap: () => Navigator.push(
                    context,
                    LiveTryOnScreen.route(
                      productName: 'Global Try-On',
                      productImage: 'assets/face.png',
                    ),
                  ),
                  color: const Color(0xFF8B0000),
                ),
                const SizedBox(height: 20),
                _buildActionButton(
                  context,
                  icon: Icons.shopping_bag,
                  title: 'Product Showcase',
                  subtitle: 'Browse and try products',
                  onTap: () => Navigator.pushNamed(context, '/products'),
                  color: const Color(0xFF8B0000),
                ),
                const SizedBox(height: 20),
                _buildActionButton(
                  context,
                  icon: Icons.face_retouching_natural,
                  title: 'AI Beauty Assistant',
                  subtitle: 'Get personalized recommendations',
                  onTap: () => Navigator.pushNamed(context, '/ai_assistant'),
                  color: const Color(0xFF8B0000),
                ),
                const SizedBox(height: 20),
                _buildActionButton(
                  context,
                  icon: Icons.photo_library,
                  title: 'Photo Try-On',
                  subtitle: 'Upload and try makeup',
                  onTap: () => Navigator.pushNamed(context, '/gallery'),
                  color: const Color(0xFF8B0000),
                ),
                const SizedBox(height: 20),
                // FIX SHADES Button
                ElevatedButton.icon(
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Updating Firebase shades...')),
                    );
                    try {
                      await fixAllProductShades();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✅ Shades updated! Check Firebase console.'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('❌ Error: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.build_circle),
                  label: const Text('FIX SHADES NOW'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                const SizedBox(height: 30),
                Consumer<MakeupProvider>(
                  builder: (_, p, __) {
                    final ready = p.isModelReady;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            ready ? Icons.check_circle : Icons.hourglass_empty,
                            color: ready ? Colors.green : Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            ready ? 'Model Ready' : 'Training in Progress...',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
        required VoidCallback onTap,
        required Color color,
      }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              spreadRadius: 2,
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                color: Colors.grey.shade400, size: 16),
          ],
        ),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (_, auth, __) {
        if (auth.isLoading) {
          return Scaffold(
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF5F5F5), Color(0xFFEE8985)],
                ),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF7B160D)),
                    SizedBox(height: 20),
                    Text('Loading...',
                        style: TextStyle(fontSize: 18, color: Colors.black87)),
                  ],
                ),
              ),
            ),
          );
        }
        return auth.isAuthenticated ? DashboardPage() : OnboardingScreen();
      },
    );
  }
}
