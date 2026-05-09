import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_dashboard_screen.dart';
import 'admin_manage_orders_screen.dart';
import 'admin_manage_products_screen.dart';
import 'admin_manage_users_screen.dart';
import 'admin_product_reviews_screen.dart';
import 'widgets/admin_side_panel.dart';

class AdminManageReviewsScreen extends StatefulWidget {
  final bool shellEmbedded;
  final VoidCallback? onNavigateToDashboard;
  final VoidCallback? onNavigateToProducts;
  final VoidCallback? onNavigateToOrders;
  final VoidCallback? onNavigateToUsers;

  const AdminManageReviewsScreen({
    super.key,
    this.shellEmbedded = false,
    this.onNavigateToDashboard,
    this.onNavigateToProducts,
    this.onNavigateToOrders,
    this.onNavigateToUsers,
  });

  @override
  State<AdminManageReviewsScreen> createState() =>
      _AdminManageReviewsScreenState();
}

class _AdminManageReviewsScreenState extends State<AdminManageReviewsScreen> {
  static const _brand = Color(0xFF7C150D);
  static const _softBg = Color(0xFFF7F2F1);
  String _filter = 'All';

  bool _matchesFilter(_ReviewAggregate a) {
    if (_filter == 'All') return true;
    if (_filter == 'Good') return a.avgRating >= 4.0;
    if (_filter == 'Bad') return a.avgRating <= 2.5;
    return true;
  }

  bool _matchesFeedbackFilter(Map<String, dynamic> data) {
    final mood = (data['moodScore'] as num?)?.toDouble() ?? 0.0;
    if (_filter == 'All') return true;
    if (_filter == 'Good') return mood >= 4.0;
    if (_filter == 'Bad') return mood <= 2.5;
    return true;
  }

  String _moodFace(int score) {
    final s = score.clamp(1, 5);
    switch (s) {
      case 1:
        return '😡';
      case 2:
        return '😕';
      case 3:
        return '😐';
      case 4:
        return '🙂';
      case 5:
        return '😍';
      default:
        return '😐';
    }
  }

  String _feedbackTopic(Map<String, dynamic> data) {
    final type = (data['type'] ?? 'feedback').toString();
    if (type == 'report') return 'Problem Report';
    return 'General Feedback';
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 980;
    return Scaffold(
      backgroundColor: _softBg,
      appBar:
          isWide
              ? null
              : AppBar(
                title: const Text('Manage Reviews'),
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1E1A1A),
                elevation: 0.2,
              ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance
                .collection('product_reviews')
                .snapshots(),
        builder: (context, reviewSnap) {
          final reviewDocs = reviewSnap.data?.docs ?? const [];
          final aggByProduct = <String, _ReviewAggregate>{};
          for (final doc in reviewDocs) {
            final d = doc.data();
            final productId = (d['productId'] ?? '').toString().trim();
            if (productId.isEmpty) continue;
            final rating = (d['rating'] as num?)?.toDouble() ?? 0.0;
            final entry = aggByProduct.putIfAbsent(
              productId,
              () => _ReviewAggregate(productId: productId),
            );
            entry.count += 1;
            entry.ratingSum += rating;
          }
          final aggregates =
              aggByProduct.values.toList()
                ..forEach(
                  (a) => a.avgRating = a.count == 0 ? 0 : a.ratingSum / a.count,
                )
                ..sort((a, b) => b.count.compareTo(a.count));

          final goodCount = aggregates.where((a) => a.avgRating >= 4.0).length;
          final badCount = aggregates.where((a) => a.avgRating <= 2.5).length;
          final midCount = aggregates.length - goodCount - badCount;
          final visible = aggregates.where(_matchesFilter).toList();

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream:
                FirebaseFirestore.instance.collection('products').snapshots(),
            builder: (context, productsSnap) {
              final nameById = <String, String>{};
              for (final p in productsSnap.data?.docs ?? const []) {
                final name = (p.data()['name'] ?? '').toString().trim();
                nameById[p.id] = name.isEmpty ? p.id : name;
              }

              Widget content = Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Manage Reviews',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1D2433),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE9DDDA)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Review quality chart',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 10),
                          _ChartRow(
                            label: 'Good (>= 4)',
                            value: goodCount,
                            total: aggregates.length,
                            color: const Color(0xFF1E8E4A),
                          ),
                          const SizedBox(height: 8),
                          _ChartRow(
                            label: 'Neutral',
                            value: midCount,
                            total: aggregates.length,
                            color: const Color(0xFFE4A11B),
                          ),
                          const SizedBox(height: 8),
                          _ChartRow(
                            label: 'Bad (<= 2.5)',
                            value: badCount,
                            total: aggregates.length,
                            color: const Color(0xFFB3261E),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children:
                          ['All', 'Good', 'Bad']
                              .map(
                                (f) => ChoiceChip(
                                  label: Text(f),
                                  selected: _filter == f,
                                  onSelected:
                                      (_) => setState(() => _filter = f),
                                ),
                              )
                              .toList(),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream:
                            FirebaseFirestore.instance
                                .collection('user_feedback')
                                .snapshots(),
                        builder: (context, feedbackSnap) {
                          final docs =
                              (feedbackSnap.data?.docs ?? const [])
                                  .where(
                                    (d) => _matchesFeedbackFilter(d.data()),
                                  )
                                  .toList()
                                ..sort((a, b) {
                                  final ad = a.data();
                                  final bd = b.data();
                                  final at =
                                      (ad['createdAt'] as Timestamp?)
                                          ?.millisecondsSinceEpoch ??
                                      0;
                                  final bt =
                                      (bd['createdAt'] as Timestamp?)
                                          ?.millisecondsSinceEpoch ??
                                      0;
                                  return bt.compareTo(at);
                                });

                          final feedbackPanel = Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE9DDDA),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(12, 12, 12, 8),
                                  child: Text(
                                    'Topic: User Feedback',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1D2433),
                                    ),
                                  ),
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  child:
                                      docs.isEmpty
                                          ? const Center(
                                            child: Text(
                                              'No user feedback for this filter.',
                                            ),
                                          )
                                          : ListView.separated(
                                            padding: const EdgeInsets.all(10),
                                            itemCount: docs.length,
                                            separatorBuilder:
                                                (_, __) =>
                                                    const SizedBox(height: 8),
                                            itemBuilder: (context, i) {
                                              final d = docs[i].data();
                                              final mood =
                                                  (d['moodScore'] as num?)
                                                      ?.toInt() ??
                                                  3;
                                              final comment =
                                                  (d['comment'] ?? '')
                                                      .toString();
                                              final user =
                                                  (d['userName'] ??
                                                          d['userEmail'] ??
                                                          'User')
                                                      .toString();
                                              final topic = _feedbackTopic(d);
                                              return ListTile(
                                                minVerticalPadding: 10,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  side: const BorderSide(
                                                    color: Color(0xFFEFE3E1),
                                                  ),
                                                ),
                                                title: Text(
                                                  '$user · $topic',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                subtitle: Text(
                                                  comment.isEmpty
                                                      ? 'No comment'
                                                      : comment,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                trailing: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      _moodFace(mood),
                                                      style: const TextStyle(
                                                        fontSize: 20,
                                                      ),
                                                    ),
                                                    Text(
                                                      '$mood/5',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                ),
                              ],
                            ),
                          );

                          final productPanel = Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE9DDDA),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(12, 12, 12, 8),
                                  child: Text(
                                    'Topic: Product Reviews',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1D2433),
                                    ),
                                  ),
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  child:
                                      visible.isEmpty
                                          ? const Center(
                                            child: Text(
                                              'No products match this review filter.',
                                            ),
                                          )
                                          : ListView.separated(
                                            padding: const EdgeInsets.all(12),
                                            itemCount: visible.length,
                                            separatorBuilder:
                                                (_, __) =>
                                                    const SizedBox(height: 8),
                                            itemBuilder: (context, i) {
                                              final a = visible[i];
                                              final name =
                                                  nameById[a.productId] ??
                                                  a.productId;
                                              return ListTile(
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  side: const BorderSide(
                                                    color: Color(0xFFEFE3E1),
                                                  ),
                                                ),
                                                title: Text(
                                                  name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                subtitle: Text(
                                                  '${a.count} review(s) · avg ${a.avgRating.toStringAsFixed(1)}',
                                                ),
                                                trailing: FilledButton(
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor: _brand,
                                                  ),
                                                  onPressed: () {
                                                    Navigator.of(context).push(
                                                      MaterialPageRoute<void>(
                                                        builder:
                                                            (
                                                              _,
                                                            ) => AdminProductReviewsScreen(
                                                              productId:
                                                                  a.productId,
                                                              productName: name,
                                                            ),
                                                      ),
                                                    );
                                                  },
                                                  child: const Text('Open'),
                                                ),
                                              );
                                            },
                                          ),
                                ),
                              ],
                            ),
                          );

                          if (isWide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: feedbackPanel),
                                const SizedBox(width: 12),
                                Expanded(child: productPanel),
                              ],
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: feedbackPanel),
                              const SizedBox(height: 12),
                              Expanded(child: productPanel),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );

              if (isWide && !widget.shellEmbedded) {
                content = Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _adminPanel(),
                    const SizedBox(width: 14),
                    Expanded(child: content),
                  ],
                );
              } else if (widget.shellEmbedded) {
                content = Padding(
                  padding: const EdgeInsets.all(12),
                  child: content,
                );
              }
              return content;
            },
          );
        },
      ),
    );
  }

  Widget _adminPanel() {
    final email =
        FirebaseAuth.instance.currentUser?.email ?? 'admin@example.com';
    return AdminSidePanel(
      email: email,
      selected: AdminNavItem.reviews,
      onDashboard: () {
        if (widget.onNavigateToDashboard != null)
          return widget.onNavigateToDashboard!();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => AdminDashboardScreen()),
        );
      },
      onProducts: () {
        if (widget.onNavigateToProducts != null)
          return widget.onNavigateToProducts!();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => AdminManageProductsScreen()),
        );
      },
      onOrders: () {
        if (widget.onNavigateToOrders != null)
          return widget.onNavigateToOrders!();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => AdminManageOrdersScreen()),
        );
      },
      onUsers: () {
        if (widget.onNavigateToUsers != null)
          return widget.onNavigateToUsers!();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminManageUsersScreen()),
        );
      },
    );
  }
}

class _ReviewAggregate {
  final String productId;
  int count = 0;
  double ratingSum = 0;
  double avgRating = 0;
  _ReviewAggregate({required this.productId});
}

class _ChartRow extends StatelessWidget {
  final String label;
  final int value;
  final int total;
  final Color color;
  const _ChartRow({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : (value / total).clamp(0, 1).toDouble();
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              color: color,
              backgroundColor: const Color(0xFFEFE9E8),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
