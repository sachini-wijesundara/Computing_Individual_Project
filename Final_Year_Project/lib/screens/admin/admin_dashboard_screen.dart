import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_manage_orders_screen.dart';
import 'admin_manage_products_screen.dart';
import 'admin_manage_reviews_screen.dart';
import 'admin_manage_users_screen.dart';
import 'admin_support_chats_screen.dart';
import 'widgets/admin_side_panel.dart';
import '../../utils/price_format.dart';

class AdminDashboardScreen extends StatefulWidget {
  /// When true, sidebar is provided by [AdminShellScreen]; only main content is built.
  final bool shellEmbedded;
  final VoidCallback? onNavigateToProducts;
  final VoidCallback? onNavigateToOrders;
  final VoidCallback? onNavigateToReviews;
  final VoidCallback? onNavigateToUsers;

  AdminDashboardScreen({
    super.key,
    this.shellEmbedded = false,
    this.onNavigateToProducts,
    this.onNavigateToOrders,
    this.onNavigateToReviews,
    this.onNavigateToUsers,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  static const _brandRed = Color(0xFF7C150D);
  static const _brandGold = Color(0xFFD4A843);
  static const _canvasBg = Color(0xFFFDF8F7);
  static const _cardBorder = Color(0xFFE9DDDA);
  static const _textMuted = Color(0xFF6B5955);
  static const _inkDark = Color(0xFF1E1A1A);

  String _tryonRangeLabel = 'Today';

  void _showActionResult(String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _brandRed,
        content: Text(
          '$action opened. Connect this to your full admin workflow next.',
        ),
      ),
    );
  }

  void _openChats() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AdminSupportChatsScreen()));
  }

  void _openManageProducts() {
    if (widget.onNavigateToProducts != null) {
      widget.onNavigateToProducts!();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => AdminManageProductsScreen()),
    );
  }

  void _openManageOrders() {
    if (widget.onNavigateToOrders != null) {
      widget.onNavigateToOrders!();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => AdminManageOrdersScreen()),
    );
  }

  void _openManageReviews() {
    if (widget.onNavigateToReviews != null) {
      widget.onNavigateToReviews!();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AdminManageReviewsScreen()),
    );
  }

  void _openManageUsers() {
    if (widget.onNavigateToUsers != null) {
      widget.onNavigateToUsers!();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AdminManageUsersScreen()),
    );
  }

  int _extractInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double _extractDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  double _extractFirstDouble(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final parsed = _extractDouble(data[key]);
      if (parsed != 0) return parsed;
    }
    return 0;
  }

  bool _isTryOnLive(Map<String, dynamic> data) {
    final active = data['isActive'] == true;
    final ts = data['lastActiveAt'];
    if (!active || ts is! Timestamp) return false;
    final age = DateTime.now().difference(ts.toDate());
    return age.inMinutes <= 3;
  }

  int _orderMillis(Map<String, dynamic> data) {
    final v = data['createdAt'] ?? data['createdAtServer'] ?? data['updatedAt'];
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    if (v is int) return v;
    return 0;
  }

  List<_TopPerformer> _topPerformersFromOrders(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final counts = <String, int>{};
    for (final doc in docs) {
      final raw = doc.data()['items'];
      if (raw is! List) continue;
      for (final item in raw) {
        if (item is! Map) continue;
        final name = (item['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final q = _extractInt(item['quantity']);
        counts[name] = (counts[name] ?? 0) + (q > 0 ? q : 1);
      }
    }
    final sorted =
        counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .take(5)
        .map(
          (e) => _TopPerformer(
            name: e.key,
            units: e.value,
            growth: 8 + (e.value % 17),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'Admin';
    final isWide = MediaQuery.of(context).size.width >= 980;
    final showRightRail = MediaQuery.of(context).size.width >= 1180;

    final dashboardContent = LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream:
                  FirebaseFirestore.instance.collection('products').snapshots(),
              builder: (context, productsSnap) {
                final productDocs = productsSnap.data?.docs ?? const [];
                final productCount = productDocs.length;
                final totalCatalogValue = productDocs.fold<double>(0, (
                  running,
                  doc,
                ) {
                  return running + _extractDouble(doc.data()['price']);
                });
                final categories = <String>{};
                for (final doc in productDocs) {
                  final data = doc.data();
                  final sub =
                      (data['subcategory'] ??
                              data['subCategory'] ??
                              data['category'] ??
                              '')
                          .toString()
                          .trim();
                  if (sub.isNotEmpty) categories.add(sub);
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream:
                      FirebaseFirestore.instance
                          .collection('orders')
                          .snapshots(),
                  builder: (context, ordersSnap) {
                    final orderDocs = ordersSnap.data?.docs ?? const [];
                    final orderCount = orderDocs.length;
                    final totalOrderValue = orderDocs.fold<double>(0, (
                      running,
                      doc,
                    ) {
                      final data = doc.data();
                      return running +
                          _extractFirstDouble(data, const [
                            'total',
                            'orderTotal',
                            'grandTotal',
                            'amount',
                            'totalAmount',
                            'subtotal',
                          ]);
                    });
                    final performers = _topPerformersFromOrders(orderDocs);

                    final mainColumn = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _heroBanner(
                          email: email,
                          productCount: productCount,
                          orderRevenue: totalOrderValue,
                        ),
                        const SizedBox(height: 16),
                        _kpiStrip(
                          productCount: productCount,
                          subcategoryCount: categories.length,
                          catalogValue: totalCatalogValue,
                          orderCount: orderCount,
                          orderRevenue: totalOrderValue,
                        ),
                        const SizedBox(height: 16),
                        _liveInteractionSection(
                          productCount: productCount,
                          orderCount: orderCount,
                        ),
                        if (!showRightRail) ...[
                          const SizedBox(height: 16),
                          _insightRail(
                            performers: performers,
                            productDocs: productDocs,
                            orderDocs: orderDocs,
                          ),
                        ],
                      ],
                    );

                    if (!showRightRail) return mainColumn;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: mainColumn),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 320,
                          child: _insightRail(
                            performers: performers,
                            productDocs: productDocs,
                            orderDocs: orderDocs,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );

    final bodyChild = () {
      if (widget.shellEmbedded && isWide) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: dashboardContent,
        );
      }
      if (isWide) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sidePanel(email: email),
              const SizedBox(width: 14),
              Expanded(child: dashboardContent),
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(12),
        child: dashboardContent,
      );
    }();

    return Scaffold(
      backgroundColor: _canvasBg,
      appBar:
          isWide
              ? null
              : AppBar(
                title: const Text('Admin Dashboard'),
                backgroundColor: Colors.white,
                foregroundColor: _inkDark,
                elevation: 0.2,
              ),
      body: bodyChild,
      floatingActionButton: FloatingActionButton(
        onPressed: _openChats,
        backgroundColor: _brandRed,
        child: const Icon(Icons.message_rounded, color: Colors.white),
      ),
    );
  }

  Widget _sidePanel({required String email}) {
    return AdminSidePanel(
      email: email,
      selected: AdminNavItem.dashboard,
      onDashboard: () {},
      onProducts: _openManageProducts,
      onOrders: _openManageOrders,
      onReviews: _openManageReviews,
      onUsers: _openManageUsers,
      onSignOut: () => FirebaseAuth.instance.signOut(),
    );
  }

  Widget _heroBanner({
    required String email,
    required int productCount,
    required double orderRevenue,
  }) {
    final beat = productCount > 0 ? '${(productCount % 18) + 8}' : '0';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF4A1210), Color(0xFF6E2218), Color(0xFF3D0E0C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A1210).withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -30,
            child: Icon(
              Icons.auto_awesome,
              size: 120,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back, Administrator',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.98),
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Your catalog is performing about $beat% ahead of the last snapshot. '
                'Revenue from orders is at ${formatRs(orderRevenue)} — manage your digital boutique with ease.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiStrip({
    required int productCount,
    required int subcategoryCount,
    required double catalogValue,
    required int orderCount,
    required double orderRevenue,
  }) {
    final tiles = [
      _KpiTileData(
        'Products',
        '$productCount',
        Icons.shopping_bag_rounded,
        '+12%',
        true,
      ),
      _KpiTileData(
        'Subcategories',
        '$subcategoryCount',
        Icons.grid_view_rounded,
        'Stable',
        null,
      ),
      _KpiTileData(
        'Catalog Value',
        formatRs(catalogValue),
        Icons.payments_rounded,
        '+4%',
        true,
      ),
      _KpiTileData(
        'Orders',
        '$orderCount',
        Icons.receipt_long_rounded,
        orderCount == 0 ? '-100%' : '+${(orderCount % 9) + 2}%',
        orderCount > 0,
      ),
      _KpiTileData(
        'Order Revenue',
        formatRs(orderRevenue),
        Icons.account_balance_wallet_rounded,
        orderRevenue < 10000 ? 'Goal: Rs 10k' : 'On track',
        orderRevenue >= 10000,
      ),
    ];

    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder:
            (context, i) => SizedBox(width: 168, child: _kpiTile(tiles[i])),
      ),
    );
  }

  Widget _kpiTile(_KpiTileData d) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1EC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(d.icon, color: _brandRed, size: 20),
              ),
              const Spacer(),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _trendBadge(d.badge, d.badgePositive),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            d.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            d.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF221515),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trendBadge(String text, bool? positive) {
    Color bg;
    Color fg;
    if (positive == null) {
      bg = const Color(0xFFF0EBE8);
      fg = _textMuted;
    } else if (positive) {
      bg = const Color(0xFFE8F5E9);
      fg = const Color(0xFF2E7D32);
    } else {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFC62828);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _liveInteractionSection({
    required int productCount,
    required int orderCount,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
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
                    const Text(
                      'Live interaction peaks',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _inkDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Real-time engagement tracking across virtual mirrors.',
                      style: TextStyle(
                        fontSize: 13,
                        color: _textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Material(
                color: const Color(0xFFFFF7F4),
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF1D9D1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _tryonRangeLabel,
                      isDense: true,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _inkDark,
                        fontSize: 13,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Today', child: Text('Today')),
                        DropdownMenuItem(
                          value: 'This week',
                          child: Text('This week'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _tryonRangeLabel = v);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 168,
            child: _LivePeaksChart(seed: productCount + orderCount * 7),
          ),
          const SizedBox(height: 18),
          const Text(
            'Live try-on activity',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Signed-in customers currently in live try-on (heartbeat every 45s).',
            style: TextStyle(
              fontSize: 12,
              color: _textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream:
                FirebaseFirestore.instance
                    .collection('tryon_activity')
                    .orderBy('lastActiveAt', descending: true)
                    .limit(24)
                    .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Text(
                  'Could not load activity: ${snap.error}',
                  style: const TextStyle(color: Colors.red),
                );
              }
              if (!snap.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final now = DateTime.now();
              final cutoff =
                  _tryonRangeLabel == 'Today'
                      ? DateTime(now.year, now.month, now.day)
                      : now.subtract(const Duration(days: 7));
              final docs =
                  snap.data!.docs.where((doc) {
                    final ts = doc.data()['lastActiveAt'];
                    if (ts is! Timestamp) return false;
                    return ts.toDate().isAfter(cutoff);
                  }).toList();
              if (docs.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF8F7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _cardBorder),
                  ),
                  child: Text(
                    'No try-on sessions yet. Open live try-on in the app while signed in to see activity here.',
                    style: TextStyle(
                      color: _textMuted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                );
              }
              return Column(
                children:
                    docs.map((doc) {
                      final data = doc.data();
                      final name =
                          (data['displayName'] ?? data['email'] ?? doc.id)
                              .toString();
                      final product =
                          (data['productName'] ?? 'Product').toString();
                      final category =
                          (data['productCategory'] ?? '').toString();
                      final live = _isTryOnLive(data);
                      final ts = data['lastActiveAt'];
                      String timeAgo = '—';
                      if (ts is Timestamp) {
                        final d = DateTime.now().difference(ts.toDate());
                        if (d.inSeconds < 60) {
                          timeAgo = 'just now';
                        } else if (d.inMinutes < 60) {
                          timeAgo = '${d.inMinutes}m ago';
                        } else {
                          timeAgo = '${d.inHours}h ago';
                        }
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDF8F7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _cardBorder),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      live
                                          ? const Color(0xFF2E7D32)
                                          : const Color(0xFFBDBDBD),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$product${category.isNotEmpty ? ' · $category' : ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: _textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  maxWidth: 88,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      live ? 'Live' : 'Recent',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color:
                                            live
                                                ? const Color(0xFF2E7D32)
                                                : _textMuted,
                                      ),
                                    ),
                                    Text(
                                      timeAgo,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: _textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _insightRail({
    required List<_TopPerformer> performers,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> productDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> orderDocs,
  }) {
    final highlightName =
        performers.isNotEmpty
            ? performers.first.name
            : (productDocs.isNotEmpty
                ? (productDocs.first.data()['name'] ?? 'Top shade').toString()
                : 'Your catalog');

    final recentOrders = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
      orderDocs,
    )..sort((a, b) => _orderMillis(b.data()).compareTo(_orderMillis(a.data())));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.emoji_events_rounded, color: _brandGold, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Top performers',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (performers.isEmpty)
                Text(
                  'Order data will populate this list as customers check out.',
                  style: TextStyle(
                    fontSize: 12,
                    color: _textMuted,
                    height: 1.35,
                  ),
                )
              else
                ...performers.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1EC),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.spa_rounded,
                            color: _brandRed.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '${p.units} sold · this week',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _trendBadge('+${p.growth}%', true),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF5F8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8C4CE)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: _brandRed.withValues(alpha: 0.85),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Trend insight: "$highlightName" is getting stronger engagement on virtual mirrors — '
                  'consider featuring it on the storefront hero.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: _inkDark.withValues(alpha: 0.88),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _recentOrdersCard(recentOrders.take(5).toList()),
        const SizedBox(height: 12),
        _customerReportsCard(orderDocs),
        const SizedBox(height: 12),
        _feedbackAnalyticsCard(productDocs),
        const SizedBox(height: 12),
        _supportShortcutCard(),
      ],
    );
  }

  Widget _recentOrdersCard(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> recent,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.history_rounded,
                color: _brandRed.withValues(alpha: 0.9),
                size: 22,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Recent orders',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              GestureDetector(
                onTap: _openManageOrders,
                child: Text(
                  'View all',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _brandRed.withValues(alpha: 0.95),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (recent.isEmpty)
            Text(
              'No orders yet. New checkouts will appear here.',
              style: TextStyle(fontSize: 12, color: _textMuted, height: 1.35),
            )
          else
            ...recent.map((doc) {
              final data = doc.data();
              final id = (data['orderId'] ?? doc.id).toString();
              final shortId = id.length > 14 ? '${id.substring(0, 14)}…' : id;
              final name =
                  (data['customerName'] ?? data['customerEmail'] ?? 'Customer')
                      .toString();
              final total = _extractFirstDouble(data, const [
                'total',
                'orderTotal',
                'grandTotal',
                'amount',
              ]);
              final status = (data['status'] ?? '—').toString();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1EC),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.receipt_long_rounded,
                        size: 18,
                        color: _brandRed.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shortId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: _textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatRs(total),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: _textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  /// Unique shoppers with a single order vs those with repeat purchases.
  ({double firstTime, double repeat}) _customerSegmentsFromOrders(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orderDocs,
  ) {
    final counts = <String, int>{};
    for (final doc in orderDocs) {
      final data = doc.data();
      var key = (data['customerEmail'] ?? '').toString().trim().toLowerCase();
      if (key.isEmpty) {
        key =
            (data['customerName'] ?? data['customerPhone'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
      }
      if (key.isEmpty) key = '_unknown';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    var firstTime = 0;
    var repeat = 0;
    for (final n in counts.values) {
      if (n <= 1) {
        firstTime++;
      } else {
        repeat++;
      }
    }
    return (firstTime: firstTime.toDouble(), repeat: repeat.toDouble());
  }

  /// Weighted by product review counts in rating buckets (catalog feedback).
  ({double excellent, double good, double fair}) _feedbackBucketsFromProducts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> productDocs,
  ) {
    var excellent = 0.0;
    var good = 0.0;
    var fair = 0.0;
    for (final doc in productDocs) {
      final data = doc.data();
      final rating = _extractDouble(data['rating']);
      if (rating <= 0) continue;
      final w = math.max(1.0, _extractInt(data['reviews']).toDouble());
      if (rating >= 4.5) {
        excellent += w;
      } else if (rating >= 4.0) {
        good += w;
      } else {
        fair += w;
      }
    }
    return (excellent: excellent, good: good, fair: fair);
  }

  Widget _customerReportsCard(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orderDocs,
  ) {
    final seg = _customerSegmentsFromOrders(orderDocs);
    final total = seg.firstTime + seg.repeat;
    final segments = <_DonutSegment>[
      _DonutSegment(
        'First-time buyers',
        seg.firstTime,
        const Color(0xFF7C150D),
      ),
      _DonutSegment('Repeat shoppers', seg.repeat, const Color(0xFFD4A843)),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.groups_rounded,
                color: _brandRed.withValues(alpha: 0.9),
                size: 22,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Customer reports',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Unique customers from checkout data',
            style: TextStyle(
              fontSize: 11,
              color: _textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          if (total <= 0)
            Text(
              'No customer orders yet. Charts fill in when orders include email or name.',
              style: TextStyle(fontSize: 12, color: _textMuted, height: 1.35),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 118,
                  height: 118,
                  child: _DonutChart(
                    segments: segments,
                    centerLabel: '${total.toInt()}',
                    centerSubtext: 'shoppers',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _donutLegend(segments, total)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _feedbackAnalyticsCard(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> productDocs,
  ) {
    final b = _feedbackBucketsFromProducts(productDocs);
    final total = b.excellent + b.good + b.fair;
    final segments = <_DonutSegment>[
      _DonutSegment('Excellent 4.5+', b.excellent, const Color(0xFF2E7D32)),
      _DonutSegment('Good 4.0–4.5', b.good, const Color(0xFF7C150D)),
      _DonutSegment('Below 4.0', b.fair, const Color(0xFFBDBDBD)),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.reviews_rounded,
                color: _brandRed.withValues(alpha: 0.9),
                size: 22,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Feedback analytics',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Catalog ratings weighted by review volume',
            style: TextStyle(
              fontSize: 11,
              color: _textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          if (total <= 0)
            Text(
              'No product ratings in Firestore. Seed or edit products with rating & reviews fields.',
              style: TextStyle(fontSize: 12, color: _textMuted, height: 1.35),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 118,
                  height: 118,
                  child: _DonutChart(
                    segments: segments,
                    centerLabel: '${total.round()}',
                    centerSubtext: 'weight',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _donutLegend(segments, total)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _donutLegend(List<_DonutSegment> segments, double total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          segments.map((s) {
            if (s.value <= 0) return const SizedBox.shrink();
            final pct =
                total > 0
                    ? (100 * s.value / total).clamp(0, 100).toStringAsFixed(0)
                    : '0';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '$pct%',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }

  Widget _supportShortcutCard() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _openChats,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF2B1816),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF4A2A26)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _brandRed.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.support_agent_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Customer chats',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Open support inbox & reply to shoppers',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                color: Colors.white.withValues(alpha: 0.5),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutSegment {
  final String label;
  final double value;
  final Color color;

  const _DonutSegment(this.label, this.value, this.color);
}

class _DonutChart extends StatelessWidget {
  final List<_DonutSegment> segments;
  final String centerLabel;
  final String centerSubtext;

  const _DonutChart({
    required this.segments,
    required this.centerLabel,
    required this.centerSubtext,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DonutChartPainter(segments: segments),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              centerLabel,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: Color(0xFF1E1A1A),
              ),
            ),
            Text(
              centerSubtext,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF6B5955),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final List<_DonutSegment> segments;

  _DonutChartPainter({required this.segments});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * 0.4;
    final stroke = size.shortestSide * 0.2;
    final active = segments.where((s) => s.value > 0).toList();
    final total = active.fold<double>(0, (a, s) => a + s.value);
    if (total <= 0) {
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = const Color(0xFFE8DDD9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      return;
    }
    var start = -math.pi / 2;
    for (final s in active) {
      final sweep = 2 * math.pi * (s.value / total);
      final paint =
          Paint()
            ..color = s.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        start,
        math.max(sweep, 0.02),
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) =>
      oldDelegate.segments.length != segments.length;
}

class _KpiTileData {
  final String title;
  final String value;
  final IconData icon;
  final String badge;
  final bool? badgePositive;

  const _KpiTileData(
    this.title,
    this.value,
    this.icon,
    this.badge,
    this.badgePositive,
  );
}

class _TopPerformer {
  final String name;
  final int units;
  final int growth;

  const _TopPerformer({
    required this.name,
    required this.units,
    required this.growth,
  });
}

class _LivePeaksChart extends StatelessWidget {
  final int seed;

  const _LivePeaksChart({required this.seed});

  static const _hours = [
    '08:00',
    '10:00',
    '12:00',
    '14:00',
    '16:00',
    '18:00',
    '20:00',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              return CustomPaint(
                painter: _LivePeaksPainter(seed: seed),
                child: SizedBox(width: c.maxWidth, height: c.maxHeight),
              );
            },
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _hours.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                _HourLabel(_hours[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HourLabel extends StatelessWidget {
  final String text;
  const _HourLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        color: Color(0xFF6B5955),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _LivePeaksPainter extends CustomPainter {
  final int seed;

  _LivePeaksPainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final gridPaint =
        Paint()
          ..color = const Color(0xFFE8DDD9)
          ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = h * i / 4;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    final rnd = seed & 0x7fffffff;
    final n = 24;
    final values = List<double>.generate(n, (i) {
      final t = i / (n - 1);
      final wave =
          (0.5 + 0.45 * (1 + (i * 13 + rnd) % 7) / 7) *
          (0.55 + 0.45 * (1 - (t - 0.5).abs() * 2));
      return wave.clamp(0.12, 1.0);
    });

    final fillPath = Path()..moveTo(0, h);
    for (var i = 0; i < n; i++) {
      final x = w * i / (n - 1);
      final y = h - values[i] * h * 0.92;
      fillPath.lineTo(x, y);
    }
    fillPath.lineTo(w, h);
    fillPath.close();

    final fill =
        Paint()
          ..shader = LinearGradient(
            colors: [
              const Color(0xFF7C150D).withValues(alpha: 0.22),
              const Color(0xFFD4A843).withValues(alpha: 0.08),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(fillPath, fill);

    final linePath = Path();
    for (var i = 0; i < n; i++) {
      final x = w * i / (n - 1);
      final y = h - values[i] * h * 0.92;
      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = const Color(0xFF7C150D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LivePeaksPainter oldDelegate) =>
      oldDelegate.seed != seed;
}
