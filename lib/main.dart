import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/camera_screen.dart';
import 'screens/gallery_screen.dart';
import 'screens/live_tryon_screen.dart';
import 'screens/ai_beauty_assistant_screen.dart';
import 'screens/product_showcase_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/dashboard_screen.dart';
import 'providers/makeup_provider.dart';
import 'providers/auth_provider.dart';
import 'firebase/firebase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseConfig.initialize();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AuthProvider()),
        ChangeNotifierProvider(create: (context) => MakeupProvider()),
      ],
      child: MaterialApp(
        title: 'Loreal VogueVista',
      theme: ThemeData(
              primarySwatch: Colors.brown,
              primaryColor: Color(0xFF8B0000), // Dark maroon
              colorScheme: ColorScheme.fromSeed(
                seedColor: Color(0xFF8B0000),
                secondary: Color(0xFFB8860B), // Metallic gold
              ),
              scaffoldBackgroundColor: Color(0xFFF5E6E8), // Light peach background
              appBarTheme: AppBarTheme(
                backgroundColor: Color(0xFF8B0000), // Dark maroon
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              visualDensity: VisualDensity.adaptivePlatformDensity,
            ),
        home: AuthWrapper(),
        routes: {
          '/onboarding': (context) => OnboardingScreen(),
          '/login': (context) => SignInPage(),
          '/signup': (context) => SignUpEmailPage(),
          '/dashboard': (context) => DashboardScreen(),
          '/camera': (context) => CameraScreen(),
          '/gallery': (context) => GalleryScreen(),
          '/live_tryon': (context) => LiveTryOnScreen(),
          '/ai_assistant': (context) => AIBeautyAssistantScreen(),
          '/products': (context) => ProductShowcaseScreen(),
        },
      ),
    );
  }
}

class MainScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.pink.shade100,
              Colors.purple.shade100,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // App Logo/Icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFFE91E63), Color(0xFFFF4081)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFFE91E63).withOpacity(0.3),
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/logo.png',
                      width: 100,
                      height: 100,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.face_retouching_natural,
                          size: 60,
                          color: Colors.white,
                        );
                      },
                    ),
                  ),
                ),
                SizedBox(height: 30),
                
                // App Title
                Text(
                  'LW',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB8860B), // Metallic gold/bronze
                    letterSpacing: 2,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),

                Text(
                  'LOREAL VOGUE VISTA',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB8860B), // Metallic gold/bronze
                    letterSpacing: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 10),
                
                Text(
                  'Try any makeup, before buying',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 50),
                
                // Main Action Buttons
                  _buildActionButton(
                    context,
                    icon: Icons.camera_alt,
                    title: 'Live Try-On',
                    subtitle: 'Real-time AR makeup',
                    onTap: () => Navigator.pushNamed(context, '/live_tryon'),
                    color: Color(0xFF8B0000), // Dark maroon
                  ),
                  SizedBox(height: 20),

                  _buildActionButton(
                    context,
                    icon: Icons.shopping_bag,
                    title: 'Product Showcase',
                    subtitle: 'Browse and try products',
                    onTap: () => Navigator.pushNamed(context, '/products'),
                    color: Color(0xFF8B0000), // Dark maroon
                  ),
                  SizedBox(height: 20),

                  _buildActionButton(
                    context,
                    icon: Icons.face_retouching_natural,
                    title: 'AI Beauty Assistant',
                    subtitle: 'Get personalized recommendations',
                    onTap: () => Navigator.pushNamed(context, '/ai_assistant'),
                    color: Color(0xFF8B0000), // Dark maroon
                  ),
                  SizedBox(height: 20),

                  _buildActionButton(
                    context,
                    icon: Icons.photo_library,
                    title: 'Photo Try-On',
                    subtitle: 'Upload and try makeup',
                    onTap: () => Navigator.pushNamed(context, '/gallery'),
                    color: Color(0xFF8B0000), // Dark maroon
                  ),
                SizedBox(height: 30),
                
                // Status Indicator
                Consumer<MakeupProvider>(
                  builder: (context, makeupProvider, child) {
                    return Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            makeupProvider.isModelReady 
                              ? Icons.check_circle 
                              : Icons.hourglass_empty,
                            color: makeupProvider.isModelReady 
                              ? Colors.green 
                              : Colors.orange,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            makeupProvider.isModelReady 
                              ? 'Model Ready' 
                              : 'Training in Progress...',
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
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              spreadRadius: 2,
              blurRadius: 8,
              offset: Offset(0, 4),
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
              child: Icon(
                icon,
                color: color,
                size: 30,
              ),
            ),
            SizedBox(width: 20),
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
                  SizedBox(height: 4),
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
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey.shade400,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        if (authProvider.isLoading) {
          return Scaffold(
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFF5F5F5),
                    Color(0xFFEE8985),
                  ],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: Color(0xFF7B160D),
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Loading...',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        
        if (authProvider.isAuthenticated) {
          return DashboardScreen();
        } else {
          return OnboardingScreen();
        }
      },
    );
  }
}