import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'admin_dashboard_screen.dart';
import 'admin_manage_products_screen.dart';
import 'admin_manage_reviews_screen.dart';
import 'admin_manage_users_screen.dart';
import 'widgets/admin_side_panel.dart';

class AdminManageOrdersScreen extends StatefulWidget {
  final bool shellEmbedded;
  final VoidCallback? onNavigateToDashboard;
  final VoidCallback? onNavigateToProducts;
  final VoidCallback? onNavigateToReviews;
  final VoidCallback? onNavigateToUsers;

  AdminManageOrdersScreen({
    super.key,
    this.shellEmbedded = false,
    this.onNavigateToDashboard,
    this.onNavigateToProducts,
    this.onNavigateToReviews,
    this.onNavigateToUsers,
  });

  @override
  State<AdminManageOrdersScreen> createState() =>
      _AdminManageOrdersScreenState();
}

class _AdminManageOrdersScreenState extends State<AdminManageOrdersScreen> {
  static const _brand = Color(0xFF7C150D);
  static const _softBg = Color(0xFFF7F2F1);
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _status = 'All';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
                title: const Text('Manage Orders'),
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1E1A1A),
                elevation: 0.2,
                actions: [
                  IconButton(
                    tooltip: 'Sync order emails for customer app',
                    icon: const Icon(Icons.phonelink_setup_rounded),
                    onPressed: _backfillCustomerEmailLower,
                  ),
                ],
              ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('orders').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            final errWidget = Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load orders.\n${snap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
            if (!isWide) return errWidget;
            if (widget.shellEmbedded) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: errWidget,
              );
            }
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _adminPanel(),
                  const SizedBox(width: 14),
                  Expanded(child: errWidget),
                ],
              ),
            );
          }

          final waitingFirst =
              snap.connectionState == ConnectionState.waiting && !snap.hasData;
          if (waitingFirst) {
            if (!isWide) {
              return const Center(child: CircularProgressIndicator());
            }
            if (widget.shellEmbedded) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _adminPanel(),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              ),
            );
          }

          final allDocs =
              (snap.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                ..sort((a, b) {
                  final ad = a.data();
                  final bd = b.data();
                  final at = _toMillis(
                    ad['createdAt'] ?? ad['createdAtServer'] ?? ad['updatedAt'],
                  );
                  final bt = _toMillis(
                    bd['createdAt'] ?? bd['createdAtServer'] ?? bd['updatedAt'],
                  );
                  return bt.compareTo(at);
                });
          final filtered = _filterDocs(allDocs);
          final totalRevenue = filtered.fold<double>(
            0,
            (sum, d) => sum + _extractOrderTotal(d.data()),
          );
          final pendingCount =
              allDocs.where((d) => _statusOf(d.data()) == 'Pending').length;
          final deliveredCount =
              allDocs.where((d) => _statusOf(d.data()) == 'Delivered').length;

          final content = SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sales  /  Orders',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Order Management',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1D2433),
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _backfillCustomerEmailLower,
                      style: OutlinedButton.styleFrom(foregroundColor: _brand),
                      icon: const Icon(Icons.phonelink_setup_rounded),
                      label: const Text('Customer app email sync'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _brand),
                      onPressed: () => setState(() {}),
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Refresh',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _statCard(
                      'Total Orders',
                      '${allDocs.length}',
                      Icons.receipt_long_rounded,
                      const Color(0xFFFFF1EC),
                    ),
                    _statCard(
                      'Pending',
                      '$pendingCount',
                      Icons.pending_actions_rounded,
                      const Color(0xFFFFF7E0),
                    ),
                    _statCard(
                      'Delivered',
                      '$deliveredCount',
                      Icons.task_alt_rounded,
                      const Color(0xFFE7F7EC),
                    ),
                    _statCard(
                      'Revenue',
                      'Rs ${totalRevenue.toStringAsFixed(0)}',
                      Icons.payments_rounded,
                      const Color(0xFFEFF2FA),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _filterCard(),
                const SizedBox(height: 14),
                _tableCard(filtered),
              ],
            ),
          );
          if (!isWide) return content;
          if (widget.shellEmbedded) {
            return Padding(padding: const EdgeInsets.all(12), child: content);
          }
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _adminPanel(),
                const SizedBox(width: 14),
                Expanded(child: content),
              ],
            ),
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
      selected: AdminNavItem.orders,
      onDashboard: () {
        if (widget.onNavigateToDashboard != null) {
          widget.onNavigateToDashboard!();
          return;
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => AdminDashboardScreen()),
        );
      },
      onProducts: () {
        if (widget.onNavigateToProducts != null) {
          widget.onNavigateToProducts!();
          return;
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => AdminManageProductsScreen()),
        );
      },
      onOrders: () {},
      onReviews: () {
        if (widget.onNavigateToReviews != null) {
          widget.onNavigateToReviews!();
          return;
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminManageReviewsScreen()),
        );
      },
      onUsers: () {
        if (widget.onNavigateToUsers != null) {
          widget.onNavigateToUsers!();
          return;
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminManageUsersScreen()),
        );
      },
      onSignOut: () => FirebaseAuth.instance.signOut(),
    );
  }

  void _comingSoon(String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label coming soon')));
  }

  /// Backfills `customerEmailLower` on orders and `checkoutEmails` on `users/{userId}` so
  /// "My orders" works when checkout email ≠ Auth email.
  Future<void> _backfillCustomerEmailLower() async {
    try {
      final snap =
          await FirebaseFirestore.instance
              .collection('orders')
              .limit(500)
              .get();
      final profileAdds = <String, Set<String>>{};
      var batch = FirebaseFirestore.instance.batch();
      var ops = 0;
      var patchedOrders = 0;

      for (final d in snap.docs) {
        final data = d.data();
        final raw =
            (data['customerEmail'] ?? data['email'] ?? '').toString().trim();
        if (raw.isEmpty) continue;
        final lower = raw.toLowerCase();
        final uid = (data['userId'] ?? '').toString().trim();
        if (uid.isNotEmpty) {
          profileAdds.putIfAbsent(uid, () => <String>{}).add(lower);
        }

        if ((data['customerEmailLower'] ?? '').toString() != lower) {
          batch.set(d.reference, {
            'customerEmailLower': lower,
          }, SetOptions(merge: true));
          ops++;
          patchedOrders++;
          if (ops >= 400) {
            await batch.commit();
            batch = FirebaseFirestore.instance.batch();
            ops = 0;
          }
        }
      }
      if (ops > 0) await batch.commit();

      var batchUsers = FirebaseFirestore.instance.batch();
      var uOps = 0;
      var uniqueProfiles = 0;
      for (final e in profileAdds.entries) {
        batchUsers.set(
          FirebaseFirestore.instance.collection('users').doc(e.key),
          {'checkoutEmails': FieldValue.arrayUnion(e.value.toList())},
          SetOptions(merge: true),
        );
        uOps++;
        uniqueProfiles++;
        if (uOps >= 400) {
          await batchUsers.commit();
          batchUsers = FirebaseFirestore.instance.batch();
          uOps = 0;
        }
      }
      if (uOps > 0) await batchUsers.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            patchedOrders == 0 && uniqueProfiles == 0
                ? 'Nothing to update (no emails / user ids on orders).'
                : 'Orders patched: $patchedOrders. Customer profiles updated: $uniqueProfiles. They can use My orders with checkout email.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    }
  }

  Widget _filterCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE9DDDA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: 'Search by order id, customer name, or email...',
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children:
                [
                      'All',
                      'Pending',
                      'Processing',
                      'Shipped',
                      'Delivered',
                      'Cancelled',
                    ]
                    .map(
                      (s) => ChoiceChip(
                        label: Text(s),
                        selected: _status == s,
                        onSelected: (_) => setState(() => _status = s),
                      ),
                    )
                    .toList(),
          ),
        ],
      ),
    );
  }

  Widget _tableCard(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE9DDDA)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFFBF7F6),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Color(0xFFF0E8E6))),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'ORDER',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.black54,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'CUSTOMER',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.black54,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'TOTAL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.black54,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'STATUS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.black54,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'DELIVERY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.black54,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'ACTIONS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (docs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No orders match current filters.'),
            )
          else
            ...docs.map(_tableRow),
        ],
      ),
    );
  }

  Widget _tableRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final orderId = doc.id;
    final customer =
        (d['customerName'] ?? d['name'] ?? d['fullName'] ?? 'Customer')
            .toString();
    final email = (d['customerEmail'] ?? d['email'] ?? '').toString();
    final total = _extractOrderTotal(d);
    final status = _statusOf(d);
    final deliveryStatus = _deliveryStatusOf(d);
    final deliveryStaffName = _deliveryStaffNameOf(d);
    final createdText = _formatDate(
      d['createdAt'] ?? d['createdAtServer'] ?? d['updatedAt'],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF4ECEA))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#$orderId',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  createdText,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(customer, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Rs ${total.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _statusBadge(status),
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deliveryStaffName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                _deliveryBadge(deliveryStatus),
                const SizedBox(height: 4),
                Text(
                  _deliveryFlowSummary(d),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  PopupMenuButton<String>(
                    tooltip: 'Update status',
                    onSelected: (value) => _updateStatus(doc.reference, value),
                    itemBuilder:
                        (context) => const [
                          PopupMenuItem(
                            value: 'Pending',
                            child: Text('Mark Pending'),
                          ),
                          PopupMenuItem(
                            value: 'Processing',
                            child: Text('Mark Processing'),
                          ),
                          PopupMenuItem(
                            value: 'Shipped',
                            child: Text('Mark Shipped'),
                          ),
                          PopupMenuItem(
                            value: 'Delivered',
                            child: Text('Mark Delivered'),
                          ),
                          PopupMenuItem(
                            value: 'Cancelled',
                            child: Text('Mark Cancelled'),
                          ),
                        ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1EC),
                        border: Border.all(color: const Color(0xFFEECDC3)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Change',
                        style: TextStyle(
                          color: _brand,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _assignDeliveryStaff(doc),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _brand,
                      side: const BorderSide(color: Color(0xFFEECDC3)),
                    ),
                    child: const Text('Assign'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStatus(
    DocumentReference<Map<String, dynamic>> ref,
    String status,
  ) async {
    await ref.set({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Order updated to $status')));
  }

  Future<void> _assignDeliveryStaff(
    QueryDocumentSnapshot<Map<String, dynamic>> orderDoc,
  ) async {
    try {
      final staffSnap =
          await FirebaseFirestore.instance
              .collection('users')
              .where('role', isEqualTo: 'delivery_staff')
              .get();
      final staffDocs =
          staffSnap.docs.where((d) {
            final data = d.data();
            final disabled =
                data['disabled'] == true || data['isDisabled'] == true;
            return !disabled;
          }).toList();
      if (staffDocs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active delivery staff found.')),
        );
        return;
      }

      String? selectedUid =
          (orderDoc.data()['deliveryStaffId'] ?? '').toString();
      if (!staffDocs.any((d) => d.id == selectedUid)) {
        selectedUid = staffDocs.first.id;
      }
      if (!mounted) return;

      final ok =
          await showDialog<bool>(
            context: context,
            builder:
                (_) => StatefulBuilder(
                  builder:
                      (context, setStateDialog) => AlertDialog(
                        title: const Text('Assign Delivery Staff'),
                        content: DropdownButtonFormField<String>(
                          initialValue: selectedUid,
                          decoration: const InputDecoration(
                            labelText: 'Delivery staff',
                            border: OutlineInputBorder(),
                          ),
                          items:
                              staffDocs.map((doc) {
                                final data = doc.data();
                                final name =
                                    (data['displayName'] ??
                                            data['staffName'] ??
                                            data['email'] ??
                                            doc.id)
                                        .toString();
                                final email = (data['email'] ?? '').toString();
                                return DropdownMenuItem(
                                  value: doc.id,
                                  child: Text(
                                    email.isEmpty ? name : '$name ($email)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                          onChanged:
                              (v) => setStateDialog(() => selectedUid = v),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _brand,
                            ),
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                ),
          ) ??
          false;
      if (!ok || selectedUid == null || selectedUid!.isEmpty) return;
      final selectedDoc = staffDocs.firstWhere((d) => d.id == selectedUid);
      final selectedData = selectedDoc.data();
      final staffName =
          (selectedData['displayName'] ??
                  selectedData['staffName'] ??
                  selectedData['email'] ??
                  selectedUid)
              .toString();
      final staffEmail = (selectedData['email'] ?? '').toString().trim();

      await orderDoc.reference.set({
        'deliveryStaffId': selectedUid,
        'deliveryStaffUid': selectedUid,
        'deliveryStaffName': staffName,
        'deliveryStaffEmail': staffEmail,
        'deliveryStaffEmailLower': staffEmail.toLowerCase(),
        'deliveryStatus': 'assigned',
        'deliveryAssignedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Assigned to $staffName')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Assign failed: $e')));
    }
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final q = _search.trim().toLowerCase();
    return docs.where((doc) {
      final d = doc.data();
      final status = _statusOf(d);
      final name =
          (d['customerName'] ?? d['name'] ?? d['fullName'] ?? '')
              .toString()
              .toLowerCase();
      final email =
          (d['customerEmail'] ?? d['email'] ?? '').toString().toLowerCase();
      final orderId = doc.id.toLowerCase();
      final matchSearch =
          q.isEmpty ||
          name.contains(q) ||
          email.contains(q) ||
          orderId.contains(q);
      final matchStatus = _status == 'All' || status == _status;
      return matchSearch && matchStatus;
    }).toList();
  }

  String _statusOf(Map<String, dynamic> d) {
    final raw = (d['status'] ?? d['orderStatus'] ?? '').toString().trim();
    if (raw.isEmpty) return 'Pending';
    final lower = raw.toLowerCase();
    if (lower.contains('process')) return 'Processing';
    if (lower.contains('ship')) return 'Shipped';
    if (lower.contains('deliver')) return 'Delivered';
    if (lower.contains('cancel')) return 'Cancelled';
    if (lower.contains('pend')) return 'Pending';
    return raw[0].toUpperCase() + raw.substring(1);
  }

  double _extractOrderTotal(Map<String, dynamic> d) {
    for (final key in const [
      'total',
      'orderTotal',
      'grandTotal',
      'amount',
      'totalAmount',
      'subtotal',
    ]) {
      final value = d[key];
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return 0;
  }

  int _toMillis(dynamic v) {
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    if (v is int) return v;
    return 0;
  }

  String _formatDate(dynamic v) {
    final ms = _toMillis(v);
    if (ms <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _statusBadge(String status) {
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }

  String _deliveryStaffNameOf(Map<String, dynamic> data) {
    final raw =
        (data['deliveryStaffName'] ??
                data['deliveryStaffEmail'] ??
                data['deliveryStaffId'] ??
                '')
            .toString()
            .trim();
    return raw.isEmpty ? 'Unassigned' : raw;
  }

  String _deliveryStatusOf(Map<String, dynamic> data) {
    final raw = (data['deliveryStatus'] ?? '').toString().trim();
    return raw.isEmpty ? 'unassigned' : raw;
  }

  Widget _deliveryBadge(String status) {
    final normalized = status.toLowerCase();
    late Color bg;
    late Color fg;
    switch (normalized) {
      case 'delivered':
        bg = const Color(0xFFE8F7EC);
        fg = const Color(0xFF1E8E4A);
        break;
      case 'out_for_delivery':
      case 'picked_up':
      case 'accepted':
        bg = const Color(0xFFE9F3FF);
        fg = const Color(0xFF235EA9);
        break;
      case 'failed_delivery':
        bg = const Color(0xFFFFECEC);
        fg = const Color(0xFFB3261E);
        break;
      case 'assigned':
        bg = const Color(0xFFFFF7E0);
        fg = const Color(0xFF9C6C00);
        break;
      default:
        bg = const Color(0xFFEFF2FA);
        fg = const Color(0xFF4A5570);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        normalized.replaceAll('_', ' ').toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }

  String _deliveryFlowSummary(Map<String, dynamic> data) {
    final collected = data['orderCollectedFromStore'] == true;
    final delivered = data['orderDeliveredByStaff'] == true;
    final cashCollected = data['cashCollectedSuccessfully'] == true;
    final handover = data['cashHandoverDone'] == true;
    final parts = <String>[];
    if (collected) parts.add('Collected');
    if (delivered) parts.add('Delivered');
    if (cashCollected) parts.add('Cash collected');
    if (handover) parts.add('Cash handover');
    if (parts.isEmpty) return 'No delivery actions yet';
    return parts.join(' · ');
  }

  Widget _statCard(String label, String value, IconData icon, Color iconBg) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE9DDDA)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: _brand),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
