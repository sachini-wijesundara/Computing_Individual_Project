import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Publishes lightweight presence while a signed-in user is on the live try-on
/// screen so the admin dashboard can show near-real-time activity.
class TryOnActivityService {
  TryOnActivityService._();

  static Timer? _timer;

  static void start({
    required String productId,
    required String productName,
    required String? productCategory,
  }) {
    stop(endRemote: false);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    void pulse() {
      FirebaseFirestore.instance.collection('tryon_activity').doc(user.uid).set(
        {
          'uid': user.uid,
          'email': user.email,
          'displayName': user.displayName,
          'productId': productId,
          'productName': productName,
          'productCategory': productCategory,
          'isActive': true,
          'lastActiveAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    pulse();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => pulse());
  }

  static void updateProduct({
    required String productId,
    required String productName,
    required String? productCategory,
  }) {
    if (_timer == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    FirebaseFirestore.instance.collection('tryon_activity').doc(user.uid).set(
      {
        'productId': productId,
        'productName': productName,
        'productCategory': productCategory,
        'lastActiveAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static void stop({bool endRemote = true}) {
    _timer?.cancel();
    _timer = null;
    if (!endRemote) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    FirebaseFirestore.instance.collection('tryon_activity').doc(user.uid).set(
      {
        'isActive': false,
        'lastActiveAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
