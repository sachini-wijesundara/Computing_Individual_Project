import 'package:flutter/material.dart';
import '../../services/firebase_auth_service.dart';

// STEP 1: Email-first screen
class SignUpEmailPage extends StatefulWidget {
  const SignUpEmailPage({super.key});

  @override
  State<SignUpEmailPage> createState() => _SignUpEmailPageState();
}

class _SignUpEmailPageState extends State<SignUpEmailPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  bool _isBusy = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _goNext() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SignUpDetailsPage(email: _emailController.text.trim()),
      ),
    );
  }

  Future<void> _signUpWithGoogle() async {
    setState(() => _isBusy = true);
    try {
      await FirebaseAuthService.signInWithGoogle();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/dashboard');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5F5F5), Color(0xFFEE8985)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: size.height * 0.04),
                Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.face_retouching_natural, size: 56, color: Colors.black54),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'Create Account',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.grey.shade900),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Enter your email to continue',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                ),
                const SizedBox(height: 28),

                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _inputDecoration('Email', Icons.email_outlined),
                        validator: (value) {
                          final String v = (value ?? '').trim();
                          if (v.isEmpty) return 'Email is required';
                          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) return 'Enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isBusy ? null : _goNext,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B0000),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 3,
                          ),
                          child: const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.grey.shade300)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0),
                            child: Text('or sign up with', style: TextStyle(color: Colors.grey.shade600)),
                          ),
                          Expanded(child: Divider(color: Colors.grey.shade300)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _isBusy ? null : _signUpWithGoogle,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black87,
                            side: const BorderSide(color: Colors.transparent),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Image(image: AssetImage('assets/icons/google.png'), width: 20, height: 20),
                              const SizedBox(width: 12),
                              Text('Sign Up with Google', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Already have an account? ', style: TextStyle(color: Colors.grey.shade700)),
                          TextButton(
                            onPressed: _isBusy ? null : () => Navigator.pushReplacementNamed(context, '/login'),
                            child: const Text('Sign In'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.grey.shade700),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0xFF8B0000), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade400),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
      ),
    );
  }
}

// STEP 2: Full details (name + password)
class SignUpDetailsPage extends StatefulWidget {
  final String email;
  const SignUpDetailsPage({super.key, required this.email});

  @override
  State<SignUpDetailsPage> createState() => _SignUpDetailsPageState();
}

class _SignUpDetailsPageState extends State<SignUpDetailsPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _pass2Controller = TextEditingController();
  bool _isBusy = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  void dispose() {
    _nameController.dispose();
    _passController.dispose();
    _pass2Controller.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passController.text != _pass2Controller.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Passwords do not match'),
          backgroundColor: Colors.red.shade600,
        ),
      );
      return;
    }
    setState(() => _isBusy = true);
    try {
      await FirebaseAuthService.signUpWithEmail(
        email: widget.email,
        password: _passController.text,
        fullName: _nameController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/dashboard');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5F5F5), Color(0xFFEE8985)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: size.height * 0.02),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: BackButton(),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Complete Your Profile',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.grey.shade900),
                  ),
                ),
                const SizedBox(height: 16),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _inputDecoration('Full Name', Icons.person_outline),
                        validator: (v) {
                          if ((v ?? '').trim().isEmpty) return 'Name is required';
                          if ((v ?? '').trim().length < 2) return 'Enter your full name';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        enabled: false,
                        initialValue: widget.email,
                        decoration: _inputDecoration('Email', Icons.email_outlined),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passController,
                        obscureText: _obscure1,
                        decoration: _inputDecoration('Password', Icons.lock_outline).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(_obscure1 ? Icons.visibility_off : Icons.visibility, color: Colors.grey.shade600),
                            onPressed: () => setState(() => _obscure1 = !_obscure1),
                          ),
                        ),
                        validator: (v) {
                          if ((v ?? '').isEmpty) return 'Password is required';
                          if ((v ?? '').length < 6) return 'Minimum 6 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _pass2Controller,
                        obscureText: _obscure2,
                        decoration: _inputDecoration('Confirm Password', Icons.lock_reset).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(_obscure2 ? Icons.visibility_off : Icons.visibility, color: Colors.grey.shade600),
                            onPressed: () => setState(() => _obscure2 = !_obscure2),
                          ),
                        ),
                        validator: (v) {
                          if ((v ?? '').isEmpty) return 'Confirm your password';
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isBusy ? null : _handleSignUp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B0000),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 3,
                          ),
                          child: _isBusy
                              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Create Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.grey.shade700),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0xFF8B0000), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade400),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
      ),
    );
  }
}


