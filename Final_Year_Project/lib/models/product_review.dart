import 'package:cloud_firestore/cloud_firestore.dart';

/// One customer review in top-level `product_reviews`.
class ProductReview {
  final String id;
  final String productId;
  final String userId;
  final String userDisplayName;
  final int rating;
  final String comment;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ProductReview({
    required this.id,
    required this.productId,
    required this.userId,
    required this.userDisplayName,
    required this.rating,
    required this.comment,
    this.createdAt,
    this.updatedAt,
  });

  factory ProductReview.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final r = d['rating'];
    int stars = 5;
    if (r is int) {
      stars = r.clamp(1, 5);
    } else if (r is double) {
      stars = r.round().clamp(1, 5);
    }
    return ProductReview(
      id: doc.id,
      productId: (d['productId'] as String?) ?? '',
      userId: (d['userId'] as String?) ?? doc.id,
      userDisplayName: (d['userDisplayName'] as String?)?.trim().isNotEmpty == true
          ? (d['userDisplayName'] as String).trim()
          : 'Customer',
      rating: stars,
      comment: (d['comment'] as String?)?.trim() ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
