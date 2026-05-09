import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/delivery_staff_service.dart';

class DeliveryStaffProfileScreen extends StatelessWidget {
  const DeliveryStaffProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: StreamBuilder(
        stream: DeliveryStaffService.instance.currentProfileStream(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data?.data() ?? const <String, dynamic>{};
          final name =
              (data['displayName'] ?? data['staffName'] ?? 'Delivery Staff')
                  .toString();
          final email = (data['email'] ?? '').toString();
          final phone =
              (data['phone'] ?? data['customerPhone'] ?? '').toString();
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Delivery Staff',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _line('Name', name),
                    _line('Email', email.isEmpty ? '-' : email),
                    _line('Phone', phone.isEmpty ? '-' : phone),
                    _line('Role', 'delivery_staff'),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Logout'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE9DDDA)),
      ),
      child: child,
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Color(0xFF1E1A1A), fontSize: 13),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
