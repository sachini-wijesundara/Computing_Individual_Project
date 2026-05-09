import 'package:flutter/material.dart';

import 'firebase/firebase_config.dart';
import 'screens/admin/admin_gate_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await FirebaseConfig.initialize();
    debugPrint('✅ Firebase initialized (admin web)');
  } catch (e, st) {
    debugPrint('⚠️ Firebase init error (admin web): $e');
    debugPrint('$st');
  }
  runApp(const _AdminWebApp());
}

class _AdminWebApp extends StatelessWidget {
  const _AdminWebApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'La Vogue Vista Admin',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C150D)),
        useMaterial3: true,
      ),
      home: const AdminGateScreen(),
      routes: {
        '/admin': (_) => const AdminGateScreen(),
      },
    );
  }
}
