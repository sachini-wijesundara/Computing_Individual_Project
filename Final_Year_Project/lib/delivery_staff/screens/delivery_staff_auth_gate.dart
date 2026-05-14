import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/delivery_staff_service.dart';
import 'delivery_staff_home_screen.dart';
import 'delivery_staff_login_screen.dart';

class DeliveryStaffAuthGate extends StatelessWidget {
  const DeliveryStaffAuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = authSnap.data;
        if (user == null) {
          return const DeliveryStaffLoginScreen();
        }

        return StreamBuilder(
          stream: DeliveryStaffService.instance.currentProfileStream(
            forUid: user.uid,
          ),
          builder: (context, snap) {
            if (snap.hasError) {
              return _blockedScaffold(
                context,
                message:
                    'Could not verify delivery profile.\n${snap.error}\n\nPlease contact admin.',
              );
            }
            if (!snap.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final doc = snap.data;
            if (doc == null || !doc.exists) {
              return _blockedScaffold(
                context,
                message:
                    'No profile found. Contact admin to create delivery-staff account.',
              );
            }
            final data = doc.data() ?? const <String, dynamic>{};
            final role = (data['role'] ?? '').toString().toLowerCase();
            final disabled =
                data['disabled'] == true ||
                data['isDisabled'] == true ||
                data['isActive'] == false;
            if (role != 'delivery_staff') {
              return _blockedScaffold(
                context,
                message: 'This account is not assigned as delivery staff.',
              );
            }
            if (disabled) {
              return _blockedScaffold(
                context,
                message: 'Your delivery account is disabled. Contact admin.',
              );
            }
            return const DeliveryStaffHomeScreen();
          },
        );
      },
    );
  }

  Widget _blockedScaffold(BuildContext context, {required String message}) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Staff'),
        actions: [
          TextButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            child: const Text('Logout'),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }
}
