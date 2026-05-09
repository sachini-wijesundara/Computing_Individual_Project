import 'package:la_vogue_vista/widgets/firebase_image.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cart_provider.dart';

import '../models/product.dart';
import '../models/product_review.dart';
import '../services/firestore_service.dart';
import 'live_tryon_screen.dart';
import 'cart_screen.dart';

// ── Colour constants (same palette as dashboard) ──────────────────────────────
const _maroon = Color(0xFF7C150D);
const _ink    = Color(0xFF1F1F1F);
const _muted  = Color(0xFF8A8A8A);

String _rs(num n) =>
    'Rs. ${n.toStringAsFixed(0).replaceAll(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), r'$1,')}';

Icon _star(double r, int i) {
  final p = i + 1;
  if (r >= p) return const Icon(Icons.star, size: 16, color: Colors.red);
  if (r > p - 1) return const Icon(Icons.star_half, size: 16, color: Colors.red);
  return const Icon(Icons.star_border, size: 16, color: Colors.red);
}

// ──────────────────────────────────────────────────────────────────────────────

class ProductDetailPage extends StatefulWidget {
  final Product product;
  const ProductDetailPage({super.key, required this.product});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  bool _addedToCart = false;
  List<Map<String, String>> _detailShades = const [];
  int _selectedShadeIndex = 0;
  late final Stream<List<ProductReview>> _reviewsStream;

  Product get p => widget.product;

  @override
  void initState() {
    super.initState();
    _reviewsStream = FirestoreDb.instance.productReviewsStream(p.id);
    _detailShades = _normalizeShades(p.shades);
    _seedSelectedShade();
    _refreshShadesFromFirestore();
  }

  String _formatReviewDate(DateTime? t) {
    if (t == null) return '';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  Future<void> _openReviewSheet() async {
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in to write a review.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    var draftRating = 5;
    final commentCtrl = TextEditingController();
    final name = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : (user.email != null && user.email!.contains('@'))
            ? user.email!.split('@').first
            : 'Customer';

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Write a review',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        icon: const Icon(Icons.close_rounded, color: _muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Your rating', style: TextStyle(color: _muted, fontSize: 13)),
                  const SizedBox(height: 6),
                  Row(
                    children: List.generate(5, (i) {
                      final filled = i < draftRating;
                      return IconButton(
                        onPressed: () => setModal(() => draftRating = i + 1),
                        icon: Icon(
                          filled ? Icons.star_rounded : Icons.star_border_rounded,
                          color: filled ? Colors.red : _muted,
                          size: 32,
                        ),
                      );
                    }),
                  ),
                  TextField(
                    controller: commentCtrl,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      alignLabelWithHint: true,
                      labelText: 'Comment (optional)',
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: _maroon, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _ink,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Submit', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (submitted != true || !mounted) return;

    try {
      await FirestoreDb.instance.upsertProductReview(
        productId: p.id,
        uid: user.uid,
        rating: draftRating,
        comment: commentCtrl.text,
        userDisplayName: name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thanks — your review was saved.'),
          backgroundColor: Color(0xFF1F8A43),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final hint = e.code == 'permission-denied'
          ? ' Check Firestore rules are deployed (firebase deploy --only firestore:rules).'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save review (${e.code}): ${e.message}$hint'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save review: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      commentCtrl.dispose();
    }
  }

  // Parse hex colour from Firestore (e.g. '#C0392B' or 'C0392B')
  Color _hexColor(String hex) {
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return _maroon;
  }

  String _normalizeHex(String raw) {
    var s = raw.trim();
    if (s.startsWith('0x') || s.startsWith('0X')) s = s.substring(2);
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 8) s = s.substring(2); // AARRGGBB -> RRGGBB
    if (s.length != 6 || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s)) {
      return p.colorHex;
    }
    return '#${s.toUpperCase()}';
  }

  List<Map<String, String>> _normalizeShades(List<Map<String, String>> raw) {
    final out = <Map<String, String>>[];
    for (final shade in raw) {
      final hex = shade['hex'] ??
          shade['colorHex'] ??
          shade['colourHex'] ??
          shade['color'] ??
          shade['colour'] ??
          shade['value'];
      if (hex == null || hex.trim().isEmpty) continue;
      out.add({
        'name': shade['name'] ?? shade['shade'] ?? 'Shade',
        'hex': _normalizeHex(hex),
      });
    }
    return out;
  }

  void _seedSelectedShade() {
    if (_detailShades.isEmpty) return;
    final current = _normalizeHex(p.colorHex);
    final idx = _detailShades.indexWhere((s) => s['hex'] == current);
    _selectedShadeIndex = idx >= 0 ? idx : 0;
  }

  Future<void> _refreshShadesFromFirestore() async {
    final shades = await FirestoreDb.instance.getProductShades(
      productId: p.id,
      productName: p.name,
      imagePath: p.imagePath,
    );
    if (!mounted || shades.isEmpty) return;
    final normalized = _normalizeShades(shades);
    if (normalized.isEmpty) return;
    setState(() {
      _detailShades = normalized;
      _seedSelectedShade();
    });
  }

  String get _selectedHex {
    if (_detailShades.isEmpty) return _normalizeHex(p.colorHex);
    final idx = _selectedShadeIndex.clamp(0, _detailShades.length - 1);
    return _detailShades[idx]['hex'] ?? _normalizeHex(p.colorHex);
  }

  String get _selectedShadeName {
    if (_detailShades.isEmpty) return 'Shade';
    final idx = _selectedShadeIndex.clamp(0, _detailShades.length - 1);
    return _detailShades[idx]['name'] ?? 'Shade';
  }

  void _addToCart() async {
    final cart = Provider.of<CartProvider>(context, listen: false);
    
    // Get the currently selected shade if available
    ProductShade? selectedShade;
    if (_detailShades.isNotEmpty) {
      final shadeData = _detailShades[_selectedShadeIndex];
      selectedShade = ProductShade(name: shadeData['name'] ?? 'Shade');
    }

    // Update local provider state for immediate UI feedback
    cart.addToCart(p, shade: selectedShade);

    // Sync with Firestore in background
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirestoreDb.instance.addToCart(uid, p);
    }
    
    if (!mounted) return;
    setState(() => _addedToCart = true);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${p.name} added to cart!'),
        backgroundColor: const Color(0xFF1F8A43),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Redirect to Cart Page
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CartScreen()),
        );
      }
    });
  }

  void _liveTryOn() {
    final shades = _detailShades.isNotEmpty ? _detailShades : _normalizeShades(p.shades);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveTryOnScreen(
          productId: p.id,
          productName: p.name,
          productImage: p.imagePath,
          productCategory: p.category,
          productColor: _hexColor(_selectedHex),
          shadeName: _selectedShadeName,
          shades: shades,
        ),
        settings: RouteSettings(
          arguments: {
            'productId': p.id,
            'productName': p.name,
            'productImage': p.imagePath,
            'productCategory': p.category,
            'subCategory': p.subCategory,   // <-- passed for face product routing
            'productColor': _hexColor(_selectedHex),
            'shadeName': _selectedShadeName,
            'shades': shades,
          },
        ),
      ),
    );
  }

  // ── Image widget ─────────────────────────────────────────────────────────────

  Widget _productImage() {
    if (p.imagePath.isNotEmpty && p.imagePath.startsWith('assets/')) {
      return FirebaseStorageImage(storagePath: p.imagePath,
        fit: BoxFit.contain,
      );
    }
    return _networkOrPlaceholder();
  }

  Widget _networkOrPlaceholder() {
    if (p.imageUrl.isNotEmpty && p.imageUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: p.imageUrl,
        fit: BoxFit.contain,
        errorWidget: (_, __, ___) =>
            const Icon(Icons.broken_image, size: 80, color: _muted),
      );
    }
    return const Icon(Icons.broken_image, size: 80, color: _muted);
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          p.brand.isNotEmpty ? p.brand : 'Product',
          style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.favorite_border_rounded, color: _maroon),
            onPressed: () async {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) {
                await FirestoreDb.instance.toggleFavourite(uid, p.id);
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<List<ProductReview>>(
        stream: _reviewsStream,
        builder: (context, snap) {
          final reviews = snap.data ?? const <ProductReview>[];
          final hasLive = reviews.isNotEmpty;
          final avg = hasLive
              ? reviews.fold<int>(0, (s, r) => s + r.rating) / reviews.length
              : p.rating;
          final summaryCount =
              hasLive ? reviews.length : p.reviews;
          final summarySuffix = hasLive
              ? ' customer review${reviews.length == 1 ? '' : 's'}'
              : ' reviews · add yours below';

          return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          // ── Product image ─────────────────────────────────────────────────
          Container(
            height: 280,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(24),
            child: Center(child: _productImage()),
          ),
          const SizedBox(height: 20),

          // ── Category / subCategory badge ──────────────────────────────────
          Wrap(
            spacing: 8,
            children: [
              _Badge(
                label: p.category.toUpperCase(),
                color: _maroon,
              ),
              if (p.subCategory.isNotEmpty)
                _Badge(
                  label: p.subCategory.toUpperCase(),
                  color: const Color(0xFF8B4513),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Name & brand ──────────────────────────────────────────────────
          Text(
            p.name,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: _ink),
          ),
          if (p.brand.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(p.brand,
                style: const TextStyle(fontSize: 14, color: _muted)),
          ],
          const SizedBox(height: 10),

          // ── Rating row (live customer reviews + catalog fallback) ─────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...List.generate(5, (i) => _star(avg, i)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${avg.toStringAsFixed(1)} ($summaryCount$summarySuffix)',
                  style: const TextStyle(fontSize: 13, color: _ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Price ─────────────────────────────────────────────────────────
          Text(
            _rs(p.price),
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w900, color: _ink),
          ),
          const SizedBox(height: 16),

          // ── Shade swatches ────────────────────────────────────────────────
          if (_detailShades.isNotEmpty || p.colorHex.isNotEmpty) ...[
            Row(
              children: [
                const Text('Shades',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: _ink, fontSize: 14)),
                if (_detailShades.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(${_detailShades.length} available)',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            if (_detailShades.isNotEmpty)
              // Use Wrap grid for products with many shades (face products)
              _detailShades.length > 12
                  ? Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: List.generate(_detailShades.length, (i) {
                        final shade = _detailShades[i];
                        final hex = shade['hex'] ?? '#C0392B';
                        final selected = i == _selectedShadeIndex;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedShadeIndex = i),
                          child: Tooltip(
                            message: shade['name'] ?? 'Shade',
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: _hexColor(hex),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected ? _maroon : Colors.black12,
                                  width: selected ? 2.5 : 1.2,
                                ),
                                boxShadow: selected
                                    ? [BoxShadow(
                                        color: _hexColor(hex).withValues(alpha: 0.45),
                                        blurRadius: 8,
                                      )]
                                    : null,
                              ),
                              child: selected
                                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                                  : null,
                            ),
                          ),
                        );
                      }),
                    )
                  : SizedBox(
                      height: 52,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _detailShades.length,
                        itemBuilder: (context, i) {
                          final shade = _detailShades[i];
                          final hex = shade['hex'] ?? '#C0392B';
                          final selected = i == _selectedShadeIndex;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedShadeIndex = i),
                            child: Container(
                              margin: const EdgeInsets.only(right: 10),
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: _hexColor(hex),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected ? _maroon : Colors.black12,
                                  width: selected ? 2.5 : 1.2,
                                ),
                                boxShadow: selected
                                    ? [BoxShadow(
                                        color: _hexColor(hex).withValues(alpha: 0.45),
                                        blurRadius: 8,
                                      )]
                                    : null,
                              ),
                              child: selected
                                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                                  : null,
                            ),
                          );
                        },
                      ),
                    )
            else
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _hexColor(_selectedHex),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black12, width: 2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(_selectedHex,
                      style: const TextStyle(color: _muted, fontSize: 13)),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  _selectedShadeName,
                  style: const TextStyle(
                    color: _ink, fontSize: 13, fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(_selectedHex,
                    style: const TextStyle(color: _muted, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // ── Description ───────────────────────────────────────────────────
          if (p.description.isNotEmpty) ...[
            const Text('About this product',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: _ink, fontSize: 14)),
            const SizedBox(height: 6),
            Text(
              p.description,
              style: const TextStyle(color: _ink, height: 1.6, fontSize: 14),
            ),
            const SizedBox(height: 20),
          ],

          // ── CTA buttons ───────────────────────────────────────────────────
          Row(
            children: [
              // Live try-on button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _liveTryOn,
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text('LIVE TRY ON'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _maroon,
                    side: const BorderSide(color: _maroon, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Add to cart button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _addedToCart ? null : _addToCart,
                  icon: Icon(
                      _addedToCart ? Icons.check : Icons.shopping_cart_rounded),
                  label: Text(_addedToCart ? 'ADDED' : 'ADD TO CART'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.green.shade700,
                    disabledForegroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── Customer reviews ────────────────────────────────────────────
          Row(
            children: [
              const Text(
                'Customer reviews',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _openReviewSheet,
                icon: const Icon(Icons.rate_review_outlined, size: 20, color: _maroon),
                label: const Text(
                  'Write a review',
                  style: TextStyle(
                    color: _maroon,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (snap.hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Could not load reviews.',
                style: TextStyle(color: Colors.red.shade800, fontSize: 13),
              ),
            ),
          if (reviews.isEmpty && snap.connectionState != ConnectionState.waiting)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'No customer reviews yet. Share your experience with this product.',
                style: TextStyle(color: _muted, fontSize: 14, height: 1.4),
              ),
            ),
          ...reviews.map((r) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.userDisplayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _ink,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Text(
                            _formatReviewDate(r.createdAt ?? r.updatedAt),
                            style: const TextStyle(fontSize: 12, color: _muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: List.generate(5, (i) => _star(r.rating.toDouble(), i)),
                      ),
                      if (r.comment.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          r.comment,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 24),
        ],
          );
        },
      ),
    );
  }
}

// ── Small reusable badge pill ─────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
