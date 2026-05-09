import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/product_review.dart';
import 'admin_support_chats_screen.dart';

/// Lists `product_reviews` for one product (admin can delete).
class AdminProductReviewsScreen extends StatelessWidget {
  final String productId;
  final String productName;

  const AdminProductReviewsScreen({
    super.key,
    required this.productId,
    required this.productName,
  });

  static const _brand = Color(0xFF7C150D);

  Future<void> _replyToReview(
    BuildContext context, {
    required ProductReview review,
  }) async {
    final ctrl = TextEditingController(
      text:
          'Hi ${review.userDisplayName}, we are sorry about your experience. '
          'Thank you for the feedback — we want to make this right.',
    );

    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 14,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 14,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Reply to customer',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'User: ${review.userDisplayName}',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _brand),
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Send reply'),
            ),
          ],
        ),
      ),
    );

    ctrl.dispose();
    if (text == null || text.isEmpty || !context.mounted) return;

    try {
      final db = FirebaseFirestore.instance;
      final chatRef = db.collection('support_chats').doc(review.userId);
      final nowServer = FieldValue.serverTimestamp();
      final nowLocal = Timestamp.now();

      await chatRef.set({
        'userId': review.userId,
        'userName': review.userDisplayName,
        'lastMessage': text,
        'lastMessageAt': nowServer,
        'updatedAt': nowServer,
        'unreadForAdmin': false,
        'unreadForUser': true,
        'typingByAdmin': false,
      }, SetOptions(merge: true));

      await chatRef.collection('messages').add({
        'senderId': 'admin',
        'senderRole': 'admin',
        'text': text,
        'createdAt': nowLocal,
        'createdAtServer': nowServer,
        'seenByAdmin': true,
        'seenByUser': false,
        'source': 'product_review_reply',
        'productId': productId,
      });

      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AdminSupportChatDetailScreen(
            chatId: review.userId,
            chatTitle: review.userDisplayName,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send reply: $e')),
      );
    }
  }

  String _date(DateTime? t) {
    if (t == null) return '—';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F2F1),
      appBar: AppBar(
        title: const Text(
          'Product reviews',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E1A1A),
        elevation: 0.2,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                productName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1D2433),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('product_reviews')
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load reviews.\n${snap.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = (snap.data?.docs ?? [])
                    .where((d) => (d.data()['productId'] ?? '').toString() == productId)
                    .toList()
                  ..sort((a, b) {
                    final ad = a.data();
                    final bd = b.data();
                    final at = (ad['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                        (ad['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                        0;
                    final bt = (bd['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                        (bd['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                        0;
                    return bt.compareTo(at);
                  });
                if (docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No customer reviews for this product yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final review = ProductReview.fromFirestore(docs[i]);
                    final ref = docs[i].reference;
                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFE9DDDA)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        review.userDisplayName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'User: ${review.userId}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.black45,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  _date(review.createdAt ?? review.updatedAt),
                                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                                ),
                                IconButton(
                                  tooltip: 'Reply in chat',
                                  icon: const Icon(Icons.reply_rounded, color: Color(0xFF7C150D)),
                                  onPressed: () =>
                                      _replyToReview(context, review: review),
                                ),
                                IconButton(
                                  tooltip: 'Delete review',
                                  icon: const Icon(Icons.delete_outline, color: Color(0xFFB3261E)),
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Delete review'),
                                            content: Text(
                                              'Remove this review from ${review.userDisplayName}?',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(ctx, false),
                                                child: const Text('Cancel'),
                                              ),
                                              FilledButton(
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: _brand,
                                                ),
                                                onPressed: () => Navigator.pop(ctx, true),
                                                child: const Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        ) ??
                                        false;
                                    if (!ok || !context.mounted) return;
                                    try {
                                      await ref.delete();
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Review removed.')),
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Could not delete: $e')),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: List.generate(
                                5,
                                (j) => Icon(
                                  j < review.rating ? Icons.star_rounded : Icons.star_border_rounded,
                                  size: 18,
                                  color: j < review.rating ? Colors.red : Colors.black38,
                                ),
                              ),
                            ),
                            if (review.comment.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                review.comment,
                                style: const TextStyle(height: 1.4, fontSize: 14),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
