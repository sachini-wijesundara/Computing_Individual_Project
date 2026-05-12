import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/delivery_staff_service.dart';
import 'delivery_staff_order_detail_screen.dart';
import 'delivery_staff_profile_screen.dart';
import '../../utils/price_format.dart';

class DeliveryStaffHomeScreen extends StatefulWidget {
  const DeliveryStaffHomeScreen({super.key});

  @override
  State<DeliveryStaffHomeScreen> createState() =>
      _DeliveryStaffHomeScreenState();
}

class _DeliveryStaffHomeScreenState extends State<DeliveryStaffHomeScreen> {
  static const _brand = Color(0xFF7C150D);
  String _tab = 'Assigned';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3F2),
      appBar: AppBar(
        title: const Text('Delivery Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DeliveryStaffProfileScreen(),
                ),
              );
            },
            icon: const Icon(Icons.person_outline_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh_rounded),
          ),
          TextButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            child: const Text('Logout'),
          ),
        ],
      ),
      body: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: DeliveryStaffService.instance.assignedOrdersStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data ?? const [];
          final deliveredToday = DeliveryStaffService.instance
              .deliveredTodayCount(all);
          final assignedCount =
              all.where((d) => _deliveryStatus(d.data()) == 'assigned').length;
          final activeCount =
              all.where((d) {
                final s = _deliveryStatus(d.data());
                return s == 'accepted' ||
                    s == 'picked_up' ||
                    s == 'out_for_delivery';
              }).length;
          final completedCount =
              all.where((d) => _deliveryStatus(d.data()) == 'delivered').length;
          final visible = all.where((doc) => _tabMatch(doc.data())).toList();
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: DeliveryStaffService.instance.currentProfileStream(),
            builder: (context, profileSnap) {
              final profile =
                  profileSnap.data?.data() ?? const <String, dynamic>{};
              final walletBalance = _toDouble(profile['deliveryWalletBalance']);
              final pendingCash = _toDouble(profile['deliveryPendingCash']);
              final handoverTotal = _toDouble(
                profile['deliveryCashHandoverTotal'],
              );
              final staffName =
                  (profile['displayName'] ??
                          profile['staffName'] ??
                          FirebaseAuth.instance.currentUser?.displayName ??
                          'Delivery Staff')
                      .toString();
              return Column(
                children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF3F0D0A),
                          Color(0xFF7C150D),
                          Color(0xFFA32A1F),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _brand.withValues(alpha: 0.28),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.local_shipping_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Hello, $staffName',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Today delivered: $deliveredToday order(s)',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.96),
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _statCard(
                            'Assigned Orders',
                            '$assignedCount',
                            Icons.assignment_rounded,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _statCard(
                            'On The Road',
                            '$activeCount',
                            Icons.delivery_dining_rounded,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _statCard(
                            'Completed',
                            '$completedCount',
                            Icons.task_alt_rounded,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Container(
                      width: double.infinity,
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
                            'Delivery Wallet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _walletTile(
                                  'Wallet Balance',
                                  formatRs(walletBalance),
                                  Icons.account_balance_wallet_rounded,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _walletTile(
                                  'Pending Cash',
                                  formatRs(pendingCash),
                                  Icons.payments_rounded,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _walletTile(
                                  'Handover Total',
                                  formatRs(handoverTotal),
                                  Icons.receipt_long_rounded,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Hand over cash to the office once at the end of your shift (all COD orders combined).',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: _brand,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              onPressed:
                                  pendingCash <= 0
                                      ? null
                                      : () => _promptEndOfDayHandover(
                                        context,
                                        pendingCash,
                                      ),
                              icon: const Icon(
                                Icons.savings_outlined,
                                size: 20,
                              ),
                              label: const Text('Hand over cash (end of day)'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE9DDDA)),
                      ),
                      child: Row(
                        children:
                            ['Assigned', 'Active', 'Completed']
                                .map(
                                  (t) => Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      child: _segTab(
                                        t,
                                        selected: _tab == t,
                                        onTap: () => setState(() => _tab = t),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                  ),
                  Expanded(
                    child:
                        visible.isEmpty
                            ? Center(
                              child: Container(
                                margin: const EdgeInsets.all(16),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0xFFE9DDDA),
                                  ),
                                ),
                                child: const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.assignment_turned_in_outlined,
                                      size: 34,
                                      color: Color(0xFF7C150D),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'No deliveries in this tab.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                              itemCount: visible.length,
                              separatorBuilder:
                                  (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final doc = visible[i];
                                final d = doc.data();
                                final customerName = _customerName(d);
                                final customerPhone = _customerPhone(d);
                                final address = _address(d);
                                final deliveryStatus = _deliveryStatus(d);
                                final orderStatus =
                                    (d['status'] ?? '').toString();
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(0xFFE9DDDA),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.03,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 46,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: _brand.withValues(alpha: 0.75),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              customerName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _statusChip(deliveryStatus),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Order #${doc.id}',
                                        style: const TextStyle(
                                          color: Colors.black54,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _infoLine(
                                        Icons.phone_rounded,
                                        customerPhone.isEmpty
                                            ? '-'
                                            : customerPhone,
                                      ),
                                      const SizedBox(height: 6),
                                      _infoLine(
                                        Icons.location_on_outlined,
                                        address.isEmpty ? '-' : address,
                                      ),
                                      if (orderStatus.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        _infoLine(
                                          Icons.inventory_2_outlined,
                                          'Order status: $orderStatus',
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: _brand,
                                            foregroundColor: Colors.white,
                                          ),
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder:
                                                    (_) =>
                                                        DeliveryStaffOrderDetailScreen(
                                                          orderDoc: doc,
                                                        ),
                                              ),
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.open_in_new_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('Open Details'),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
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

  bool _tabMatch(Map<String, dynamic> d) {
    final s = _deliveryStatus(d);
    if (_tab == 'Assigned') {
      return s == 'assigned' ||
          s == 'accepted' ||
          s == 'picked_up' ||
          s == 'out_for_delivery';
    }
    if (_tab == 'Completed') return s == 'delivered';
    return s == 'accepted' || s == 'picked_up' || s == 'out_for_delivery';
  }

  String _deliveryStatus(Map<String, dynamic> d) {
    final s = (d['deliveryStatus'] ?? '').toString().trim();
    if (s.isNotEmpty) return s;
    final hasAssignee =
        (d['deliveryStaffId'] ??
                d['deliveryStaffUid'] ??
                d['deliveryStaffEmailLower'] ??
                '')
            .toString()
            .trim()
            .isNotEmpty;
    if (hasAssignee) return 'assigned';
    final order = (d['status'] ?? '').toString().toLowerCase();
    if (order.contains('deliver')) return 'delivered';
    if (order.contains('ship')) return 'out_for_delivery';
    return 'assigned';
  }

  String _customerName(Map<String, dynamic> d) {
    return (d['customerName'] ?? d['name'] ?? d['fullName'] ?? 'Customer')
        .toString();
  }

  String _customerPhone(Map<String, dynamic> d) {
    return (d['customerPhone'] ?? d['phone'] ?? d['mobile'] ?? '').toString();
  }

  String _address(Map<String, dynamic> d) {
    return (d['shippingAddress'] ?? d['address'] ?? d['deliveryAddress'] ?? '')
        .toString();
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE9DDDA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _brand),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final label = status.replaceAll('_', ' ');
    Color bg = const Color(0xFFEFF2FA);
    Color fg = const Color(0xFF4A5570);
    if (status == 'delivered') {
      bg = const Color(0xFFE8F7EC);
      fg = const Color(0xFF1E8E4A);
    } else if (status == 'failed_delivery') {
      bg = const Color(0xFFFFECEC);
      fg = const Color(0xFFB3261E);
    } else if (status == 'out_for_delivery') {
      bg = const Color(0xFFE9F3FF);
      fg = const Color(0xFF235EA9);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _infoLine(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.black54),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.black87),
          ),
        ),
      ],
    );
  }

  Widget _walletTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF1EE),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: _brand),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Future<void> _promptEndOfDayHandover(
    BuildContext context,
    double pendingCash,
  ) async {
    if (pendingCash <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pending cash to hand over.')),
      );
      return;
    }
    final ctrl = TextEditingController(
      text: pendingCash.toStringAsFixed(0),
    );
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: const Text('Hand over cash to office'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pending cash to settle: ${formatRs(pendingCash)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(
                        labelText: 'Amount you are handing over',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You can hand over part or all of it. Amounts over your pending balance are capped automatically.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!ok || !context.mounted) return;
    final raw = ctrl.text.trim().replaceAll(',', '');
    final amount = double.tryParse(raw) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount.')),
      );
      return;
    }
    try {
      final settled =
          await DeliveryStaffService.instance.markEndOfDayCashHandover(
            amount: amount,
          );
      if (!context.mounted) return;
      if (settled <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nothing was settled. Check pending cash.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Handover recorded: ${formatRs(settled)}',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  Widget _segTab(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFE8E1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? _brand : Colors.black87,
          ),
        ),
      ),
    );
  }
}
