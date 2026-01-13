import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firebase_auth_service.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  String? _error;

  // Getters
  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;

  AuthProvider() {
    _init();
  }

  void _init() {
    try {
      FirebaseAuthService.authStateChanges.listen((User? user) {
        _user = user;
        notifyListeners();
      });
    } catch (e) {
      // Firebase not initialized - user will need to login manually
      debugPrint('ℹ️ Firebase Auth not available: $e');
    }
  }

  // Sign up with email and password
  Future<void> signUpWithEmail(String email, String password, String fullName) async {
    _setLoading(true);
    _clearError();

    try {
      await FirebaseAuthService.signUpWithEmail(
        email: email,
        password: password,
        fullName: fullName,
      );
    } catch (e) {
      _setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Sign in with email and password
  Future<void> signInWithEmail(String email, String password) async {
    _setLoading(true);
    _clearError();

    try {
      await FirebaseAuthService.signInWithEmail(
        email: email,
        password: password,
      );
    } catch (e) {
      _setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Sign in with Google
  Future<void> signInWithGoogle() async {
    _setLoading(true);
    _clearError();

    try {
      await FirebaseAuthService.signInWithGoogle();
    } catch (e) {
      _setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Sign out
  Future<void> signOut() async {
    _setLoading(true);
    _clearError();

    try {
      await FirebaseAuthService.signOut();
    } catch (e) {
      _setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Reset password
  Future<void> resetPassword(String email) async {
    _setLoading(true);
    _clearError();

    try {
      await FirebaseAuthService.resetPassword(email);
    } catch (e) {
      _setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Update user profile
  Future<void> updateProfile({String? displayName, String? photoURL}) async {
    _setLoading(true);
    _clearError();

    try {
      await FirebaseAuthService.updateUserProfile(
        displayName: displayName,
        photoURL: photoURL,
      );
    } catch (e) {
      _setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _error = error;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    notifyListeners();
  }
}




