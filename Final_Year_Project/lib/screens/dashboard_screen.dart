import 'package:la_vogue_vista/widgets/firebase_image.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/firestore_service.dart';
import 'ai_beauty_assistant_screen.dart';
import 'enhanced_ai_assistant_screen.dart';
import 'product_detail_page.dart';
import 'live_tryon_screen.dart';
import 'virtual_tryon_popup.dart';
import 'hair_color_tryon_screen.dart';
import 'hair_style_matcher_screen.dart';
import 'mens_shade_matcher_screen.dart';
import 'nail_tryon_landing.dart';
import 'cart_screen.dart';

/// Colors / helpers
const _roseTop = Color(0xFFF5F5F5);
const _roseMid = Color(0xFFF1ABAD);
const _roseBot = Color(0xFFF7BDBD);
const _maroon  = Color(0xFF7C150D);
const _ink     = Color(0xFF1F1F1F);
const _muted   = Color(0xFF8A8A8A);
const _gold    = Color(0xFFDCB568);
const _navBg   = Color(0xFFEDE5E5);

String rs(num n) =>
    'Rs. ${n.toStringAsFixed(0).replaceAll(RegExp(r'(\\d)(?=(\\d{3})+(?!\\d))'), r'$1,')}'
        .replaceAll('\\', '');

Icon _star(double r, int i) {
  final p = i + 1;
  if (r >= p) return const Icon(Icons.star, size: 16, color: Colors.red);
  if (r > p - 1) return const Icon(Icons.star_half, size: 16, color: Colors.red);
  return const Icon(Icons.star_border, size: 16, color: Colors.red);
}

/// Asset-first product image with network fallback
class _ProductImage extends StatelessWidget {
  final String imageUrl;   // optional http(s)
  final String imagePath;  // assets/...
  final double? width, height;
  final BoxFit fit;

  const _ProductImage({
    required this.imageUrl,
    required this.imagePath,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (imagePath.isNotEmpty && imagePath.startsWith('assets/')) {
      return FirebaseStorageImage(
        storagePath: imagePath,
        width: width,
        height: height,
        fit: fit,
      );
    }

    if (imageUrl.isNotEmpty && imageUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: fit,
        errorWidget: (_, __, ___) =>
        const Icon(Icons.broken_image, color: _muted, size: 48),
      );
    }

    return const Icon(Icons.broken_image, color: _muted, size: 48);
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _tab = 0;

  void _onNavTap(int i) {
    if (i == 1) {
      // "Try Live" → open the landing page as a full-screen route
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const VirtualTryOnLandingPage(),
        ),
      );
      return;
    }
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const _HomeFeed(),
      const _SimplePage(title: 'Home'), // index 1 is never shown (Try Live = push nav)
      const CartScreen(showBackButton: false),
      const _SimplePage(title: 'Settings'),
      const _SimplePage(title: 'Profile'),
    ];
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(children: [pages[_tab], const _AiAssistantFab()]),
      bottomNavigationBar: _FlatBottomNav(
        currentIndex: _tab,
        onTap: _onNavTap,
      ),
    );
  }
}

/// Home feed (Firestore + filter)
class _HomeFeed extends StatefulWidget {
  const _HomeFeed();
  @override
  State<_HomeFeed> createState() => _HomeFeedState();
}

class _HomeFeedState extends State<_HomeFeed> {
  // MUST match Firestore category values
  static const _categories = ['All', 'Lip Sticks', 'Makeup', 'Hair', 'Nails'];
  static const _makeupGroups = ['All Makeup', 'Eye Products', 'Face Products'];
  static const _eyeSubcategories = [
    'All Eye Products',
    'Mascara',
    'Eyeliner',
    'Eyeshadow',
    'Eyebrow',
  ];
  // Subcategories for the dedicated 'Face' tab — must match Firestore subCategory values.
  static const _faceSubcats = [
    'All',
    'Foundation',
    'Powder',
    'Blush',
    'Concealer',
    'Highlighter',
    'Contour & Bronzer',
  ];
  // Legacy subcategories used inside the Makeup > Face Products dropdown.
  static const _faceSubcategories = [
    'All Face Products',
    'Foundation',
    'Blush',
    'Concealer',
    'Powder',
    'Bronzer',
    'Highlighter',
  ];

  String _category = _categories.first;
  String _makeupGroup = _makeupGroups.first;
  String _makeupSubcategory = 'All Makeup';
  // Active subcategory when the 'Face' top-level tab is selected.
  String _faceSubcat = _faceSubcats.first;
  // Firestore category value to query (Hair tab queries 'Hair Colors').
  String get _firestoreCategory {
    if (_category == 'Hair') return 'Hair Colors';
    return _category;
  }

  Stream<List<Product>> _stream() =>
      FirestoreDb.instance.productsByCategory(_firestoreCategory);

  bool _containsAny(String text, List<String> keys) =>
      keys.any(text.contains);

  bool _isEyeProduct(Product p) {
    final s =
        '${p.id} ${p.name} ${p.category} ${p.imagePath} ${p.description}'
            .toLowerCase();
    return _containsAny(s, [
      'mas_',
      'es_',
      'el_',
      'eb_',
      '/eye products/',
      '/mascara/',
      '/eyeshadow',
      '/eyeshadows/',
      '/eyeliner/',
      '/eyebrow/',
      'mascara',
      'eyeliner',
      'eyeshadow',
      'eye shadow',
      'eyebrow',
      'brow',
      'kajal',
      'kohl',
      'lash',
    ]);
  }

  bool _isFaceProduct(Product p) {
    if (p.category == 'Face') return true;
    final s =
        '${p.id} ${p.name} ${p.category} ${p.imagePath} ${p.description}'
            .toLowerCase();
    return _containsAny(s, [
      '/face products/',
      'foundation',
      'blush',
      'concealer',
      'compact',
      'powder',
      'bronzer',
      'highlighter',
      'primer',
      'face ',
      ' face',
    ]);
  }

  bool _matchesEyeSub(Product p, String sub) {
    final s = '${p.id} ${p.name} ${p.imagePath} ${p.description}'.toLowerCase();
    switch (sub) {
      case 'Mascara':
        return _containsAny(s, ['mas_', '/mascara/', 'mascara', 'lash']);
      case 'Eyeliner':
        return _containsAny(s, ['el_', '/eyeliner/', 'eyeliner', 'kohl', 'kajal']);
      case 'Eyeshadow':
        return _containsAny(s, ['es_', '/eyeshadows/', 'eyeshadow', 'eye shadow']);
      case 'Eyebrow':
        return _containsAny(s, ['eb_', '/eyebrow/', 'eyebrow', 'brow']);
      default:
        return true;
    }
  }

  bool _matchesFaceSub(Product p, String sub) {
    // Prefer exact Firestore subCategory field match first.
    final storedSub = (p.compareData['subCategory'] as String? ?? '').trim();
    if (storedSub.isNotEmpty) {
      if (sub == 'Bronzer') return storedSub == 'Contour & Bronzer';
      return storedSub.toLowerCase() == sub.toLowerCase();
    }
    // Fallback: text heuristic (for legacy Makeup-category face products).
    final s = '${p.id} ${p.name} ${p.imagePath} ${p.description}'.toLowerCase();
    switch (sub) {
      case 'Foundation':
        return _containsAny(s, ['foundation', 'face base']);
      case 'Blush':
        return _containsAny(s, ['blush', 'rouge']);
      case 'Concealer':
        return _containsAny(s, ['concealer']);
      case 'Powder':
        return _containsAny(s, ['powder', 'compact']);
      case 'Bronzer':
        return _containsAny(s, ['bronzer', 'contour', 'sculpt']);
      case 'Highlighter':
        return _containsAny(s, ['highlighter', 'illuminator', 'glow']);
      default:
        return true;
    }
  }

  /// Filter for the dedicated 'Face' top-level tab subcategory chips.
  bool _matchesFaceTabSub(Product p, String sub) {
    if (sub == 'All') return true;
    final storedSub = (p.compareData['subCategory'] as String? ?? '').trim();
    if (storedSub.isNotEmpty) {
      return storedSub.toLowerCase() == sub.toLowerCase();
    }
    return _matchesFaceSub(p, sub);
  }

  List<Product> _applySubFilter(List<Product> items) {
    // Face top-level tab: filter by subcategory chip.
    if (_category == 'Face') {
      if (_faceSubcat == 'All') return items;
      return items.where((p) => _matchesFaceTabSub(p, _faceSubcat)).toList();
    }
    // Makeup tab: existing dropdown sub-filter.
    if (_category != 'Makeup') return items;
    if (_makeupGroup == 'All Makeup') return items;

    return items.where((p) {
      if (_makeupGroup == 'Eye Products') {
        if (!_isEyeProduct(p)) return false;
        if (_makeupSubcategory == 'All Eye Products') return true;
        return _matchesEyeSub(p, _makeupSubcategory);
      }
      if (_makeupGroup == 'Face Products') {
        if (!_isFaceProduct(p)) return false;
        if (_makeupSubcategory == 'All Face Products') return true;
        return _matchesFaceSub(p, _makeupSubcategory);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder<List<Product>>(
        stream: _stream(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error: ${snap.error}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rawItems = snap.data!;
          final items = _applySubFilter(rawItems);
          return CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: _HeaderBar()),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              if (_category == 'All' && items.isNotEmpty)
                SliverToBoxAdapter(
                    child: _HeroCarousel(items: items.take(4).toList())),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              // ── Top-level category chips ──────────────────────────────────
              SliverToBoxAdapter(
                child: _CenteredChips(
                  categories: _categories,
                  active: _category,
                  onChanged: (c) {
                    if (c == 'Nails') {
                      showNailTryOnEntry(context);
                      return;
                    }
                    setState(() {
                      _category = c;
                      _makeupGroup = _makeupGroups.first;
                      _makeupSubcategory = 'All Makeup';
                      _faceSubcat = _faceSubcats.first;
                    });
                  },
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              // ── Hair subcategory feature tiles ──────────────────────────────
              if (_category == 'Hair')
                SliverToBoxAdapter(
                  child: _HairFeatureTiles(),
                ),
              if (_category == 'Hair')
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              // ── Face subcategory chips ────────────────────────────────────
              if (_category == 'Face')
                SliverToBoxAdapter(
                  child: _FaceSubcatChips(
                    subcats: _faceSubcats,
                    active: _faceSubcat,
                    onChanged: (s) => setState(() => _faceSubcat = s),
                  ),
                ),
              if (_category == 'Face')
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
              // ── Makeup dropdown filters ──────────────────────────────────
              if (_category == 'Makeup')
                SliverToBoxAdapter(
                  child: _MakeupDropdownFilters(
                    groupOptions: _makeupGroups,
                    activeGroup: _makeupGroup,
                    subOptions: _makeupGroup == 'Eye Products'
                        ? _eyeSubcategories
                        : (_makeupGroup == 'Face Products'
                            ? _faceSubcategories
                            : const ['All Makeup']),
                    activeSub: _makeupSubcategory,
                    onGroupChanged: (group) => setState(() {
                      _makeupGroup = group;
                      _makeupSubcategory = group == 'Eye Products'
                          ? _eyeSubcategories.first
                          : (group == 'Face Products'
                              ? _faceSubcategories.first
                              : 'All Makeup');
                    }),
                    onSubChanged: (sub) => setState(() => _makeupSubcategory = sub),
                  ),
                ),
              if (_category == 'Makeup')
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
              if (items.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text('No products yet',
                          style: TextStyle(color: Colors.black54, fontSize: 16)),
                    ),
                  ),
                )
              else
                _ProductGrid(items: items),
            ],
          );
        },
      ),
    );
  }
}

class _MakeupDropdownFilters extends StatelessWidget {
  final List<String> groupOptions;
  final String activeGroup;
  final List<String> subOptions;
  final String activeSub;
  final ValueChanged<String> onGroupChanged;
  final ValueChanged<String> onSubChanged;

  const _MakeupDropdownFilters({
    required this.groupOptions,
    required this.activeGroup,
    required this.subOptions,
    required this.activeSub,
    required this.onGroupChanged,
    required this.onSubChanged,
  });

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: _ink,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
          filled: true,
          fillColor: const Color(0xFFFFF6F6),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE8C7C7)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE8C7C7)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _maroon, width: 1.2),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: groupOptions.contains(activeGroup) ? activeGroup : groupOptions.first,
              decoration: deco('Makeup Type'),
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              items: groupOptions
                  .map((o) => DropdownMenuItem<String>(value: o, child: Text(o)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onGroupChanged(v);
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: subOptions.contains(activeSub) ? activeSub : subOptions.first,
              decoration: deco('Subcategory'),
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              items: subOptions
                  .map((o) => DropdownMenuItem<String>(value: o, child: Text(o)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onSubChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: SizedBox(
        height: 44,
        child: Stack(alignment: Alignment.center, children: [
          Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                  icon: const Icon(Icons.menu_rounded, color: _ink),
                  onPressed: () {})),
          Center(
            child: StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (_, s) {
                final u = s.data;
                final name = u?.displayName ?? u?.email ?? 'Guest';
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  const CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(0xFFFFE5E5),
                      child: Icon(Icons.person, color: _maroon, size: 14)),
                  const SizedBox(width: 10),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 18, color: _ink),
                      children: [
                        const TextSpan(
                            text: 'Hello ',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        TextSpan(
                            text: name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w400,
                                color: Colors.black54)),
                        const TextSpan(text: '!'),
                      ],
                    ),
                  ),
                ]);
              },
            ),
          ),
          Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                  icon: const Icon(Icons.search_rounded, color: _ink),
                  onPressed: () {})),
        ]),
      ),
    );
  }
}

/// HERO
class _HeroCarousel extends StatefulWidget {
  final List<Product> items;
  const _HeroCarousel({required this.items});
  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  late final PageController _ctrl = PageController();
  int _idx = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || widget.items.isEmpty) return;
      _idx = (_idx + 1) % widget.items.length;
      _ctrl.animateToPage(_idx,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final scale = MediaQuery.of(context).textScaler.scale(1.0);
    double h = w < 380 ? 276 : (w < 420 ? 252 : 236);
    h += (scale - 1.0) * 28;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: PageView.builder(
          controller: _ctrl,
          itemCount: widget.items.length,
          onPageChanged: (i) => setState(() => _idx = i),
          itemBuilder: (_, i) => _HeroCard(item: widget.items[i]),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final Product item;
  const _HeroCard({required this.item});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF4F4F4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Expanded(
          flex: 6,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.brand, style: const TextStyle(fontSize: 12, color: _muted)),
                const SizedBox(height: 2),
                Text(item.name.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: .2)),
                const SizedBox(height: 6),
                Row(children: [
                  ...List.generate(5, (i) => _star(item.rating, i)),
                  const SizedBox(width: 8),
                  Text(rs(item.price),
                      style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${item.rating.toStringAsFixed(1)} (${item.reviews}) · Write a review',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                _DualPillCTA(
                  onLeft: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LiveTryOnScreen(
                        productId: item.id,
                        productName: item.name,
                        productImage: item.imagePath,
                        productCategory: item.category,
                        shades: item.shades,
                      ),
                      settings: RouteSettings(
                        arguments: {
                          'productId': item.id,
                          'productName': item.name,
                          'productImage': item.imagePath,
                          'productCategory': item.category,
                          'shades': item.shades,
                        },
                      ),
                    ),
                  ),
                  onRight: () => FirestoreDb.instance.addToCart(
                    FirebaseAuth.instance.currentUser!.uid,
                    item,
                  ),
                  width: 210,
                ),
              ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: Align(
            alignment: Alignment.centerRight,
            child: _ProductImage(
              imageUrl: item.imageUrl,
              imagePath: item.imagePath, // assets/.. exact
              width: 150,
              height: 150,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ]),
    );
  }
}

class _DualPillCTA extends StatelessWidget {
  final double width;
  final VoidCallback onLeft, onRight;
  const _DualPillCTA({required this.onLeft, required this.onRight, this.width = 240});
  @override
  Widget build(BuildContext context) {
    const h = 38.0, r = 20.0;
    return Material(
      color: Colors.transparent,
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(r),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: SizedBox(
          height: h,
          width: width,
          child: Row(children: [
            Expanded(
              child: InkWell(
                onTap: onLeft,
                child: Container(
                  color: _gold,
                  alignment: Alignment.center,
                  child: const Text('LIVE TRY ON',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            Container(width: 1, height: h, color: Colors.black),
            Expanded(
              child: InkWell(
                onTap: onRight,
                child: Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: const Text('ADD TO CART',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// HORIZONTAL, SCROLLABLE CHIPS
class _CenteredChips extends StatelessWidget {
  final List<String> categories;
  final String active;
  final ValueChanged<String> onChanged;
  const _CenteredChips({
    required this.categories,
    required this.active,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        itemBuilder: (_, i) {
          final label = categories[i];
          return _CategoryChip(
            label: label,
            active: active == label,
            onTap: () => onChanged(label),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 12),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _CategoryChip({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active ? Colors.white : const Color(0xFFFFF6F6),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: active ? _maroon : const Color(0xFFE8C7C7), width: 1.5),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? _maroon : _ink, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

/// Horizontally-scrollable chip row for Face subcategories.
class _FaceSubcatChips extends StatelessWidget {
  final List<String> subcats;
  final String active;
  final ValueChanged<String> onChanged;

  const _FaceSubcatChips({
    required this.subcats,
    required this.active,
    required this.onChanged,
  });

  IconData _iconFor(String sub) {
    switch (sub) {
      case 'Foundation':    return Icons.water_drop_outlined;
      case 'Powder':        return Icons.cloud_outlined;
      case 'Blush':         return Icons.favorite_border_rounded;
      case 'Concealer':     return Icons.brush_outlined;
      case 'Highlighter':   return Icons.auto_awesome_outlined;
      case 'Contour & Bronzer': return Icons.palette_outlined;
      default:              return Icons.grid_view_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: subcats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final label = subcats[i];
          final isActive = active == label;
          return GestureDetector(
            onTap: () => onChanged(label),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: isActive
                    ? const LinearGradient(
                        colors: [Color(0xFF7C150D), Color(0xFFB84A4A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isActive ? null : const Color(0xFFFFF6F6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive ? Colors.transparent : const Color(0xFFE8C7C7),
                  width: 1.2,
                ),
                boxShadow: isActive
                    ? [BoxShadow(color: _maroon.withOpacity(.22), blurRadius: 6, offset: const Offset(0, 2))]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _iconFor(label),
                    size: 15,
                    color: isActive ? Colors.white : _maroon,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isActive ? Colors.white : _ink,
                      letterSpacing: .2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}


// ─── Hair Feature Chips ────────────────────────────────────────────────────────
class _HairFeatureTiles extends StatelessWidget {
  const _HairFeatureTiles();

  @override
  Widget build(BuildContext context) {
    const chips = [
      _HairChipData(
        emoji: '🎨',
        title: 'Colour Match',
        gradient: [Color(0xFF7C150D), Color(0xFFB84A4A)],
        screen: 'colour',
      ),
      _HairChipData(
        emoji: '💇',
        title: 'Style Match',
        gradient: [Color(0xFF1A237E), Color(0xFF3949AB)],
        screen: 'style',
      ),
      _HairChipData(
        emoji: '🧔',
        title: "Men's Shade",
        gradient: [Color(0xFF1B5E20), Color(0xFF388E3C)],
        screen: 'mens',
      ),
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) => _HairChip(data: chips[i]),
      ),
    );
  }
}

class _HairChipData {
  final String emoji, title, screen;
  final List<Color> gradient;
  const _HairChipData({
    required this.emoji,
    required this.title,
    required this.gradient,
    required this.screen,
  });
}

class _HairChip extends StatelessWidget {
  final _HairChipData data;
  const _HairChip({required this.data});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () {
        switch (data.screen) {
          case 'colour':
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => const HairColorTryOnScreen()));
            break;
          case 'style':
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => const HairStyleMatcherScreen()));
            break;
          case 'mens':
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => const MensShadeMatcher()));
            break;
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: data.gradient,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(
              color: data.gradient.last.withOpacity(.25),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(data.emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            Text(
              data.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: .2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  final List<Product> items;
  const _ProductGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: 290,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        delegate: SliverChildBuilderDelegate((context, i) {
          final p = items[i];
          return Material(
            elevation: .6,
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ProductDetailPage(product: p)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Center(
                        child: _ProductImage(
                          imageUrl: p.imageUrl,
                          imagePath: p.imagePath,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      p.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, height: 1.1),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rs(p.price),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, color: _ink),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ...List.generate(5, (i) => _star(p.rating, i)),
                        const SizedBox(width: 6),
                        Text('(${p.reviews})',
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 36,
                      child: ElevatedButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ProductDetailPage(product: p)),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _ink,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6)),
                        ),
                        child: const Text('VIEW PRODUCT',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }, childCount: items.length),
      ),
    );
  }
}

/// AI FAB (now tappable) + bottom nav + simple page
class _AiAssistantFab extends StatefulWidget {
  const _AiAssistantFab();
  @override
  State<_AiAssistantFab> createState() => _AiAssistantFabState();
}

class _AiAssistantFabState extends State<_AiAssistantFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
  AnimationController(vsync: this, duration: const Duration(seconds: 3))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _openAssistant() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AiSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding.bottom;
    return Positioned(
      right: 16,
      bottom: 78 + 8 + pad,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          final wave = math.sin(t * math.pi * 2);
          final glow = 10 + 4 * wave.abs();
          return Transform.translate(
            offset: Offset(0, 2.5 * wave),
            child: GestureDetector(
              onTap: _openAssistant,
              child: Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: _maroon.withOpacity(.12),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: const Color(0xFFA855F7).withOpacity(.30),
                      blurRadius: glow,
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset('assets/icons/ai.png', fit: BoxFit.cover),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The popup content (your AI sheet)
class _AiSheet extends StatelessWidget {
  const _AiSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 18)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38, height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: const [
                Icon(Icons.smart_toy_rounded, color: _maroon),
                SizedBox(width: 8),
                Text('AI Assistant',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: _ink)),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Hi! Ask me to recommend shades, match your skin tone, or find the best deal.',
              style: TextStyle(color: _ink),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 46, width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Chat with AI'),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AIBeautyAssistantScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _maroon, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 46, width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.face_retouching_natural_rounded),
                label: const Text('AI Skin & Hair Analysis'),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EnhancedAIAssistantScreen(),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _maroon,
                  side: const BorderSide(color: _maroon),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Bottom nav flush with bottom edge (no SafeArea bottom padding)
class _FlatBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _FlatBottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Remove system bottom padding so the bar hugs the edge
    return MediaQuery.removePadding(
      context: context,
      removeBottom: true,
      child: Container(
        height: 70,
        decoration: const BoxDecoration(
          color: _navBg,
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(18), topRight: Radius.circular(18)),
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: const [
            _NavItem(0, Icons.home_rounded, 'Home'),
            _NavItem(2, Icons.shopping_cart_rounded, 'Cart'),
            _NavItem(1, Icons.camera_alt_rounded, 'Try Live'),
            _NavItem(3, Icons.settings_rounded, 'Settings'),
            _NavItem(4, Icons.person_rounded, 'Profile'),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final int index;
  final IconData icon;
  final String label;
  const _NavItem(this.index, this.icon, this.label);
  @override
  Widget build(BuildContext context) {
    final parent = context.findAncestorWidgetOfExactType<_FlatBottomNav>()!;
    final active = parent.currentIndex == index;
    final color = active ? _maroon : _muted;
    return InkWell(
      onTap: () => parent.onTap(index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: color)),
        ]),
      ),
    );
  }
}

class _SimplePage extends StatelessWidget {
  final String title;
  const _SimplePage({required this.title});
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [_roseTop, _roseMid, _roseBot], stops: [0.0, .77, 1.0],
      ),
    ),
    child: SafeArea(
      child: Center(
        child: Text(title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      ),
    ),
  );
}
