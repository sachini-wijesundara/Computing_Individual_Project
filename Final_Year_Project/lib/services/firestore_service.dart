import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import '../models/product_review.dart';

/// Singleton Firestore service.
/// Usage: `FirestoreDb.instance.productsByCategory('Lip Sticks')`
class FirestoreDb {
  FirestoreDb._();
  static final FirestoreDb instance = FirestoreDb._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Products ─────────────────────────────────────────────────────────────────

  /// Returns a real-time stream of products, optionally filtered by category.
  /// Pass `'All'` (or any unrecognised value) to get every product.
  Stream<List<Product>> productsByCategory(String category) {
    Query<Map<String, dynamic>> query = _db.collection('products');

    if (category != 'All') {
      query = query.where('category', isEqualTo: category);
    }

    return query.snapshots().map(
      (snap) => snap.docs.map((doc) => Product.fromFirestore(doc)).toList(),
    );
  }

  /// One-off fetch of every product (e.g. in-app search).
  Future<List<Product>> fetchAllProducts() async {
    final snap = await _db.collection('products').get();
    return snap.docs.map((doc) => Product.fromFirestore(doc)).toList();
  }

  /// Fetch a single product by its document ID (one-off, not a stream).
  CollectionReference<Map<String, dynamic>> _productReviewsRef() {
    return _db.collection('product_reviews');
  }

  /// Live list of customer reviews (newest first).
  Stream<List<ProductReview>> productReviewsStream(String productId) {
    return _productReviewsRef()
        .where('productId', isEqualTo: productId)
        .snapshots()
        .map((snap) {
          final reviews = snap.docs.map(ProductReview.fromFirestore).toList();
          reviews.sort((a, b) {
            final am = (a.createdAt ?? a.updatedAt)?.millisecondsSinceEpoch ?? 0;
            final bm = (b.createdAt ?? b.updatedAt)?.millisecondsSinceEpoch ?? 0;
            return bm.compareTo(am);
          });
          return reviews;
        });
  }

  /// One review per user per product (document id = [uid]).
  Future<void> upsertProductReview({
    required String productId,
    required String uid,
    required int rating,
    String? comment,
    String? userDisplayName,
  }) async {
    if (productId.isEmpty || uid.isEmpty) {
      throw ArgumentError('Review requires a product id and signed-in user.');
    }
    final reviewId = '${productId}_$uid';
    final ref = _productReviewsRef().doc(reviewId);
    final int stars = rating < 1 ? 1 : (rating > 5 ? 5 : rating);
    final name = (userDisplayName ?? '').trim();
    final body = (comment ?? '').trim();

    final snap = await ref.get();
    final data = <String, dynamic>{
      'productId': productId,
      'userId': uid,
      'rating': stars,
      'comment': body,
      'userDisplayName': name.isNotEmpty ? name : 'Customer',
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!snap.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }
    await ref.set(data, SetOptions(merge: true));
  }

  Future<Product?> getProduct(String id) async {
    try {
      final doc = await _db.collection('products').doc(id).get();
      if (!doc.exists) return null;
      return Product.fromFirestore(doc);
    } catch (e) {
      print('getProduct error: $e');
      return null;
    }
  }

  /// Returns shades for a product.
  /// Priority: direct ID lookup -> fallback query by name/imagePath.
  Future<List<Map<String, String>>> getProductShades({
    String? productId,
    String? productName,
    String? imagePath,
  }) async {
    try {
      if (productId != null && productId.isNotEmpty) {
        final doc = await _db.collection('products').doc(productId).get();
        if (doc.exists) {
          final shades = await _extractShades(doc);
          if (shades.isNotEmpty) return shades;
        }
      }

      Query<Map<String, dynamic>> query = _db.collection('products');
      if (productName != null && productName.isNotEmpty) {
        query = query.where('name', isEqualTo: productName);
      }

      final snap = await query.limit(8).get();
      for (final doc in snap.docs) {
        final product = Product.fromFirestore(doc);
        if (imagePath != null &&
            imagePath.isNotEmpty &&
            product.imagePath.isNotEmpty &&
            product.imagePath != imagePath) {
          continue;
        }
        final shades = await _extractShades(doc);
        if (shades.isNotEmpty) return shades;
      }
    } catch (e) {
      print('getProductShades error: $e');
    }
    return const [];
  }

  Future<List<Map<String, String>>> _extractShades(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data() ?? const <String, dynamic>{};

    // Common array fields in Firestore schemas.
    const candidates = [
      'shades',
      'shadeList',
      'shade_list',
      'shadeOptions',
      'shade_options',
      'colors',
      'colour',
      'colours',
    ];

    for (final key in candidates) {
      final shades = _normalizeShades(data[key]);
      if (shades.isNotEmpty) return shades;
    }

    // Some schemas store a single shade map/string.
    const singleCandidates = [
      'shade',
      'defaultShade',
      'default_shade',
      'colorHex',
      'colourHex',
      'hex',
    ];
    for (final key in singleCandidates) {
      final shades = _normalizeShades(data[key]);
      if (shades.isNotEmpty) return shades;
    }

    // Subcollection fallback: products/{id}/shades
    try {
      final sub = await doc.reference.collection('shades').get();
      if (sub.docs.isNotEmpty) {
        final shades = _normalizeShades(sub.docs.map((d) => d.data()).toList());
        if (shades.isNotEmpty) return shades;
      }
    } catch (_) {
      // Ignore subcollection read failures and keep fallback behavior.
    }

    return const [];
  }

  List<Map<String, String>> _normalizeShades(dynamic raw) {
    if (raw == null) return const [];

    if (raw is List) {
      final out = <Map<String, String>>[];
      for (final item in raw) {
        final shade = _normalizeShadeItem(item);
        if (shade != null) out.add(shade);
      }
      return out;
    }

    final single = _normalizeShadeItem(raw);
    return single == null ? const [] : [single];
  }

  Map<String, String>? _normalizeShadeItem(dynamic item) {
    if (item == null) return null;

    if (item is Map) {
      final map = item.map((k, v) => MapEntry(k.toString(), v));
      final name = (map['name'] ??
              map['shade'] ??
              map['label'] ??
              map['title'] ??
              map['colorName'] ??
              map['colourName'])
          ?.toString();

      final hex = _normalizeHex(
        map['hex'] ??
            map['colorHex'] ??
            map['colourHex'] ??
            map['color'] ??
            map['colour'] ??
            map['value'],
      );

      if (hex == null) return null;
      return {
        'name': (name == null || name.isEmpty) ? 'Shade' : name,
        'hex': hex,
      };
    }

    if (item is String || item is num) {
      final hex = _normalizeHex(item);
      if (hex == null) return null;
      return {'name': 'Shade', 'hex': hex};
    }

    return null;
  }

  String? _normalizeHex(dynamic value) {
    if (value == null) return null;

    if (value is int) {
      final rgb = value & 0xFFFFFF;
      return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
    }

    if (value is String) {
      var s = value.trim();
      if (s.isEmpty) return null;

      if (s.startsWith('0x') || s.startsWith('0X')) {
        s = s.substring(2);
      }
      if (s.startsWith('#')) {
        s = s.substring(1);
      }
      if (s.length == 8) {
        // AARRGGBB -> RRGGBB
        s = s.substring(2);
      }
      if (s.length != 6) return null;
      final valid = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s);
      if (!valid) return null;
      return '#${s.toUpperCase()}';
    }

    return null;
  }

  // ── Cart ─────────────────────────────────────────────────────────────────────

  /// Adds a product to the user's cart subcollection.
  Future<void> addToCart(String uid, Product product) async {
    try {
      final cartRef = _db
          .collection('users')
          .doc(uid)
          .collection('cart')
          .doc(product.id);

      final snap = await cartRef.get();
      if (snap.exists) {
        // Increment quantity if already in cart
        await cartRef.update({'quantity': FieldValue.increment(1)});
      } else {
        await cartRef.set({
          ...product.toMap(),
          'productId': product.id,
          'quantity':  1,
          'addedAt':   FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('addToCart error: $e');
    }
  }

  /// Returns a real-time stream of the user's cart items.
  Stream<List<Map<String, dynamic>>> cartStream(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('cart')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => {'id': d.id, ...d.data()})
            .toList());
  }

  /// Removes a product from the cart.
  Future<void> removeFromCart(String uid, String productId) async {
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('cart')
          .doc(productId)
          .delete();
    } catch (e) {
      print('removeFromCart error: $e');
    }
  }

  // ── Favourites / wishlist (stored on `users/{uid}.favourites` as product id strings) ─

  /// Live list of product document ids in the user's wishlist (order preserved).
  Stream<List<String>> favouriteProductIdsStream(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((snap) {
      return List<String>.from(snap.data()?['favourites'] ?? []);
    });
  }

  /// Loads [Product]s for the given ids, in the same order as [ids]. Skips missing ids.
  /// Firestore `whereIn` is limited to 10 values per query.
  Future<List<Product>> fetchProductsByIdsInOrder(List<String> ids) async {
    if (ids.isEmpty) return [];
    const maxIn = 10;
    final byId = <String, Product>{};
    for (var i = 0; i < ids.length; i += maxIn) {
      final slice = ids.sublist(i, math.min(i + maxIn, ids.length));
      final snap = await _db
          .collection('products')
          .where(FieldPath.documentId, whereIn: slice)
          .get();
      for (final doc in snap.docs) {
        byId[doc.id] = Product.fromFirestore(doc);
      }
    }
    final out = <Product>[];
    for (final id in ids) {
      final p = byId[id];
      if (p != null) out.add(p);
    }
    return out;
  }

  Future<void> toggleFavourite(String uid, String productId) async {
    final ref = _db.collection('users').doc(uid);
    final snap = await ref.get();
    final favs = List<String>.from(snap.data()?['favourites'] ?? []);
    final remove = favs.contains(productId);
    await ref.set(
      {
        'favourites':
            remove ? FieldValue.arrayRemove([productId]) : FieldValue.arrayUnion([productId]),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
