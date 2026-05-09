import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'order_history_screen.dart';

const _bgTop = Color(0xFFF5F5F5);
const _bgMid = Color(0xFFF1ABAD);
const _bgBot = Color(0xFFF7BDBD);
const _ink = Color(0xFF121212);
const _fieldFill = Color(0xFFF2C9CC);
const _fieldBorder = Color(0xFFE5AFB4);
const _maroon = Color(0xFF9A130B);

class ProfileScreen extends StatelessWidget {
  final bool showBackButton;
  final VoidCallback? onBack;
  const ProfileScreen({super.key, this.showBackButton = false, this.onBack});

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logged out successfully'),
        backgroundColor: Color(0xFF1F8A43),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = (user?.displayName?.trim().isNotEmpty ?? false) ? user!.displayName!.trim() : 'Melissa Peters';
    final email = user?.email ?? 'melpeters@gmail.com';
    final avatar = user?.photoURL;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bgTop, _bgMid, _bgBot],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          children: [
            SizedBox(
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (showBackButton)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: () {
                          if (onBack != null) {
                            onBack!();
                          } else {
                            Navigator.of(context).maybePop();
                          }
                        },
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _ink),
                      ),
                    ),
                  const Text(
                    'Profile',
                    style: TextStyle(fontSize: 40 / 2, fontWeight: FontWeight.w800, color: _ink),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: CircleAvatar(
                radius: 54,
                backgroundColor: const Color(0xFF5C4FA1),
                child: CircleAvatar(
                  radius: 52,
                  backgroundImage: avatar != null && avatar.isNotEmpty
                      ? NetworkImage(avatar)
                      : const NetworkImage('https://images.unsplash.com/photo-1524504388940-b1c1722653e1?w=300'),
                ),
              ),
            ),
            const SizedBox(height: 22),
            _label('Name'),
            _readOnlyField(name),
            const SizedBox(height: 12),
            _label('Email'),
            _readOnlyField(email),
            const SizedBox(height: 12),
            _label('Password'),
            _readOnlyField('************'),
            const SizedBox(height: 12),
            _label('Date of Birth'),
            _readOnlyField('23/05/1995'),
            const SizedBox(height: 12),
            _label('Country/Region'),
            _readOnlyField('Sri Lanka'),
            const SizedBox(height: 24),
            Material(
              color: _fieldFill,
              borderRadius: BorderRadius.circular(7),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const Icon(Icons.receipt_long_outlined, color: _maroon),
                title: const Text(
                  'My orders & tracking',
                  style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
                ),
                subtitle: Text(
                  'View history and delivery status',
                  style: TextStyle(fontSize: 13, color: _ink.withValues(alpha: 0.55)),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, color: _ink),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => OrderHistoryScreen(showBackButton: true),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: SizedBox(
                width: 126,
                height: 42,
                child: FilledButton(
                  onPressed: () => _logout(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: _maroon,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: Color(0xFFE06D6D), width: 1.6),
                    ),
                  ),
                  child: const Text(
                    'Logout',
                    style: TextStyle(fontSize: 30 / 2, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _label(String t) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Text(
        t,
        style: const TextStyle(fontSize: 17 / 1.1, fontWeight: FontWeight.w700, color: _ink),
      ),
    );
  }

  static Widget _readOnlyField(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: _fieldFill,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _fieldBorder),
      ),
      child: Text(
        value,
        style: const TextStyle(fontSize: 17 / 1.1, fontWeight: FontWeight.w600, color: Color(0xFF4A4A4A)),
      ),
    );
  }
}
