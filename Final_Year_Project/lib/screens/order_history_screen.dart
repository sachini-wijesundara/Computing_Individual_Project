import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/order_tracking.dart';
import 'order_detail_screen.dart';

const _bgTop = Color(0xFFF5F5F5);
const _bgMid = Color(0xFFF1ABAD);
const _bgBot = Color(0xFFF7BDBD);
const _ink = Color(0xFF121212);
const _maroon = Color(0xFF7C150D);

class OrderHistoryScreen extends StatefulWidget {
  final bool showBackButton;
  const OrderHistoryScreen({super.key, this.showBackButton = true});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  User? _user;
  Set<String> _emails = {};
  Set<String> _phones = {};
  bool _keysLoaded = false;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    if (_user != null) {
      _loadQueryKeys(_user!);
    }
  }

  Future<void> _loadQueryKeys(User user) async {
    final emails = <String>{};
    void addEmail(String? v) {
      final t = v?.trim();
      if (t == null || t.isEmpty) return;
      emails.add(t);
      final lower = t.toLowerCase();
      if (lower != t) emails.add(lower);
    }

    addEmail(user.email);
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final d = doc.data();
      addEmail(d?['email']?.toString());
      addEmail(d?['userEmail']?.toString());
      final checkoutList = d?['checkoutEmails'];
      if (checkoutList is List) {
        for (final x in checkoutList) {
          addEmail(x?.toString());
        }
      }
    } catch (_) {
      // Profile optional; auth email / phone still used for order queries.
    }

    // Must match Firestore rules (exact token.phone_number); no alternate formats here.
    final phones = <String>{};
    final pn = user.phoneNumber?.trim();
    if (pn != null && pn.isNotEmpty) phones.add(pn);

    if (!mounted) return;
    setState(() {
      _emails = emails;
      _phones = phones;
      _keysLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) {
      return _signInRequired(context);
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bgTop, _bgMid, _bgBot],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: _ink,
          leading: widget.showBackButton
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
          title: const Text(
            'My orders',
            style: TextStyle(fontWeight: FontWeight.w800, color: _ink),
          ),
        ),
        body: !_keysLoaded
            ? const Center(child: CircularProgressIndicator(color: _maroon))
            : _MergedOrdersList(
                uid: user.uid,
                emails: _emails,
                phones: _phones,
              ),
      ),
    );
  }

  Widget _signInRequired(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bgTop, _bgMid, _bgBot],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: _ink,
          leading: widget.showBackButton
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
          title: const Text('My orders', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 56, color: _maroon),
                const SizedBox(height: 16),
                const Text(
                  'Sign in to see your orders',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink),
                ),
                const SizedBox(height: 8),
                Text(
                  'Order history and delivery tracking are available after you log in.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _ink.withValues(alpha: 0.65), height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Merges several Firestore queries (userId, customerEmail, legacy email, phone).
class _MergedOrdersList extends StatefulWidget {
  final String uid;
  final Set<String> emails;
  final Set<String> phones;

  const _MergedOrdersList({
    required this.uid,
    required this.emails,
    required this.phones,
  });

  @override
  State<_MergedOrdersList> createState() => _MergedOrdersListState();
}

class _MergedOrdersListState extends State<_MergedOrdersList> {
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _subs = [];
  final List<QuerySnapshot<Map<String, dynamic>>?> _snaps = [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    void listenTo(Query<Map<String, dynamic>> q) {
      final idx = _snaps.length;
      _snaps.add(null);
      _subs.add(
        q.snapshots().listen(
          (snap) => setState(() {
            _snaps[idx] = snap;
            _error = null;
          }),
          onError: (e) => setState(() => _error = e),
        ),
      );
    }

    final col = FirebaseFirestore.instance.collection('orders');
    listenTo(col.where('userId', isEqualTo: widget.uid));

    for (final e in widget.emails) {
      listenTo(col.where('customerEmail', isEqualTo: e));
      listenTo(col.where('email', isEqualTo: e));
    }
    final emailLowers = widget.emails.map((e) => e.toLowerCase()).toSet()..remove('');
    for (final l in emailLowers) {
      listenTo(col.where('customerEmailLower', isEqualTo: l));
    }
    for (final p in widget.phones) {
      listenTo(col.where('customerPhone', isEqualTo: p));
      listenTo(col.where('phone', isEqualTo: p));
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _mergedDocs() {
    final map = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final snap in _snaps) {
      if (snap == null) continue;
      for (final d in snap.docs) {
        map[d.id] = d;
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => orderCreatedAtMs(b.data()).compareTo(orderCreatedAtMs(a.data())));
    return list;
  }

  bool get _allStreamsHaveSnapshot => _snaps.every((s) => s != null);

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load orders.\n$_error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink),
          ),
        ),
      );
    }

    if (!_allStreamsHaveSnapshot) {
      return const Center(child: CircularProgressIndicator(color: _maroon));
    }

    final docs = _mergedDocs();

    if (docs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long_outlined, size: 64, color: _ink.withValues(alpha: 0.35)),
              const SizedBox(height: 16),
              Text(
                'No orders yet',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _ink.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'We look up orders by your account id, email, and phone. '
                'Use the same details at checkout as on this account, or open the order in Firebase and set '
                'userId, customerEmail, or customerPhone to match.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _ink.withValues(alpha: 0.6), height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        return _LiveOrderListTile(initialDoc: docs[i]);
      },
    );
  }
}

/// One stable document listener per row so status/total update when admin changes the order.
class _LiveOrderListTile extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> initialDoc;

  const _LiveOrderListTile({required this.initialDoc});

  @override
  State<_LiveOrderListTile> createState() => _LiveOrderListTileState();
}

class _LiveOrderListTileState extends State<_LiveOrderListTile> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _orderStream;

  @override
  void initState() {
    super.initState();
    _orderStream =
        FirebaseFirestore.instance.collection('orders').doc(widget.initialDoc.id).snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _orderStream,
      builder: (context, live) {
        final d = (live.hasData && live.data != null && live.data!.exists)
            ? live.data!.data()!
            : widget.initialDoc.data();
        final orderId = (d['orderId'] ?? widget.initialDoc.id).toString();
        final status = displayOrderStatus(d);
        final total = orderTotalAmount(d);
        final ms = orderCreatedAtMs(d);
        final dateStr = ms > 0
            ? '${DateTime.fromMillisecondsSinceEpoch(ms).year}-${DateTime.fromMillisecondsSinceEpoch(ms).month.toString().padLeft(2, '0')}-${DateTime.fromMillisecondsSinceEpoch(ms).day.toString().padLeft(2, '0')}'
            : '';

        return Material(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OrderDetailScreen(orderDocId: widget.initialDoc.id),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1EC),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.local_shipping_outlined, color: _maroon),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          orderId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateStr.isEmpty ? 'Date pending' : 'Placed $dateStr',
                          style: TextStyle(fontSize: 13, color: _ink.withValues(alpha: 0.55)),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _StatusPill(status: status),
                      const SizedBox(height: 6),
                      Text(
                        'Rs. ${total.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: _maroon),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, color: _ink.withValues(alpha: 0.35)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    switch (status) {
      case 'Delivered':
        bg = const Color(0xFFE8F7EC);
        fg = const Color(0xFF1E8E4A);
        break;
      case 'Cancelled':
        bg = const Color(0xFFFFECEC);
        fg = const Color(0xFFB3261E);
        break;
      case 'Shipped':
        bg = const Color(0xFFE9F3FF);
        fg = const Color(0xFF235EA9);
        break;
      case 'Processing':
        bg = const Color(0xFFFFF7E0);
        fg = const Color(0xFF9C6C00);
        break;
      default:
        bg = const Color(0xFFEFF2FA);
        fg = const Color(0xFF4A5570);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }
}
