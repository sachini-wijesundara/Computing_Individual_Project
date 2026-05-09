import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../config/admin_panel_config.dart';
import '../../firebase/firebase_config.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _emailCtrl = TextEditingController(text: 'lavougevistaofficial@gmail.com');
  final _pwdCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _showPassword = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailCtrl.text.trim();
    final pwd = _pwdCtrl.text;
    if (email.isEmpty || pwd.isEmpty) return;
    if (!AdminPanelConfig.isAllowedAdminEmail(email)) {
      setState(() => _error = 'This email is not in admin allowlist.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!FirebaseConfig.isInitialized) {
        setState(() => _error = 'Firebase is not initialized for web yet.');
        return;
      }
      await FirebaseConfig.auth
          .signInWithEmailAndPassword(email: email, password: pwd);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Login failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const brandRed = Color(0xFF7C150D);
    const brandGold = Color(0xFFD4A843);
    const panel = Color(0xFF1F1A1A);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF140E0E), Color(0xFF2A1818), Color(0xFF0F0B0B)],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 18),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: panel.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0x33FFFFFF)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 24,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  child: Image.asset(
                    'assets/logo.png',
                    height: 58,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'La Vogue Vista',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: brandGold,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Admin Control Center',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _emailCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Admin Email',
                    labelStyle: const TextStyle(color: Color(0xFFDDD5D5)),
                    prefixIcon: const Icon(Icons.alternate_email_rounded, color: brandGold),
                    filled: true,
                    fillColor: const Color(0x26FFFFFF),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0x33FFFFFF)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: brandGold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pwdCtrl,
                  obscureText: !_showPassword,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: const TextStyle(color: Color(0xFFDDD5D5)),
                    prefixIcon: const Icon(Icons.lock_outline_rounded, color: brandGold),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        color: Colors.white70,
                      ),
                    ),
                    filled: true,
                    fillColor: const Color(0x26FFFFFF),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0x33FFFFFF)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: brandGold),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFFFB6B6),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _signIn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandRed,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.login_rounded),
                  label: Text(
                    _busy ? 'Signing in...' : 'Sign in to Admin Panel',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Only allowlisted admin accounts can access this panel.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFBBAEAE), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
