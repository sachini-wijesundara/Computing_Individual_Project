import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:la_vogue_vista/widgets/firebase_image.dart';

import '../models/product.dart';
import '../services/firestore_service.dart';
import '../utils/price_format.dart';
import 'product_detail_page.dart';

const _bgTop = Color(0xFFF5F5F5);
const _bgMid = Color(0xFFF1ABAD);
const _bgBot = Color(0xFFF7BDBD);
const _ink = Color(0xFF121212);
const _maroon = Color(0xFF7C150D);
const _muted = Color(0xFF6B6B6B);

/// Lists products saved under `users/{uid}.favourites` (same field used on product detail ♥).
class WishlistScreen extends StatelessWidget {
  final bool showBackButton;

  const WishlistScreen({super.key, this.showBackButton = true});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bgTop, _bgMid, _bgBot],
          stops: [0.0, 0.58, 1.0],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: showBackButton
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _ink),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
          title: const Text(
            'Wishlist',
            style: TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 19),
          ),
          centerTitle: true,
        ),
        body: user == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Sign in to save products to your wishlist and see them here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted.withValues(alpha: 0.95), fontSize: 15, height: 1.4),
                  ),
                ),
              )
            : StreamBuilder<List<String>>(
                stream: FirestoreDb.instance.favouriteProductIdsStream(user.uid),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('Could not load wishlist.\n${snap.error}',
                            textAlign: TextAlign.center),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: _maroon));
                  }
                  final ids = snap.data!;
                  if (ids.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.favorite_border_rounded,
                                size: 56, color: _muted.withValues(alpha: 0.45)),
                            const SizedBox(height: 16),
                            Text(
                              'Your wishlist is empty.\nOpen a product and tap the heart to add it.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: _muted.withValues(alpha: 0.95), fontSize: 15, height: 1.45),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return FutureBuilder<List<Product>>(
                    key: ValueKey<String>(ids.join('|')),
                    future: FirestoreDb.instance.fetchProductsByIdsInOrder(ids),
                    builder: (context, prodSnap) {
                      if (prodSnap.connectionState == ConnectionState.waiting && !prodSnap.hasData) {
                        return const Center(child: CircularProgressIndicator(color: _maroon));
                      }
                      if (prodSnap.hasError) {
                        return Center(child: Text('${prodSnap.error}'));
                      }
                      final products = prodSnap.data ?? [];
                      if (products.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Saved items could not be loaded. They may have been removed from the shop.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: products.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final p = products[i];
                          return _WishlistTile(
                            product: p,
                            uid: user.uid,
                          );
                        },
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}

Widget _wishlistThumb(Product product) {
  if (product.imagePath.isNotEmpty && product.imagePath.startsWith('assets/')) {
    return FirebaseStorageImage(
      storagePath: product.imagePath,
      fit: BoxFit.cover,
    );
  }
  if (product.imageUrl.isNotEmpty && product.imageUrl.startsWith('http')) {
    return CachedNetworkImage(
      imageUrl: product.imageUrl,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => const ColoredBox(
        color: Color(0xFFF0F0F0),
        child: Icon(Icons.broken_image_outlined, color: _muted),
      ),
    );
  }
  return const ColoredBox(
    color: Color(0xFFF0F0F0),
    child: Icon(Icons.image_outlined, color: _muted),
  );
}

class _WishlistTile extends StatelessWidget {
  final Product product;
  final String uid;

  const _WishlistTile({required this.product, required this.uid});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProductDetailPage(product: product),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: _wishlistThumb(product),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: _ink,
                      ),
                    ),
                    if (product.brand.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(product.brand,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: _muted)),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      formatRs(product.price),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _maroon,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove from wishlist',
                icon: const Icon(Icons.favorite_rounded, color: _maroon),
                onPressed: () async {
                  await FirestoreDb.instance.toggleFavourite(uid, product.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Removed "${product.name}" from wishlist'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
