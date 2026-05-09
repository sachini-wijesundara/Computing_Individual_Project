import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'delivery_staff/screens/delivery_staff_auth_gate.dart';
import 'firebase/firebase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseConfig.initialize();
  runApp(const DeliveryStaffApp());
}

class DeliveryStaffApp extends StatelessWidget {
  const DeliveryStaffApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Delivery Staff',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C150D)),
        scaffoldBackgroundColor: const Color(0xFFF7F2F1),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1E1A1A),
          elevation: 0.2,
        ),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return const DeliveryStaffAuthGate();
        },
      ),
    );
  }
}
