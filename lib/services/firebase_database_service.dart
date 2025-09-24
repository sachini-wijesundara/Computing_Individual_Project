import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../firebase/firebase_config.dart';

class FirebaseDatabaseService {
  static final FirebaseFirestore _firestore = FirebaseConfig.firestore;
  static final FirebaseAuth _auth = FirebaseConfig.auth;

  // User data operations
  static Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.data();
    } catch (e) {
      print('Get user data error: $e');
      return null;
    }
  }

  static Future<void> updateUserData(String uid, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Update user data error: $e');
      rethrow;
    }
  }

  // Makeup preferences
  static Future<void> updateMakeupPreferences({
    String? skinTone,
    List<String>? favoriteColors,
    String? makeupStyle,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final preferences = <String, dynamic>{};
        
        if (skinTone != null) preferences['skinTone'] = skinTone;
        if (favoriteColors != null) preferences['favoriteColors'] = favoriteColors;
        if (makeupStyle != null) preferences['makeupStyle'] = makeupStyle;
        
        await _firestore.collection('users').doc(user.uid).update({
          'preferences': FieldValue.arrayUnion([preferences]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Update makeup preferences error: $e');
      rethrow;
    }
  }

  // Try-on history
  static Future<void> saveTryOnHistory({
    required String productId,
    required String productName,
    required String productType,
    required String imageUrl,
    required Map<String, dynamic> makeupSettings,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'tryOnHistory': FieldValue.arrayUnion([{
            'productId': productId,
            'productName': productName,
            'productType': productType,
            'imageUrl': imageUrl,
            'makeupSettings': makeupSettings,
            'timestamp': FieldValue.serverTimestamp(),
          }]),
        });
      }
    } catch (e) {
      print('Save try-on history error: $e');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getTryOnHistory() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        final data = doc.data();
        return List<Map<String, dynamic>>.from(data?['tryOnHistory'] ?? []);
      }
      return [];
    } catch (e) {
      print('Get try-on history error: $e');
      return [];
    }
  }

  // Favorite products
  static Future<void> addToFavorites(String productId) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'favoriteProducts': FieldValue.arrayUnion([productId]),
        });
      }
    } catch (e) {
      print('Add to favorites error: $e');
      rethrow;
    }
  }

  static Future<void> removeFromFavorites(String productId) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'favoriteProducts': FieldValue.arrayRemove([productId]),
        });
      }
    } catch (e) {
      print('Remove from favorites error: $e');
      rethrow;
    }
  }

  static Future<List<String>> getFavoriteProducts() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        final data = doc.data();
        return List<String>.from(data?['favoriteProducts'] ?? []);
      }
      return [];
    } catch (e) {
      print('Get favorite products error: $e');
      return [];
    }
  }

  // Product data
  static Future<List<Map<String, dynamic>>> getProducts({
    String? category,
    int limit = 20,
  }) async {
    try {
      Query query = _firestore.collection('products');
      
      if (category != null) {
        query = query.where('category', isEqualTo: category);
      }
      
      query = query.limit(limit);
      
      final snapshot = await query.get();
      return snapshot.docs.map((doc) => {
        'id': doc.id,
        ...doc.data() as Map<String, dynamic>,
      }).toList();
    } catch (e) {
      print('Get products error: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getProduct(String productId) async {
    try {
      final doc = await _firestore.collection('products').doc(productId).get();
      if (doc.exists) {
        return {
          'id': doc.id,
          ...doc.data()!,
        };
      }
      return null;
    } catch (e) {
      print('Get product error: $e');
      return null;
    }
  }

  // AI suggestions
  static Future<void> saveAISuggestion({
    required String suggestionType,
    required Map<String, dynamic> suggestion,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('ai_suggestions').add({
          'userId': user.uid,
          'suggestionType': suggestionType,
          'suggestion': suggestion,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Save AI suggestion error: $e');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getAISuggestions({
    String? suggestionType,
    int limit = 10,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        Query query = _firestore
            .collection('ai_suggestions')
            .where('userId', isEqualTo: user.uid);
        
        if (suggestionType != null) {
          query = query.where('suggestionType', isEqualTo: suggestionType);
        }
        
        query = query.orderBy('timestamp', descending: true).limit(limit);
        
        final snapshot = await query.get();
        return snapshot.docs.map((doc) => {
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        }).toList();
      }
      return [];
    } catch (e) {
      print('Get AI suggestions error: $e');
      return [];
    }
  }
}




