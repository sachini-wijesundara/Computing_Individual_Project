import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'firebase_options.dart';

class FirebaseConfig {
  static FirebaseAuth? _auth;
  static FirebaseFirestore? _firestore;
  static FirebaseStorage? _storage;
  static FirebaseAnalytics? _analytics;
  static FirebaseCrashlytics? _crashlytics;

  // Initialize Firebase
  static Future<void> initialize() async {
    try {
      // Check if already initialized (e.g., after hot restart)
      if (Firebase.apps.isNotEmpty) {
        print('🔥 Firebase already initialized, reusing existing instance');
      } else {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        print('🔥 Firebase initialized successfully');
      }
      
      // Always set instance variables if Firebase is available
      _auth = FirebaseAuth.instance;
      _firestore = FirebaseFirestore.instance;
      _storage = FirebaseStorage.instance;
      _analytics = FirebaseAnalytics.instance;
      _crashlytics = FirebaseCrashlytics.instance;
      
      // Enable crashlytics
      await _crashlytics!.setCrashlyticsCollectionEnabled(true);
      
    } catch (e, stack) {
      print('⚠️ Firebase initialization error: $e');
      print('Stack: $stack');
      
      // Even if initialization failed, try to use existing Firebase instance
      if (Firebase.apps.isNotEmpty) {
        print('🔧 Attempting to use existing Firebase instance despite error...');
        try {
          _auth = FirebaseAuth.instance;
          _firestore = FirebaseFirestore.instance;
          _storage = FirebaseStorage.instance;
          _analytics = FirebaseAnalytics.instance;
          _crashlytics = FirebaseCrashlytics.instance;
          print('✅ Successfully connected to existing Firebase instance');
        } catch (e2) {
          print('❌ Could not connect to Firebase: $e2');
        }
      }
    }
  }

  
  // Getters with null-safety checks
  static FirebaseAuth get auth {
    if (_auth == null) {
      throw StateError('Firebase not initialized. Call FirebaseConfig.initialize() first.');
    }
    return _auth!;
  }
  
  static FirebaseFirestore get firestore {
    if (_firestore == null) {
      throw StateError('Firebase not initialized. Call FirebaseConfig.initialize() first.');
    }
    return _firestore!;
  }
  
  static FirebaseStorage get storage {
    if (_storage == null) {
      throw StateError('Firebase not initialized. Call FirebaseConfig.initialize() first.');
    }
    return _storage!;
  }
  
  static FirebaseAnalytics get analytics {
    if (_analytics == null) {
      throw StateError('Firebase not initialized. Call FirebaseConfig.initialize() first.');
    }
    return _analytics!;
  }
  
  static FirebaseCrashlytics get crashlytics {
    if (_crashlytics == null) {
      throw StateError('Firebase not initialized. Call FirebaseConfig.initialize() first.');
    }
    return _crashlytics!;
  }
  
  // Check if Firebase is initialized
  static bool get isInitialized => _auth != null;
}
