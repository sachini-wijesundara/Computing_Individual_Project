import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../firebase_options.dart';
import 'admin_dashboard_screen.dart';
import 'admin_manage_orders_screen.dart';
import 'admin_manage_products_screen.dart';
import 'admin_manage_reviews_screen.dart';
import 'widgets/admin_side_panel.dart';

class AdminManageUsersScreen extends StatefulWidget {
  final bool shellEmbedded;
  final VoidCallback? onNavigateToDashboard;
  final VoidCallback? onNavigateToProducts;
  final VoidCallback? onNavigateToOrders;
  final VoidCallback? onNavigateToReviews;

  const AdminManageUsersScreen({
    super.key,
    this.shellEmbedded = false,
    this.onNavigateToDashboard,
    this.onNavigateToProducts,
    this.onNavigateToOrders,
    this.onNavigateToReviews,
  });

  @override
  State<AdminManageUsersScreen> createState() => _AdminManageUsersScreenState();
}

class _AdminManageUsersScreenState extends State<AdminManageUsersScreen> {
  static const _softBg = Color(0xFFF7F2F1);
  static const _brand = Color(0xFF7C150D);
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _filter = 'All';
  bool _creatingDeliveryStaff = false;

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
                title: const Text('Manage Users'),
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1E1A1A),
                elevation: 0.2,
              ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snap) {
          final allDocs = snap.data?.docs ?? const [];
          final filtered = _filterDocs(allDocs);
          final admins = allDocs.where((d) => _isAdmin(d.data())).length;
          final deliveryStaff =
              allDocs.where((d) => _isDeliveryStaff(d.data())).length;
          final active = allDocs.where((d) => _isActive(d.data())).length;
          final disabled = allDocs.length - active;

          Widget content = SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Manage Users',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1D2433),
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _brand),
                      onPressed:
                          _creatingDeliveryStaff
                              ? null
                              : _openCreateDeliveryStaffDialog,
                      icon:
                          _creatingDeliveryStaff
                              ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Add Delivery Staff'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _statCard(
                      'Total users',
                      '${allDocs.length}',
                      Icons.people_alt_rounded,
                    ),
                    _statCard(
                      'Admins',
                      '$admins',
                      Icons.admin_panel_settings_rounded,
                    ),
                    _statCard(
                      'Delivery staff',
                      '$deliveryStaff',
                      Icons.local_shipping_rounded,
                    ),
                    _statCard('Active', '$active', Icons.verified_user_rounded),
                    _statCard('Disabled', '$disabled', Icons.block_rounded),
                  ],
                ),
                const SizedBox(height: 14),
                _filterCard(),
                const SizedBox(height: 14),
                _tableCard(filtered),
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
      ),
    );
  }

  Widget _adminPanel() {
    final email =
        FirebaseAuth.instance.currentUser?.email ?? 'admin@example.com';
    return AdminSidePanel(
      email: email,
      selected: AdminNavItem.users,
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
      onReviews: () {
        if (widget.onNavigateToReviews != null)
          return widget.onNavigateToReviews!();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminManageReviewsScreen()),
        );
      },
      onUsers: () {},
      onSignOut: () => FirebaseAuth.instance.signOut(),
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(12),
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
              color: const Color(0xFFFFF1EC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _brand, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
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
              hintText: 'Search by name, email, or uid...',
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
            runSpacing: 8,
            children:
                ['All', 'Admins', 'Delivery Staff', 'Active', 'Disabled']
                    .map(
                      (v) => ChoiceChip(
                        label: Text(v),
                        selected: _filter == v,
                        onSelected: (_) => setState(() => _filter = v),
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
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'USER',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.black54,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'EMAIL',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.black54,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'ROLE',
                    style: TextStyle(
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
                      fontWeight: FontWeight.w800,
                      color: Colors.black54,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'ACTION',
                    style: TextStyle(
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
              child: Text('No users match this filter.'),
            )
          else
            ...docs.map(_row),
        ],
      ),
    );
  }

  Widget _row(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final name = _nameOf(d);
    final email = _emailOf(d);
    final isAdmin = _isAdmin(d);
    final isDeliveryStaff = _isDeliveryStaff(d);
    final isActive = _isActive(d);
    final isCurrentAdmin = FirebaseAuth.instance.currentUser?.uid == doc.id;

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
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  email.isEmpty ? 'No email' : email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              email.isEmpty ? doc.id : email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              isAdmin
                  ? 'Admin'
                  : (isDeliveryStaff ? 'Delivery Staff' : 'Customer'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color:
                    isAdmin ? const Color(0xFF7C150D) : const Color(0xFF1E1A1A),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              isActive ? 'Active' : 'Disabled',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color:
                    isActive
                        ? const Color(0xFF1E8E4A)
                        : const Color(0xFFB3261E),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                TextButton(
                  onPressed: () => _showUserDetails(doc),
                  child: const Text('View'),
                ),
                TextButton(
                  onPressed:
                      isAdmin || isCurrentAdmin
                          ? null
                          : () =>
                              _toggleUserDisabled(doc: doc, disable: isActive),
                  child: Text(isActive ? 'Disable' : 'Enable'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleUserDisabled({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required bool disable,
  }) async {
    final d = doc.data();
    final name = _nameOf(d);
    final action = disable ? 'Disable' : 'Enable';
    final ok =
        await showDialog<bool>(
          context: context,
          builder:
              (_) => AlertDialog(
                title: Text('$action user'),
                content: Text(
                  '$action "$name"?\n\nThis updates user status in Firestore.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _brand),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(action),
                  ),
                ],
              ),
        ) ??
        false;
    if (!ok) return;

    try {
      await doc.reference.set({
        'disabled': disable,
        'isDisabled': disable,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User ${disable ? 'disabled' : 'enabled'}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update user: $e')));
    }
  }

  Future<void> _showUserDetails(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final d = doc.data();
    final createdAt = _timeText(d['createdAt']);
    final updatedAt = _timeText(d['updatedAt']);
    await showDialog<void>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(_nameOf(d)),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailLine('UID', doc.id),
                  _detailLine('Email', _emailOf(d)),
                  _detailLine(
                    'Role',
                    _isAdmin(d)
                        ? 'Admin'
                        : (_isDeliveryStaff(d) ? 'Delivery Staff' : 'Customer'),
                  ),
                  _detailLine('Status', _isActive(d) ? 'Active' : 'Disabled'),
                  _detailLine('Created', createdAt),
                  _detailLine('Updated', updatedAt),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Color(0xFF1E1A1A), fontSize: 13),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value.isEmpty ? '-' : value),
          ],
        ),
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final q = _search.trim().toLowerCase();
    final out =
        docs.where((doc) {
          final d = doc.data();
          final name = _nameOf(d).toLowerCase();
          final email = _emailOf(d).toLowerCase();
          final uid = doc.id.toLowerCase();
          final matchText =
              q.isEmpty ||
              name.contains(q) ||
              email.contains(q) ||
              uid.contains(q);

          final matchFilter = switch (_filter) {
            'Admins' => _isAdmin(d),
            'Delivery Staff' => _isDeliveryStaff(d),
            'Active' => _isActive(d),
            'Disabled' => !_isActive(d),
            _ => true,
          };
          return matchText && matchFilter;
        }).toList();

    out.sort((a, b) {
      final an = _nameOf(a.data()).toLowerCase();
      final bn = _nameOf(b.data()).toLowerCase();
      return an.compareTo(bn);
    });
    return out;
  }

  String _nameOf(Map<String, dynamic> d) {
    return (d['name'] ??
            d['displayName'] ??
            d['fullName'] ??
            d['staffName'] ??
            'User')
        .toString();
  }

  String _emailOf(Map<String, dynamic> d) {
    final direct =
        (d['email'] ?? d['userEmail'] ?? d['customerEmail'] ?? '')
            .toString()
            .trim();
    if (direct.isNotEmpty) return direct;
    final checkoutEmails = d['checkoutEmails'];
    if (checkoutEmails is List && checkoutEmails.isNotEmpty) {
      final first = checkoutEmails.first.toString().trim();
      if (first.isNotEmpty) return first;
    }
    return '';
  }

  bool _isAdmin(Map<String, dynamic> d) {
    return d['isAdmin'] == true ||
        (d['role'] ?? '').toString().toLowerCase() == 'admin';
  }

  bool _isDeliveryStaff(Map<String, dynamic> d) {
    return (d['role'] ?? '').toString().toLowerCase() == 'delivery_staff';
  }

  bool _isActive(Map<String, dynamic> d) {
    if (d['disabled'] == true) return false;
    if (d['isDisabled'] == true) return false;
    return true;
  }

  String _timeText(dynamic value) {
    if (value is! Timestamp) return '-';
    final dt = value.toDate();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openCreateDeliveryStaffDialog() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final save =
        await showDialog<bool>(
          context: context,
          builder:
              (_) => AlertDialog(
                title: const Text('Create Delivery Staff'),
                content: SizedBox(
                  width: 420,
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                            border: OutlineInputBorder(),
                          ),
                          validator:
                              (v) =>
                                  (v ?? '').trim().isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            final value = (v ?? '').trim();
                            if (value.isEmpty) return 'Required';
                            if (!value.contains('@')) return 'Invalid email';
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: passCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Temporary password',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if ((v ?? '').length < 6) {
                              return 'Min 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone number',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _brand),
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      Navigator.of(context).pop(true);
                    },
                    child: const Text('Create'),
                  ),
                ],
              ),
        ) ??
        false;
    if (!save) return;

    setState(() => _creatingDeliveryStaff = true);
    try {
      final appName = 'delivery-staff-${DateTime.now().microsecondsSinceEpoch}';
      final tempApp = await Firebase.initializeApp(
        name: appName,
        options: DefaultFirebaseOptions.currentPlatform,
      );
      try {
        final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
        final cred = await tempAuth.createUserWithEmailAndPassword(
          email: emailCtrl.text.trim(),
          password: passCtrl.text,
        );
        final user = cred.user;
        if (user == null) {
          throw Exception('Could not create auth user.');
        }
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': emailCtrl.text.trim(),
          'displayName': nameCtrl.text.trim(),
          'staffName': nameCtrl.text.trim(),
          'phone': phoneCtrl.text.trim(),
          'customerPhone': phoneCtrl.text.trim(),
          'role': 'delivery_staff',
          'isDeliveryStaff': true,
          'disabled': false,
          'isDisabled': false,
          'isActive': true,
          'createdByAdminUid': FirebaseAuth.instance.currentUser?.uid,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await tempAuth.signOut();
      } finally {
        await tempApp.delete();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delivery staff created: ${emailCtrl.text.trim()}'),
        ),
      );
      await showDialog<void>(
        context: context,
        builder:
            (_) => AlertDialog(
              title: const Text('Credentials created'),
              content: Text(
                'Email: ${emailCtrl.text.trim()}\nPassword: ${passCtrl.text}\n\nShare these with the delivery staff and ask them to change password later.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Failed to create delivery staff')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _creatingDeliveryStaff = false);
      }
    }
  }
}
