import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../firebase/firebase_config.dart';
import 'admin_shell_screen.dart';
import 'admin_login_screen.dart';

class AdminGateScreen extends StatelessWidget {
  const AdminGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!FirebaseConfig.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Firebase web config is missing.\n'
              'Admin web is open, but login/chat requires web Firebase options.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseConfig.auth.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snap.data;
        if (user == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Admin')),
            body: const AdminLoginScreen(),
          );
        }
        // Full-screen dashboard: avoid nesting a second Scaffold (refresh was showing
        // only the outer "Admin" app bar + an old-looking body layout).
        return const AdminShellScreen();
      },
    );
  }
}
