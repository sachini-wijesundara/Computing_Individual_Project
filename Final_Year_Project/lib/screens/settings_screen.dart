import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'edit_profile_screen.dart';
import 'order_history_screen.dart';
import 'user_feedback_screen.dart';
import 'wishlist_screen.dart';
import '../services/firebase_auth_service.dart';

const _bgTop = Color(0xFFF5F5F5);
const _bgMid = Color(0xFFF1ABAD);
const _bgBot = Color(0xFFF7BDBD);
const _cardAccount = Color(0xFFEEE8EB);
const _cardCache = Color(0xFFF0E2E6);
const _cardAction = Color(0xFFEFDDE2);
const _textDark = Color(0xFF171717);
const _iconMuted = Color(0xFF5F5A5D);

class SettingsScreen extends StatefulWidget {
  final bool showBackButton;
  final VoidCallback? onBack;
  const SettingsScreen({super.key, this.showBackButton = false, this.onBack});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifications = true;
  bool _dataSaver = false;
  bool _privateProfile = false;
  bool _savingToggles = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> _loadSettings() async {
    final uid = _uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!mounted || !doc.exists) return;
    final d = doc.data() ?? const <String, dynamic>{};
    setState(() {
      _notifications = (d['notifications'] as bool?) ?? true;
      _dataSaver = (d['dataSaver'] as bool?) ?? false;
      _privateProfile = (d['privateProfile'] as bool?) ?? false;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _saveToggle({
    bool? notifications,
    bool? dataSaver,
    bool? privateProfile,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    if (_savingToggles) return;
    _savingToggles = true;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        if (notifications != null) 'notifications': notifications,
        if (dataSaver != null) 'dataSaver': dataSaver,
        if (privateProfile != null) 'privateProfile': privateProfile,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } finally {
      _savingToggles = false;
    }
  }

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuthService.signOut();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logged out successfully'),
        backgroundColor: Color(0xFF1F8A43),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _security(BuildContext context) async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email found for this account.')),
      );
      return;
    }
    try {
      await FirebaseAuthService.resetPassword(email);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password reset email sent to $email'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send reset email: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bgTop, _bgMid, _bgBot],
          stops: [0.0, 0.58, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: widget.showBackButton
                        ? IconButton(
                            onPressed: () {
                              if (widget.onBack != null) {
                                widget.onBack!();
                              } else {
                                Navigator.of(context).maybePop();
                              }
                            },
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _textDark),
                          )
                        : const SizedBox(width: 48, height: 48),
                  ),
                  const Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 40 / 2,
                      fontWeight: FontWeight.w800,
                      color: _textDark,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                children: [
                  const _SectionTitle('Account'),
                  _SettingsGroup(
                    color: _cardAccount.withValues(alpha: 0.78),
                    tiles: [
                      _SettingsTile(
                        icon: Icons.person_outline_rounded,
                        label: 'Edit profile',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const EditProfileScreen(),
                          ),
                        ),
                      ),
                      _SettingsTile(
                        icon: Icons.local_shipping_outlined,
                        label: 'Orders & tracking',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const OrderHistoryScreen(showBackButton: true),
                          ),
                        ),
                      ),
                      _SettingsTile(
                        icon: Icons.favorite_outline_rounded,
                        label: 'Wishlist',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const WishlistScreen(showBackButton: true),
                          ),
                        ),
                      ),
                      _SettingsTile(
                        icon: Icons.security_rounded,
                        label: 'Security (reset password)',
                        onTap: () => _security(context),
                      ),
                      _SettingsToggleTile(
                        icon: Icons.notifications_none_rounded,
                        label: 'Notifications',
                        value: _notifications,
                        onChanged: (v) {
                          setState(() => _notifications = v);
                          _saveToggle(notifications: v);
                        },
                      ),
                      _SettingsToggleTile(
                        icon: Icons.lock_outline_rounded,
                        label: 'Privacy',
                        value: _privateProfile,
                        onChanged: (v) {
                          setState(() => _privateProfile = v);
                          _saveToggle(privateProfile: v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const _SectionTitle('Cache & cellular'),
                  _SettingsGroup(
                    color: _cardCache.withValues(alpha: 0.82),
                    tiles: [
                      _SettingsTile(
                        icon: Icons.feedback_outlined,
                        label: 'Feedback',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const UserFeedbackScreen(),
                          ),
                        ),
                      ),
                      _SettingsToggleTile(
                        icon: Icons.data_saver_off_rounded,
                        label: 'Data Saver',
                        value: _dataSaver,
                        onChanged: (v) {
                          setState(() => _dataSaver = v);
                          _saveToggle(dataSaver: v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const _SectionTitle('Actions'),
                  _SettingsGroup(
                    color: _cardAction.withValues(alpha: 0.82),
                    tiles: [
                      _SettingsTile(
                        icon: Icons.group_add_outlined,
                        label: 'Add account',
                        onTap: () => _logout(context),
                      ),
                      _SettingsTile(
                        icon: Icons.logout_rounded,
                        label: 'Log out',
                        onTap: () => _logout(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 32 / 2,
          fontWeight: FontWeight.w800,
          color: _textDark,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final Color color;
  final List<Widget> tiles;
  const _SettingsGroup({required this.color, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(children: tiles),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12.5),
        child: Row(
          children: [
            Icon(icon, color: _iconMuted, size: 27),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 33 / 2,
                  fontWeight: FontWeight.w700,
                  color: _textDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsToggleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggleTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: _iconMuted, size: 27),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 33 / 2,
                fontWeight: FontWeight.w700,
                color: _textDark,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: _textDark,
            activeTrackColor: _textDark.withValues(alpha: 0.35),
          ),
        ],
      ),
    );
  }
}
