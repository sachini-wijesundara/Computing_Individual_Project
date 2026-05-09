import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/order_tracking.dart';

const _kTitle = Color(0xFF1A1A1A);
const _kMuted = Color(0xFF888888);
const _kMaroon = Color(0xFF7B1B11);

class OrderDetailScreen extends StatefulWidget {
  final String orderDocId;

  const OrderDetailScreen({super.key, required this.orderDocId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  /// Stable stream instances so listeners stay attached across rebuilds (live admin updates).
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _orderStream;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userStream = FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();
      _orderStream =
          FirebaseFirestore.instance.collection('orders').doc(widget.orderDocId).snapshots();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _kTitle,
        elevation: 0.2,
        title: const Text('Order details', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: user == null
          ? const Center(child: Text('Please sign in to view this order.'))
          : _userStream == null || _orderStream == null
              ? const Center(child: CircularProgressIndicator(color: _kMaroon))
              : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _userStream,
                  builder: (context, userSnap) {
                    final checkoutEmailLowers = <String>{};
                    final ud = userSnap.data?.data();
                    final rawList = ud?['checkoutEmails'];
                    if (rawList is List) {
                      for (final x in rawList) {
                        final s = x?.toString().trim().toLowerCase();
                        if (s != null && s.isNotEmpty) checkoutEmailLowers.add(s);
                      }
                    }
                    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: _orderStream,
                      builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Could not load order.\n${snap.error}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                      return const Center(child: CircularProgressIndicator(color: _kMaroon));
                    }
                    if (!snap.hasData || !snap.data!.exists) {
                      return const Center(
                        child: Text('This order could not be found or you no longer have access.'),
                      );
                    }
                    final d = snap.data!.data()!;
                    if (!_customerCanViewOrder(
                      d,
                      user,
                      checkoutEmailsLower: checkoutEmailLowers,
                    )) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'You do not have access to this order.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    final status = displayOrderStatus(d);
                    final orderId = (d['orderId'] ?? widget.orderDocId).toString();
                    final steps = buildFulfilmentSteps(status);
                    final items = <Map<String, dynamic>>[];
                    final rawItems = d['items'];
                    if (rawItems is List) {
                      for (final e in rawItems) {
                        if (e is Map) {
                          items.add(Map<String, dynamic>.from(e));
                        }
                      }
                    }
                    final createdMs = orderCreatedAtMs(d);
                    final updatedMs = orderUpdatedAtMs(d);

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                      children: [
                        Text(
                          orderId,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _kTitle),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          createdMs > 0
                              ? 'Placed ${_formatDt(createdMs)}'
                              : 'Order date pending',
                          style: const TextStyle(color: _kMuted, fontSize: 14),
                        ),
                        if (updatedMs != null && updatedMs != createdMs) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Last update ${_formatDt(updatedMs)}',
                            style: const TextStyle(color: _kMuted, fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _SectionTitle(title: 'Tracking', icon: Icons.route_rounded),
                        const SizedBox(height: 10),
                        _TrackingCard(status: status, steps: steps),
                        const SizedBox(height: 22),
                        _SectionTitle(title: 'Delivery', icon: Icons.location_on_outlined),
                        const SizedBox(height: 10),
                        _InfoCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (d['customerName'] ?? '').toString().isEmpty
                                    ? '—'
                                    : (d['customerName'] ?? '').toString(),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${(d['address'] ?? '').toString()}\n${(d['city'] ?? '').toString()}',
                                style: const TextStyle(color: _kMuted, height: 1.45),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                (d['customerPhone'] ?? '').toString(),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        _SectionTitle(title: 'Items', icon: Icons.shopping_bag_outlined),
                        const SizedBox(height: 10),
                        _InfoCard(
                          child: Column(
                            children: [
                              for (var i = 0; i < items.length; i++) ...[
                                if (i > 0) const Divider(height: 18),
                                _ItemLine(item: items[i]),
                              ],
                              if (items.isEmpty)
                                const Text('No line items recorded.', style: TextStyle(color: _kMuted)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        _SectionTitle(title: 'Payment', icon: Icons.payments_outlined),
                        const SizedBox(height: 10),
                        _InfoCard(
                          child: Column(
                            children: [
                              _MoneyRow('Subtotal', _readNum(d['subtotal'])),
                              _MoneyRow('Discount', _readNum(d['discount'])),
                              const Divider(height: 20),
                              _MoneyRow('Total', orderTotalAmount(d), emphasize: true),
                              const SizedBox(height: 8),
                              Text(
                                (d['paymentMethod'] ?? '').toString(),
                                style: const TextStyle(color: _kMuted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }

  static String _formatDt(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  static double _readNum(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  /// Matches Firestore rules: uid, account email, phone, or checkout email saved on user profile.
  static bool _customerCanViewOrder(
    Map<String, dynamic> d,
    User user, {
    Set<String> checkoutEmailsLower = const {},
  }) {
    if (d['userId'] == user.uid) return true;

    final orderLowerField = (d['customerEmailLower'] ?? '').toString().trim().toLowerCase();
    final orderFromRaw =
        (d['customerEmail'] ?? d['email'] ?? '').toString().trim().toLowerCase();
    if (orderLowerField.isNotEmpty && checkoutEmailsLower.contains(orderLowerField)) {
      return true;
    }
    if (orderFromRaw.isNotEmpty && checkoutEmailsLower.contains(orderFromRaw)) {
      return true;
    }

    final authEmail = user.email?.trim();
    if (authEmail != null && authEmail.isNotEmpty) {
      final authLower = authEmail.toLowerCase();
      final orderEmail = (d['customerEmail'] ?? d['email'] ?? '').toString().trim();
      final orderLower = (d['customerEmailLower'] ?? '').toString().trim();
      if (orderLower.isNotEmpty && orderLower.toLowerCase() == authLower) return true;
      if (orderEmail.isNotEmpty &&
          (orderEmail == authEmail || orderEmail.toLowerCase() == authLower)) {
        return true;
      }
    }

    final authPhone = user.phoneNumber?.trim();
    if (authPhone != null && authPhone.isNotEmpty) {
      final orderPhone = (d['customerPhone'] ?? d['phone'] ?? '').toString().trim();
      if (orderPhone.isNotEmpty && orderPhone == authPhone) return true;
    }

    return false;
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: _kMaroon),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _kTitle),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Widget child;
  const _InfoCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: child,
    );
  }
}

class _TrackingCard extends StatelessWidget {
  final String status;
  final List<TrackingStepUi> steps;
  const _TrackingCard({required this.status, required this.steps});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9DDDA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: status == 'Cancelled' ? const Color(0xFFFFECEC) : const Color(0xFFEFF2FA),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'STATUS: ${status.toUpperCase()}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 11,
                color: status == 'Cancelled' ? const Color(0xFFB3261E) : const Color(0xFF4A5570),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(steps.length, (i) {
            final s = steps[i];
            final isLast = i == steps.length - 1;
            return _TimelineRow(step: s, showLine: !isLast);
          }),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final TrackingStepUi step;
  final bool showLine;
  const _TimelineRow({required this.step, required this.showLine});

  @override
  Widget build(BuildContext context) {
    final done = step.isComplete;
    final current = step.isCurrent;
    final color = done || current ? _kMaroon : _kMuted.withValues(alpha: 0.4);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? _kMaroon : Colors.transparent,
                border: Border.all(color: color, width: 2),
              ),
              child: done
                  ? const Icon(Icons.check, size: 10, color: Colors.white)
                  : current
                      ? Center(
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(color: _kMaroon, shape: BoxShape.circle),
                          ),
                        )
                      : null,
            ),
            if (showLine)
              Container(
                width: 2,
                height: 36,
                margin: const EdgeInsets.symmetric(vertical: 2),
                color: done ? _kMaroon.withValues(alpha: 0.35) : Colors.grey.shade300,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: showLine ? 14 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: current || done ? _kTitle : _kMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  step.subtitle,
                  style: TextStyle(fontSize: 13, color: _kMuted.withValues(alpha: 0.9), height: 1.3),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ItemLine extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ItemLine({required this.item});

  @override
  Widget build(BuildContext context) {
    final name = (item['name'] ?? '').toString();
    final qty = item['quantity'];
    final q = qty is int ? qty : int.tryParse('$qty') ?? 0;
    final price = item['price'];
    final p = price is num ? price.toDouble() : double.tryParse('$price') ?? 0;
    final shade = (item['shade'] ?? '').toString();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? 'Item' : name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (shade.isNotEmpty)
                Text(
                  shade,
                  style: const TextStyle(fontSize: 12, color: _kMuted),
                ),
            ],
          ),
        ),
        Text(
          '×$q',
          style: const TextStyle(color: _kMuted, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 12),
        Text(
          'Rs. ${(p * q).toStringAsFixed(0)}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _MoneyRow extends StatelessWidget {
  final String label;
  final double value;
  final bool emphasize;
  const _MoneyRow(this.label, this.value, {this.emphasize = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              color: emphasize ? _kTitle : _kMuted,
            ),
          ),
          Text(
            'Rs. ${value.toStringAsFixed(0)}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: emphasize ? 17 : 14,
              color: emphasize ? _kMaroon : _kTitle,
            ),
          ),
        ],
      ),
    );
  }
}
