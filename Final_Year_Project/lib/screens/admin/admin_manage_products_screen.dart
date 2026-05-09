import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'admin_dashboard_screen.dart';
import 'admin_manage_orders_screen.dart';
import 'admin_manage_reviews_screen.dart';
import 'admin_manage_users_screen.dart';
import 'widgets/admin_side_panel.dart';
import '../../utils/seed_products.dart';
import '../../widgets/firebase_image.dart';

class AdminManageProductsScreen extends StatefulWidget {
  final bool shellEmbedded;
  final VoidCallback? onNavigateToDashboard;
  final VoidCallback? onNavigateToOrders;
  final VoidCallback? onNavigateToReviews;
  final VoidCallback? onNavigateToUsers;

  AdminManageProductsScreen({
    super.key,
    this.shellEmbedded = false,
    this.onNavigateToDashboard,
    this.onNavigateToOrders,
    this.onNavigateToReviews,
    this.onNavigateToUsers,
  });

  @override
  State<AdminManageProductsScreen> createState() =>
      _AdminManageProductsScreenState();
}

class _AdminManageProductsScreenState extends State<AdminManageProductsScreen> {
  static const _brand = Color(0xFF7C150D);
  static const _softBg = Color(0xFFF7F2F1);
  static const _pageSize = 8;
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _category = 'All';
  String _status = 'All';
  String _catalog = 'All';

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
                title: const Text('Product Management'),
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1E1A1A),
                elevation: 0.2,
              ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('products').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            final errWidget = Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load products.\n${snap.error}',
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

          final allDocs = snap.data?.docs ?? const [];
          final categories = _categoriesFrom(allDocs);
          final filtered = _filterDocs(allDocs);
          final pageDocs = filtered;

          final activeCount =
              allDocs.where((d) => _statusOf(d.data()) == 'Active').length;
          final outCount =
              allDocs
                  .where((d) => _statusOf(d.data()) == 'Out of Stock')
                  .length;
          final lowStockCount =
              allDocs.where((d) {
                final stock = _toInt(d.data()['stock']);
                return stock > 0 && stock < 15;
              }).length;

          Widget content;
          if (allDocs.isEmpty) {
            content = const Center(
              child: Text(
                'No products found. Tap "Add Product" to create one.',
              ),
            );
          } else {
            content = SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, c) {
                      final compactHeader = c.maxWidth < 860;
                      final titleBlock = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Inventory  /  Products',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Product Management',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: math.min(48 / 1.4, c.maxWidth / 14),
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1D2433),
                            ),
                          ),
                        ],
                      );
                      final addButton = FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _brand,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => _openProductPage(),
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text(
                          'Add Product',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );

                      if (compactHeader) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            titleBlock,
                            const SizedBox(height: 10),
                            addButton,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: titleBlock),
                          const SizedBox(width: 10),
                          addButton,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _statCatalogTile(
                          'Active listings',
                          '$activeCount',
                          Icons.check_circle_rounded,
                          const Color(0xFFE7F7EC),
                          selected: _catalog == 'All',
                          onTap: () => setState(() => _catalog = 'All'),
                        ),
                        const SizedBox(width: 10),
                        _statCatalogTile(
                          'Low stock',
                          '$lowStockCount',
                          Icons.warning_amber_rounded,
                          const Color(0xFFFFF7E0),
                        ),
                        const SizedBox(width: 10),
                        _statCatalogTile(
                          'Out of stock',
                          '$outCount',
                          Icons.error_rounded,
                          const Color(0xFFFFECEC),
                          selected: _catalog == 'Out of Stock',
                          onTap:
                              () => setState(() => _catalog = 'Out of Stock'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _filterCard(categories),
                  const SizedBox(height: 14),
                  _tableCard(pageDocs, filtered.length),
                ],
              ),
            );
          }

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
      selected: AdminNavItem.products,
      onDashboard: () {
        if (widget.onNavigateToDashboard != null) {
          widget.onNavigateToDashboard!();
          return;
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => AdminDashboardScreen()),
        );
      },
      onProducts: () {},
      onOrders: () {
        if (widget.onNavigateToOrders != null) {
          widget.onNavigateToOrders!();
          return;
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => AdminManageOrdersScreen()),
        );
      },
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

  static num _toNum(dynamic v) {
    if (v is num) return v;
    return num.tryParse('$v') ?? 0;
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  Future<void> _setAllProductsInStock() async {
    final confirm =
        await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Set all products in stock'),
                content: const Text(
                  'This will update all products and set stock to exactly 10.\n\nContinue?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _brand),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Update all'),
                  ),
                ],
              ),
        ) ??
        false;
    if (!confirm) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db.collection('products').get();
      var updated = 0;

      WriteBatch batch = db.batch();
      var opCount = 0;

      for (final doc in snap.docs) {
        batch.set(doc.reference, {
          'stock': 10,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        opCount++;
        updated++;

        // Firestore batch write limit safety
        if (opCount >= 400) {
          await batch.commit();
          batch = db.batch();
          opCount = 0;
        }
      }

      if (opCount > 0) {
        await batch.commit();
      }

      messenger.showSnackBar(
        SnackBar(
          backgroundColor: _brand,
          content: Text('Updated stock for $updated products.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to update stock: $e')),
      );
    }
  }

  Future<void> _fixAllProductImages() async {
    final confirm =
        await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Fix product images'),
                content: const Text(
                  'This will scan all products, resolve image paths from seed data, and store working imageUrl values in Firestore.\n\nContinue?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _brand),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Run fix'),
                  ),
                ],
              ),
        ) ??
        false;
    if (!confirm) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db.collection('products').get();
      var updated = 0;
      var skipped = 0;

      WriteBatch batch = db.batch();
      var opCount = 0;

      for (final doc in snap.docs) {
        final d = doc.data();
        String? bestPath;

        // Keep existing known-good path first.
        final existingPath = (d['imagePath'] ?? '').toString().trim();
        if (existingPath.isNotEmpty) {
          final normalized = _normalizeToStoragePath(existingPath);
          if (normalized != null) {
            bestPath = normalized;
          }
        }

        // Fallback to seed mapping.
        bestPath ??= _normalizeToStoragePath(
          seedImagePathForProduct(
                docId: doc.id,
                id: (d['id'] ?? '').toString(),
                name: (d['name'] ?? '').toString(),
              ) ??
              '',
        );

        if (bestPath == null || bestPath.isEmpty) {
          skipped++;
          continue;
        }

        try {
          final url =
              await FirebaseStorage.instance.ref(bestPath).getDownloadURL();
          batch.set(doc.reference, {
            'imagePath': bestPath,
            'imageUrl': url,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          opCount++;
          updated++;
          if (opCount >= 350) {
            await batch.commit();
            batch = db.batch();
            opCount = 0;
          }
        } catch (_) {
          skipped++;
        }
      }

      if (opCount > 0) {
        await batch.commit();
      }

      messenger.showSnackBar(
        SnackBar(
          backgroundColor: _brand,
          content: Text(
            'Image fix complete. Updated: $updated, Skipped: $skipped',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to fix product images: $e')),
      );
    }
  }

  String? _normalizeToStoragePath(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://'))
      return null;
    if (value.startsWith('gs://')) {
      final withoutScheme = value.replaceFirst('gs://', '');
      final slashIndex = withoutScheme.indexOf('/');
      return slashIndex >= 0 ? withoutScheme.substring(slashIndex + 1) : null;
    }
    if (value.startsWith('assets/')) {
      return value.replaceFirst('assets/', '');
    }
    if (value.startsWith('products/')) {
      return value;
    }
    if (value.startsWith('/products/')) {
      return value.substring(1);
    }
    // If only relative object name is stored, assume products/ root.
    if (!value.contains('://') && !value.startsWith('/')) {
      return 'products/$value';
    }
    return null;
  }

  String _skuFor(DocumentSnapshot<Map<String, dynamic>> doc) {
    final id = doc.id.toUpperCase();
    return 'SKU:${id.length > 12 ? id.substring(0, 12) : id}';
  }

  String _statusOf(Map<String, dynamic> d) {
    final stock = _toInt(d['stock']);
    if (stock <= 0) return 'Out of Stock';
    if (d['isDraft'] == true) return 'Draft';
    return 'Active';
  }

  List<String> _categoriesFrom(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final set = <String>{'All'};
    for (final doc in docs) {
      final d = doc.data();
      final c = (d['category'] ?? d['subCategory'] ?? '').toString().trim();
      if (c.isNotEmpty) set.add(c);
    }
    return set.toList();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final filtered =
        docs.where((doc) {
          final d = doc.data();
          final name = (d['name'] ?? '').toString().toLowerCase();
          final sku = doc.id.toLowerCase();
          final category = (d['category'] ?? '').toString();
          final status = _statusOf(d);
          final q = _search.toLowerCase().trim();

          final matchSearch = q.isEmpty || name.contains(q) || sku.contains(q);
          final matchCategory = _category == 'All' || category == _category;
          final matchStatus = _status == 'All' || status == _status;
          final matchCatalog =
              _catalog == 'All' ||
              (_catalog == 'Out of Stock' && status == 'Out of Stock');
          return matchSearch && matchCategory && matchStatus && matchCatalog;
        }).toList();

    filtered.sort((a, b) {
      final ad = a.data();
      final bd = b.data();
      final at = _toMillis(ad['updatedAt'] ?? ad['createdAt']);
      final bt = _toMillis(bd['updatedAt'] ?? bd['createdAt']);
      return bt.compareTo(at);
    });
    return filtered;
  }

  static int _toMillis(dynamic v) {
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    if (v is int) return v;
    if (v is String) return DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0;
    return 0;
  }

  Widget _filterCard(List<String> categories) {
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
            onChanged:
                (v) => setState(() {
                  _search = v;
                }),
            decoration: InputDecoration(
              hintText: 'Search product name or SKU...',
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'CATEGORY:',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children:
                categories
                    .map(
                      (c) => ChoiceChip(
                        label: Text(c, overflow: TextOverflow.ellipsis),
                        selected: _category == c,
                        onSelected:
                            (_) => setState(() {
                              _category = c;
                            }),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 10),
          const Text(
            'STATUS:',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children:
                ['All', 'Active', 'Out of Stock', 'Draft']
                    .map(
                      (s) => ChoiceChip(
                        label: Text(s),
                        selected: _status == s,
                        onSelected:
                            (_) => setState(() {
                              _status = s;
                            }),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 10),
          const Text(
            'PRODUCT VIEW:',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children:
                ['All', 'Out of Stock']
                    .map(
                      (v) => ChoiceChip(
                        label: Text(v),
                        selected: _catalog == v,
                        onSelected:
                            (_) => setState(() {
                              _catalog = v;
                            }),
                      ),
                    )
                    .toList(),
          ),
        ],
      ),
    );
  }

  static const double _tableMinWidth = 1000;

  Widget _tableCard(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int filteredTotal,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = math.max(_tableMinWidth, constraints.maxWidth);
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: tableWidth),
              child: Container(
                width: tableWidth,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE9DDDA)),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF6F3F4),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Text(
                              'Product',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'Category',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'Price',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'Stock Level',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'Status',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              'Actions',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (docs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No products match current filters.'),
                      )
                    else
                      ...docs.map(_tableRow),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Color(0xFFF0E8E6)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Showing $filteredTotal product(s)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tableRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final name = (d['name'] ?? '').toString();
    final category = (d['category'] ?? '').toString();
    final price = _toNum(d['price']);
    final stock = _toInt(d['stock']);
    final status = _statusOf(d);

    final stockColor =
        stock <= 0
            ? const Color(0xFFD32F2F)
            : stock < 15
            ? const Color(0xFFE67E22)
            : const Color(0xFF2EAF62);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF4ECEA))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1EC),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _productThumb(d, doc.id),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _skuFor(doc),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              category.isEmpty ? '-' : category,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Rs ${price.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: (stock / 100).clamp(0, 1).toDouble(),
                      backgroundColor: const Color(0xFFE8EDF3),
                      color: stockColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '$stock',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: stockColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _statusBadge(status),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _openProductPage(doc: doc),
                ),
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  onPressed: () async {
                    final ok =
                        await showDialog<bool>(
                          context: context,
                          builder:
                              (context) => AlertDialog(
                                title: const Text('Delete product'),
                                content: Text(
                                  'Delete "${name.isEmpty ? doc.id : name}"?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed:
                                        () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _brand,
                                    ),
                                    onPressed:
                                        () => Navigator.pop(context, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                        ) ??
                        false;
                    if (!ok) return;
                    await doc.reference.delete();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    late Color bg;
    late Color fg;
    if (status == 'Active') {
      bg = const Color(0xFFE8F7EC);
      fg = const Color(0xFF1E8E4A);
    } else if (status == 'Out of Stock') {
      bg = const Color(0xFFFFECEC);
      fg = const Color(0xFFB3261E);
    } else {
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

  Widget _productThumb(Map<String, dynamic> d, String docId) {
    return _ProductImageProbe(data: d, docId: docId);
  }

  static const double _statCatalogWidth = 152;

  /// Compact catalog-style KPI tiles (not full-width bars).
  Widget _statCatalogTile(
    String label,
    String value,
    IconData icon,
    Color iconBg, {
    bool selected = false,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      width: _statCatalogWidth,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFF7F5) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  selected
                      ? _brand.withValues(alpha: 0.55)
                      : const Color(0xFFE9DDDA),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 24, color: _brand),
              ),
              const SizedBox(height: 10),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1D2433),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.black54,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openProductPage({
    DocumentSnapshot<Map<String, dynamic>>? doc,
  }) async {
    final d = doc?.data();
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder:
            (_) => _AdminProductFormPage(initialData: d, isEdit: doc != null),
      ),
    );
    if (result == null) return;
    final messenger = ScaffoldMessenger.of(context);

    final payload = <String, dynamic>{
      'name': (result['name'] ?? '').toString().trim(),
      'category': (result['category'] ?? '').toString().trim(),
      'subCategory': (result['subCategory'] ?? '').toString().trim(),
      'price': num.tryParse((result['price'] ?? '').toString()) ?? 0,
      'stock': int.tryParse((result['stock'] ?? '').toString()) ?? 0,
      'imagePath': _normalizePathForField(
        (result['imagePath'] ?? '').toString(),
      ),
      'imageUrl': (result['imageUrl'] ?? '').toString().trim(),
      'shades':
          (result['shades'] is List)
              ? result['shades']
              : const <Map<String, String>>[],
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (doc != null) {
      await doc.reference.set(payload, SetOptions(merge: true));
      messenger.showSnackBar(
        const SnackBar(content: Text('Product updated successfully.')),
      );
      return;
    }

    final id = payload['name']
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (id.isNotEmpty) {
      payload['id'] = id;
      await FirebaseFirestore.instance.collection('products').doc(id).set({
        ...payload,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await FirebaseFirestore.instance.collection('products').add({
        ...payload,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    messenger.showSnackBar(
      SnackBar(content: Text('"${payload['name']}" added successfully.')),
    );
  }

  Future<void> _showProductDialog(
    BuildContext context, {
    DocumentSnapshot<Map<String, dynamic>>? doc,
  }) async {
    final d = doc?.data();
    final nameCtrl = TextEditingController(text: (d?['name'] ?? '').toString());
    final categoryCtrl = TextEditingController(
      text: (d?['category'] ?? '').toString(),
    );
    final subCategoryCtrl = TextEditingController(
      text: (d?['subCategory'] ?? d?['subcategory'] ?? '').toString(),
    );
    final priceCtrl = TextEditingController(
      text: _toNum(d?['price']).toStringAsFixed(0),
    );
    final stockCtrl = TextEditingController(
      text: _toInt(d?['stock']).toString(),
    );
    final imagePathCtrl = TextEditingController(
      text: _normalizePathForField((d?['imagePath'] ?? '').toString()),
    );
    final imageUrlCtrl = TextEditingController(
      text: (d?['imageUrl'] ?? '').toString(),
    );

    final formKey = GlobalKey<FormState>();
    final isEdit = doc != null;

    final save =
        await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text(isEdit ? 'Edit Product' : 'Add Product'),
                content: SizedBox(
                  width: 420,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _field(nameCtrl, 'Name'),
                          const SizedBox(height: 10),
                          _field(categoryCtrl, 'Category'),
                          const SizedBox(height: 10),
                          _field(subCategoryCtrl, 'Subcategory'),
                          const SizedBox(height: 10),
                          _field(
                            priceCtrl,
                            'Price',
                            keyboardType: TextInputType.number,
                            validator:
                                (v) =>
                                    num.tryParse(v ?? '') == null
                                        ? 'Enter valid price'
                                        : null,
                          ),
                          const SizedBox(height: 10),
                          _field(
                            stockCtrl,
                            'Stock',
                            keyboardType: TextInputType.number,
                            validator:
                                (v) =>
                                    int.tryParse(v ?? '') == null
                                        ? 'Enter valid stock'
                                        : null,
                          ),
                          const SizedBox(height: 10),
                          _field(
                            imagePathCtrl,
                            'Image path (optional)',
                            required: false,
                          ),
                          const SizedBox(height: 10),
                          _field(
                            imageUrlCtrl,
                            'Image URL (optional)',
                            required: false,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _brand),
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      Navigator.pop(context, true);
                    },
                    child: Text(isEdit ? 'Save' : 'Add'),
                  ),
                ],
              ),
        ) ??
        false;

    if (!save) return;

    final payload = <String, dynamic>{
      'name': nameCtrl.text.trim(),
      'category': categoryCtrl.text.trim(),
      'subCategory': subCategoryCtrl.text.trim(),
      'price': num.tryParse(priceCtrl.text.trim()) ?? 0,
      'stock': int.tryParse(stockCtrl.text.trim()) ?? 0,
      'imagePath': _normalizePathForField(imagePathCtrl.text.trim()),
      'imageUrl': imageUrlCtrl.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (isEdit) {
      await doc.reference.set(payload, SetOptions(merge: true));
      return;
    }

    final id = payload['name']
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    if (id.isNotEmpty) {
      payload['id'] = id;
      await FirebaseFirestore.instance.collection('products').doc(id).set({
        ...payload,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await FirebaseFirestore.instance.collection('products').add({
        ...payload,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = true,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      validator:
          validator ??
          (value) {
            if (!required) return null;
            if ((value ?? '').trim().isEmpty) return 'Required';
            return null;
          },
    );
  }

  String _normalizePathForField(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return value;

    // Keep full gs:// and http(s) if user provides those intentionally.
    if (value.startsWith('gs://') ||
        value.startsWith('http://') ||
        value.startsWith('https://')) {
      return value;
    }

    // Convert local app asset-style path to Firebase Storage object path.
    if (value.startsWith('assets/')) {
      value = value.replaceFirst('assets/', '');
    }
    // Ensure object path begins with products/ for this catalog.
    if (!value.startsWith('products/')) {
      value = 'products/$value';
    }
    return value;
  }
}

class _AdminProductFormPage extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final bool isEdit;
  const _AdminProductFormPage({
    required this.initialData,
    required this.isEdit,
  });

  @override
  State<_AdminProductFormPage> createState() => _AdminProductFormPageState();
}

class _AdminProductFormPageState extends State<_AdminProductFormPage> {
  static const _brand = Color(0xFF7C150D);
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  static const List<String> _categoryOptions = [
    'Lip Sticks',
    'Makeup',
    'Face',
    'Hair Colors',
  ];
  static const Map<String, List<String>> _subCategoryByCategory = {
    'Lip Sticks': ['Lipstick', 'Lip Liner', 'Lip Gloss', 'Lip Care'],
    'Makeup': [
      'Foundation',
      'Concealer',
      'Blush',
      'Highlighter',
      'Contour & Bronzer',
      'Mascara',
      'Eye Liner',
      'Eye Shadows',
      'Eye Brow',
      'Primer',
      'Setting Spray',
    ],
    'Face': [
      'Foundation',
      'Powder',
      'Blush',
      'Concealer',
      'Highlighter',
      'Contour & Bronzer',
    ],
    'Hair Colors': ['Permanent', 'Semi-Permanent', 'Temporary'],
  };

  late final TextEditingController _nameCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _subCategoryCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _imagePathCtrl;
  List<Map<String, String>> _shades = [];
  String _selectedCategory = 'Lip Sticks';
  String _selectedSubCategory = 'Lipstick';
  Uint8List? _pickedBytes;
  String? _pickedFileName;
  String _uploadedImageUrl = '';
  bool _uploadVerified = false;
  bool _uploadingImage = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    _nameCtrl = TextEditingController(text: (d?['name'] ?? '').toString());
    _categoryCtrl = TextEditingController(
      text: (d?['category'] ?? '').toString(),
    );
    _subCategoryCtrl = TextEditingController(
      text: (d?['subCategory'] ?? d?['subcategory'] ?? '').toString(),
    );
    _priceCtrl = TextEditingController(
      text: _AdminManageProductsScreenState._toNum(
        d?['price'],
      ).toStringAsFixed(0),
    );
    _stockCtrl = TextEditingController(
      text: _AdminManageProductsScreenState._toInt(d?['stock']).toString(),
    );
    _imagePathCtrl = TextEditingController(
      text: (d?['imagePath'] ?? '').toString(),
    );
    _uploadedImageUrl = (d?['imageUrl'] ?? '').toString();
    _uploadVerified =
        _imagePathCtrl.text.trim().isNotEmpty &&
        _uploadedImageUrl.trim().isNotEmpty;

    final initialCategory = (d?['category'] ?? '').toString().trim();
    if (_categoryOptions.contains(initialCategory)) {
      _selectedCategory = initialCategory;
    }
    final availableSubs =
        _subCategoryByCategory[_selectedCategory] ?? const <String>[];
    final initialSub =
        (d?['subCategory'] ?? d?['subcategory'] ?? '').toString().trim();
    _selectedSubCategory =
        availableSubs.contains(initialSub)
            ? initialSub
            : (availableSubs.isNotEmpty ? availableSubs.first : '');

    _categoryCtrl.text = _selectedCategory;
    _subCategoryCtrl.text = _selectedSubCategory;

    final rawShades = d?['shades'];
    if (rawShades is List) {
      _shades =
          rawShades
              .whereType<Map>()
              .map(
                (item) => {
                  'name': (item['name'] ?? '').toString(),
                  'hex': (item['hex'] ?? '').toString(),
                },
              )
              .where(
                (shade) =>
                    shade['name']!.trim().isNotEmpty ||
                    shade['hex']!.trim().isNotEmpty,
              )
              .toList();
    }
    if (_requiresColorOptions && _shades.isEmpty) {
      _shades = [
        {'name': 'Default Shade', 'hex': '#C0392B'},
      ];
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _subCategoryCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _imagePathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F2F1),
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Edit Product' : 'Add Product'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E1A1A),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Product Details',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    children: [
                      _field(_nameCtrl, 'Product name'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _categoryDropdown()),
                          const SizedBox(width: 12),
                          Expanded(child: _subCategoryDropdown()),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              _priceCtrl,
                              'Price',
                              keyboardType: TextInputType.number,
                              validator:
                                  (v) =>
                                      num.tryParse(v ?? '') == null
                                          ? 'Enter valid price'
                                          : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              _stockCtrl,
                              'Stock',
                              keyboardType: TextInputType.number,
                              validator:
                                  (v) =>
                                      int.tryParse(v ?? '') == null
                                          ? 'Enter valid stock'
                                          : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_requiresColorOptions) ...[
                    const SizedBox(height: 16),
                    Text(
                      _colorSectionTitle,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _sectionCard(
                      children: [
                        ..._buildShadeRows(),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _addShadeRow,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Shade'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'Product Image',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(children: [_buildImageUploader()]),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, c) {
                      final narrow = c.maxWidth < 380;
                      final saveBtn = FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: _brand),
                        onPressed:
                            (_uploadingImage || !_uploadVerified)
                                ? null
                                : _submit,
                        icon: const Icon(
                          Icons.save_rounded,
                          color: Colors.white,
                        ),
                        label: Text(
                          widget.isEdit ? 'Save Product' : 'Create Product',
                        ),
                      );
                      final cancelBtn = OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      );
                      if (narrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            cancelBtn,
                            const SizedBox(height: 10),
                            saveBtn,
                          ],
                        );
                      }
                      return Row(
                        children: [cancelBtn, const Spacer(), saveBtn],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9DDDA)),
      ),
      child: Column(children: children),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = true,
    bool readOnly = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      validator:
          validator ??
          (value) {
            if (!required) return null;
            if ((value ?? '').trim().isEmpty) return 'Required';
            return null;
          },
    );
  }

  String get _safeCategory => '$_selectedCategory';
  String get _safeSubCategory => '$_selectedSubCategory';
  bool get _isLipsticksCategory => _safeCategory == 'Lip Sticks';
  bool get _isHairColorsCategory => _safeCategory == 'Hair Colors';
  bool get _isFoundationSubCategory =>
      _safeSubCategory.toLowerCase() == 'foundation';
  bool get _requiresColorOptions =>
      _isLipsticksCategory || _isHairColorsCategory || _isFoundationSubCategory;
  String get _colorSectionTitle {
    if (_isHairColorsCategory) return 'Hair Color Options';
    if (_isFoundationSubCategory) return 'Foundation Shades';
    return 'Lipstick Shades';
  }

  Widget _categoryDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedCategory,
      decoration: InputDecoration(
        labelText: 'Category',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      items:
          _categoryOptions
              .map(
                (category) =>
                    DropdownMenuItem(value: category, child: Text(category)),
              )
              .toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _selectedCategory = value;
          _categoryCtrl.text = value;
          final subs = _subCategoryByCategory[value] ?? const <String>[];
          _selectedSubCategory = subs.isNotEmpty ? subs.first : '';
          _subCategoryCtrl.text = _selectedSubCategory;
          if (_requiresColorOptions && _shades.isEmpty) {
            _shades = [
              {'name': 'Default Shade', 'hex': '#C0392B'},
            ];
          }
        });
      },
    );
  }

  Widget _subCategoryDropdown() {
    final subs = _subCategoryByCategory[_selectedCategory] ?? const <String>[];
    final current =
        subs.contains(_selectedSubCategory)
            ? _selectedSubCategory
            : (subs.isEmpty ? null : subs.first);
    return DropdownButtonFormField<String>(
      value: current,
      decoration: InputDecoration(
        labelText: 'Subcategory',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      items:
          subs
              .map((sub) => DropdownMenuItem(value: sub, child: Text(sub)))
              .toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _selectedSubCategory = value;
          _subCategoryCtrl.text = value;
          if (_requiresColorOptions && _shades.isEmpty) {
            _shades = [
              {'name': 'Default Shade', 'hex': '#C0392B'},
            ];
          }
        });
      },
    );
  }

  List<Widget> _buildShadeRows() {
    if (_shades.isEmpty) {
      return [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Add at least one shade for lipsticks.',
            style: TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ];
    }
    final rows = <Widget>[];
    for (var i = 0; i < _shades.length; i++) {
      final shade = _shades[i];
      rows.add(
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                initialValue: shade['name'] ?? '',
                decoration: InputDecoration(
                  labelText: 'Shade name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (v) => _shades[i]['name'] = v,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TextFormField(
                initialValue: shade['hex'] ?? '',
                decoration: InputDecoration(
                  labelText: 'Hex (#RRGGBB)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (v) => _shades[i]['hex'] = v,
              ),
            ),
            IconButton(
              tooltip: 'Remove shade',
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              padding: EdgeInsets.zero,
              onPressed: () => _removeShadeRow(i),
              icon: const Icon(Icons.delete_outline, size: 22),
            ),
          ],
        ),
      );
      if (i != _shades.length - 1) rows.add(const SizedBox(height: 10));
    }
    return rows;
  }

  void _addShadeRow() {
    setState(() {
      _shades.add({'name': '', 'hex': '#C0392B'});
    });
  }

  void _removeShadeRow(int index) {
    setState(() {
      if (index >= 0 && index < _shades.length) {
        _shades.removeAt(index);
      }
      if (_requiresColorOptions && _shades.isEmpty) {
        _shades = [
          {'name': 'Default Shade', 'hex': '#C0392B'},
        ];
      }
    });
  }

  Widget _buildImageUploader() {
    final hasImage =
        _pickedBytes != null || _uploadedImageUrl.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F5FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD8DCE8), width: 1.2),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 200),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF2FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD4D9E7)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_pickedBytes != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      _pickedBytes!,
                      height: 120,
                      fit: BoxFit.cover,
                    ),
                  )
                else if (_uploadedImageUrl.trim().isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      _uploadedImageUrl.trim(),
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (_, __, ___) => const Icon(
                            Icons.image_outlined,
                            size: 64,
                            color: Color(0xFFADB3C4),
                          ),
                    ),
                  )
                else
                  const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 64,
                    color: Color(0xFFADB3C4),
                  ),
                const SizedBox(height: 12),
                Text(
                  hasImage ? 'Image selected' : 'Drag and drop image here',
                  style: const TextStyle(
                    fontSize: 28 * 0.7,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4C4F5B),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'High-resolution JPG or PNG (Max 5MB)\nRecommended aspect ratio 4:5',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF8E92A0),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: _uploadingImage ? null : _pickAndUploadImage,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _brand,
                    side: const BorderSide(color: Color(0xFFCBB3B7)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  child:
                      _uploadingImage
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text(
                            'SELECT FILE',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                ),
                if (_pickedFileName != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _pickedFileName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6A6E7E),
                    ),
                  ),
                ],
                if (_uploadVerified) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Upload successful',
                    style: TextStyle(
                      color: Color(0xFF1E8E4A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(3, (index) {
              final showPicked = index == 0 && _pickedBytes != null;
              return Expanded(
                child: Container(
                  height: 68,
                  margin: EdgeInsets.only(right: index < 2 ? 10 : 0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF2FA),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFD8DCE8)),
                  ),
                  child:
                      showPicked
                          ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              _pickedBytes!,
                              fit: BoxFit.cover,
                            ),
                          )
                          : const Icon(
                            Icons.image_outlined,
                            color: Color(0xFFB8BDCA),
                          ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;

      setState(() {
        _pickedBytes = bytes;
        _pickedFileName = file.name;
        _uploadingImage = true;
        _uploadVerified = false;
      });

      final ext = _fileExt(file.name);
      final product = _slug(_nameCtrl.text);
      final millis = DateTime.now().millisecondsSinceEpoch;
      final folder = _storageFolderForSelection(
        category: _selectedCategory,
        subCategory: _selectedSubCategory,
      );
      final objectPath = 'products/$folder/${product}_$millis.$ext';

      final metadata = SettableMetadata(contentType: 'image/$ext');
      await FirebaseStorage.instance.ref(objectPath).putData(bytes, metadata);
      final url =
          await FirebaseStorage.instance.ref(objectPath).getDownloadURL();
      await FirebaseStorage.instance.ref(objectPath).getMetadata();

      if (!mounted) return;
      setState(() {
        _imagePathCtrl.text = objectPath;
        _uploadedImageUrl = url;
        _uploadingImage = false;
        _uploadVerified = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingImage = false;
        _uploadVerified = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Image upload failed: $e')));
    }
  }

  String _slug(String value) {
    final v = value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final cleaned = v
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'uncategorized' : cleaned;
  }

  String _fileExt(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.jpeg')) return 'jpeg';
    if (lower.endsWith('.jpg')) return 'jpg';
    if (lower.endsWith('.webp')) return 'webp';
    return 'png';
  }

  String _storageFolderForSelection({
    required String category,
    required String subCategory,
  }) {
    final c = category.trim().toLowerCase();
    final s = subCategory.trim().toLowerCase();

    if (c == 'lip sticks' || s.contains('lip')) {
      return 'lipsticks';
    }
    if (c == 'hair colors' ||
        s.contains('permanent') ||
        s.contains('temporary')) {
      return 'hair colors';
    }
    if (s.contains('mascara')) return 'eye products/mascara';
    if (s.contains('liner')) return 'eye products/eye liner';
    if (s.contains('shadow')) return 'eye products/eye shadows';
    if (s.contains('brow')) return 'eye products/eye brow';
    if (s.contains('foundation')) return 'face products/foundation';
    if (s.contains('concealer')) return 'face products/concealer';
    if (s.contains('blush')) return 'face products/blush';
    if (s.contains('highlighter')) return 'face products/highlighter';
    if (s.contains('powder')) return 'face products/powder';
    if (s.contains('contour') || s.contains('bronzer'))
      return 'face products/contour_bronzer';
    if (c == 'face') return 'face products/foundation';
    if (c == 'makeup') return 'face products/foundation';

    // Keep uploads inside the existing known catalog folders by default.
    return 'lipsticks';
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_uploadingImage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait until image upload completes.'),
        ),
      );
      return;
    }
    if (!_uploadVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload and verify product image first.'),
        ),
      );
      return;
    }
    if (_imagePathCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an image to upload first.'),
        ),
      );
      return;
    }
    final cleanShades =
        _shades
            .map(
              (s) => {
                'name': (s['name'] ?? '').trim(),
                'hex': _normalizeHex((s['hex'] ?? '').trim()),
              },
            )
            .where((s) => s['name']!.isNotEmpty)
            .toList();
    if (_requiresColorOptions && cleanShades.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please add at least one ${_colorSectionTitle.toLowerCase().replaceAll(' options', '').replaceAll(' shades', ' shade')}.',
          ),
        ),
      );
      return;
    }
    Navigator.pop(context, {
      'name': _nameCtrl.text.trim(),
      'category': _selectedCategory,
      'subCategory': _selectedSubCategory,
      'price': _priceCtrl.text.trim(),
      'stock': _stockCtrl.text.trim(),
      'imagePath': _imagePathCtrl.text.trim(),
      'imageUrl': _uploadedImageUrl.trim(),
      'shades': cleanShades,
    });
  }

  String _normalizeHex(String input) {
    if (input.isEmpty) return '#C0392B';
    var out = input.toUpperCase();
    if (!out.startsWith('#')) out = '#$out';
    final valid = RegExp(r'^#[0-9A-F]{6}$').hasMatch(out);
    return valid ? out : '#C0392B';
  }
}

class _ProductImageProbe extends StatefulWidget {
  final Map<String, dynamic> data;
  final String? docId;
  const _ProductImageProbe({required this.data, this.docId});

  @override
  State<_ProductImageProbe> createState() => _ProductImageProbeState();
}

class _ProductImageProbeState extends State<_ProductImageProbe> {
  static final Map<String, String?> _urlCache = {};
  static Future<List<String>>? _allStorageObjectsFuture;
  late Future<String?> _urlFuture;

  @override
  void initState() {
    super.initState();
    _urlFuture = _resolveImageUrl();
  }

  @override
  @override
  void didUpdateWidget(covariant _ProductImageProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _urlFuture = _resolveImageUrl();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _urlFuture,
      builder: (context, snap) {
        final url = snap.data;
        if (url == null || url.isEmpty) {
          return const Icon(
            Icons.inventory_2_rounded,
            color: Color(0xFF7C150D),
            size: 20,
          );
        }
        return Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder:
              (_, __, ___) => const Icon(
                Icons.inventory_2_rounded,
                color: Color(0xFF7C150D),
                size: 20,
              ),
        );
      },
    );
  }

  Future<String?> _resolveImageUrl() async {
    final candidates = _buildCandidates(widget.data);
    final cacheKey = candidates.join('||');
    if (_urlCache.containsKey(cacheKey)) return _urlCache[cacheKey];

    for (final c in candidates) {
      if (c.startsWith('http://') || c.startsWith('https://')) {
        _urlCache[cacheKey] = c;
        return c;
      }
      final path = _normalizeStoragePath(c);
      if (path == null || path.isEmpty) continue;
      final variants = _pathCandidates(path);
      for (final v in variants) {
        try {
          final url = await FirebaseStorage.instance.ref(v).getDownloadURL();
          _urlCache[cacheKey] = url;
          return url;
        } catch (_) {
          continue;
        }
      }
    }

    // Last-resort fallback: match against real objects in Firebase Storage.
    final matchedPath = await _matchFromStorageIndex(widget.data);
    if (matchedPath != null && matchedPath.isNotEmpty) {
      try {
        final url =
            await FirebaseStorage.instance.ref(matchedPath).getDownloadURL();
        _urlCache[cacheKey] = url;
        return url;
      } catch (_) {
        // ignore and fallthrough to null
      }
    }

    _urlCache[cacheKey] = null;
    return null;
  }

  Future<String?> _matchFromStorageIndex(Map<String, dynamic> d) async {
    _allStorageObjectsFuture ??= _listAllProductObjects();
    final allObjects = await _allStorageObjectsFuture!;
    if (allObjects.isEmpty) return null;

    final tokens = <String>{
      _normalizeToken((d['id'] ?? '').toString()),
      _normalizeToken((d['sku'] ?? '').toString()),
      _normalizeToken((d['name'] ?? '').toString()),
    }..removeWhere((e) => e.isEmpty);
    if (tokens.isEmpty) return null;

    for (final path in allObjects) {
      final basename = path.split('/').last;
      final fileKey = _normalizeToken(
        basename.replaceAll(
          RegExp(r'\.(png|jpg|jpeg|webp)$', caseSensitive: false),
          '',
        ),
      );
      if (fileKey.isEmpty) continue;
      for (final token in tokens) {
        if (fileKey == token ||
            fileKey.contains(token) ||
            token.contains(fileKey)) {
          return path;
        }
      }
    }
    return null;
  }

  Future<List<String>> _listAllProductObjects() async {
    final root = FirebaseStorage.instance.ref('products');
    final out = <String>[];

    Future<void> walk(Reference ref) async {
      final list = await ref.listAll();
      for (final item in list.items) {
        out.add(item.fullPath);
      }
      for (final dir in list.prefixes) {
        await walk(dir);
      }
    }

    try {
      await walk(root);
    } catch (_) {
      // If listing is denied or fails, just return empty and keep normal fallbacks.
    }
    return out;
  }

  String _normalizeToken(String raw) {
    return raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  List<String> _buildCandidates(Map<String, dynamic> d) {
    final out = <String>[];
    const keys = [
      'imageUrl',
      'imageURL',
      'image',
      'photoUrl',
      'photoURL',
      'thumbnailUrl',
      'thumbnail',
      'imagePath',
      'storagePath',
    ];

    for (final k in keys) {
      final value = (d[k] ?? '').toString().trim();
      if (value.isNotEmpty) out.add(value);
    }

    final seedPath = seedImagePathForProduct(
      docId: widget.docId,
      id: (d['id'] ?? '').toString(),
      name: (d['name'] ?? '').toString(),
    );
    if (seedPath != null && seedPath.isNotEmpty) {
      out.add(seedPath);
    }

    final name = (d['name'] ?? '').toString().trim().toLowerCase();
    final category = (d['category'] ?? '').toString().trim().toLowerCase();
    final subCategory =
        (d['subCategory'] ?? d['subcategory'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    final rawIds = <String>{
      (d['id'] ?? '').toString().trim().toLowerCase(),
      (d['sku'] ?? '').toString().trim().toLowerCase(),
      (d['SKU'] ?? '').toString().trim().toLowerCase(),
    }..removeWhere((e) => e.isEmpty);

    final tokenVariants = <String>{};
    if (name.isNotEmpty) {
      final compact = name.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
      tokenVariants.addAll([
        compact,
        compact.replaceAll(' ', '_'),
        compact.replaceAll(' ', '-'),
      ]);
    }
    for (final id in rawIds) {
      final cleaned = id.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
      tokenVariants.addAll([
        id,
        cleaned,
        cleaned.replaceAll(' ', '_'),
        cleaned.replaceAll(' ', '-'),
      ]);
      if (id.startsWith('sku:')) {
        final skuOnly = id.replaceFirst('sku:', '').trim();
        tokenVariants.addAll([
          skuOnly,
          skuOnly.replaceAll(RegExp(r'[^a-z0-9]+'), '_'),
        ]);
      }
    }

    if (tokenVariants.isNotEmpty) {
      final folders = _guessFolders(category, subCategory, name);
      const exts = ['.png', '.webp', '.jpg', '.jpeg'];
      for (final folder in folders) {
        for (final v in tokenVariants) {
          for (final ext in exts) {
            out.add('$folder/$v$ext');
          }
        }
      }
    }
    return out;
  }

  List<String> _guessFolders(String category, String subCategory, String name) {
    final eyeHints = <String>[category, subCategory, name].join(' ');

    if (eyeHints.contains('eye') ||
        eyeHints.contains('mascara') ||
        eyeHints.contains('brow') ||
        eyeHints.contains('liner') ||
        eyeHints.contains('shadow')) {
      return const [
        'products/eye products/mascara',
        'products/eye products/eye liner',
        'products/eye products/eye shadows',
        'products/eye products/eye brow',
      ];
    }
    if (category.contains('lip')) {
      return const ['products/lipsticks'];
    }
    if (category.contains('face') || category.contains('makeup')) {
      return const ['products/face products'];
    }
    if (category.contains('hair')) {
      return const ['products/hair colors'];
    }
    return const [
      'products/eye products/mascara',
      'products/face products',
      'products/lipsticks',
      'products/hair colors',
    ];
  }

  String? _normalizeStoragePath(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://'))
      return null;
    if (value.startsWith('gs://')) {
      final withoutScheme = value.replaceFirst('gs://', '');
      final slashIndex = withoutScheme.indexOf('/');
      final extracted =
          slashIndex >= 0 ? withoutScheme.substring(slashIndex + 1) : '';
      return extracted.isEmpty ? null : _normalizeFolderAliases(extracted);
    }
    if (value.startsWith('assets/')) {
      return _normalizeFolderAliases(value.replaceFirst('assets/', ''));
    }
    if (value.startsWith('/products/')) {
      return _normalizeFolderAliases(value.substring(1));
    }
    if (value.startsWith('products/')) {
      return _normalizeFolderAliases(value);
    }
    if (!value.contains('://') && !value.startsWith('/')) {
      return _normalizeFolderAliases('products/$value');
    }
    return null;
  }

  String _normalizeFolderAliases(String path) {
    return path
        .replaceAll('eye products/eyeliner/', 'eye products/eye liner/')
        .replaceAll('eye products/eyebrow/', 'eye products/eye brow/')
        .replaceAll('eye products/eyeshadow/', 'eye products/eye shadows/')
        .replaceAll('eye products/eyeshadows/', 'eye products/eye shadows/');
  }

  List<String> _pathCandidates(String basePath) {
    final out = <String>{basePath};

    if (basePath.endsWith('.webp')) {
      out.add(basePath.replaceFirst('.webp', '.png'));
      out.add(basePath.replaceFirst('.webp', '.jpg'));
      out.add(basePath.replaceFirst('.webp', '.jpeg'));
    } else if (basePath.endsWith('.png')) {
      out.add(basePath.replaceFirst('.png', '.webp'));
      out.add(basePath.replaceFirst('.png', '.jpg'));
      out.add(basePath.replaceFirst('.png', '.jpeg'));
    } else if (basePath.endsWith('.jpg')) {
      out.add(basePath.replaceFirst('.jpg', '.png'));
      out.add(basePath.replaceFirst('.jpg', '.webp'));
      out.add(basePath.replaceFirst('.jpg', '.jpeg'));
    } else if (basePath.endsWith('.jpeg')) {
      out.add(basePath.replaceFirst('.jpeg', '.jpg'));
      out.add(basePath.replaceFirst('.jpeg', '.png'));
      out.add(basePath.replaceFirst('.jpeg', '.webp'));
    }

    out.add(basePath.replaceAll('_', ' '));
    out.add(basePath.replaceAll('-', ' '));
    out.add(basePath.replaceAll(' ', '_'));
    out.add(basePath.replaceAll(' ', '-'));

    return out.toList();
  }
}
