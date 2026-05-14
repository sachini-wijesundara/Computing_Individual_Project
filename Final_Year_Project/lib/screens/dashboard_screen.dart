import 'package:la_vogue_vista/widgets/firebase_image.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/product.dart';
import '../utils/price_format.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';
import 'ai_beauty_assistant_screen.dart';
import 'enhanced_ai_assistant_screen.dart';
import 'product_detail_page.dart';
import 'live_tryon_screen.dart';
import 'virtual_tryon_popup.dart';
import 'hair_style_matcher_screen.dart';
import 'mens_shade_matcher_screen.dart';
import 'cart_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import 'support_chat_screen.dart';

/// Colors / helpers
const _roseTop = Color(0xFFF5F5F5);
const _roseMid = Color(0xFFF1ABAD);
const _roseBot = Color(0xFFF7BDBD);
const _maroon  = Color(0xFF7C150D);
const _ink     = Color(0xFF1F1F1F);
const _muted   = Color(0xFF8A8A8A);
const _gold    = Color(0xFFDCB568);
const _navBg   = Color(0xFFEDE5E5);

String rs(num n) => formatRs(n);
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
  final ScrollController _homeScroll = ScrollController();
  bool get _hideAiFabOnCurrentTab => _tab == 2 || _tab == 3 || _tab == 4;

  void _scrollHomeToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_homeScroll.hasClients) return;
      _homeScroll.animateTo(
        0,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    });
  }

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
    if (i == 0) {
      if (_tab != 0) setState(() => _tab = 0);
      _scrollHomeToTop();
      return;
    }
    setState(() => _tab = i);
  }

  @override
  void dispose() {
    _homeScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _HomeFeed(scrollController: _homeScroll),
      const _SimplePage(title: 'Home'), // index 1 is never shown (Try Live = push nav)
      const CartScreen(showBackButton: false),
      SettingsScreen(
        showBackButton: true,
        onBack: () => setState(() => _tab = 0),
      ),
      ProfileScreen(
        showBackButton: true,
        onBack: () => setState(() => _tab = 0),
      ),
    ];
    return Scaffold(
      backgroundColor: Colors.white,
      drawer: _DashboardSideDrawer(
        onHome: () {
          Navigator.pop(context);
          if (_tab != 0) setState(() => _tab = 0);
          _scrollHomeToTop();
        },
        onLiveTryon: () {
          Navigator.pop(context);
          Navigator.of(context).push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => const VirtualTryOnLandingPage(),
            ),
          );
        },
        onAiSkinHair: () {
          Navigator.pop(context);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const EnhancedAIAssistantScreen(),
            ),
          );
        },
        onSettings: () {
          Navigator.pop(context);
          setState(() => _tab = 3);
        },
        onProfile: () {
          Navigator.pop(context);
          setState(() => _tab = 4);
        },
        onLogout: () async {
          Navigator.pop(context);
          await FirebaseAuthService.signOut();
        },
      ),
      body: Stack(
        children: [
          pages[_tab],
          if (!_hideAiFabOnCurrentTab) const _AiAssistantFab(),
        ],
      ),
      bottomNavigationBar: _FlatBottomNav(
        currentIndex: _tab,
        onTap: _onNavTap,
      ),
    );
  }
}

class _DashboardSideDrawer extends StatelessWidget {
  const _DashboardSideDrawer({
    required this.onHome,
    required this.onLiveTryon,
    required this.onAiSkinHair,
    required this.onSettings,
    required this.onProfile,
    required this.onLogout,
  });

  final VoidCallback onHome;
  final VoidCallback onLiveTryon;
  final VoidCallback onAiSkinHair;
  final VoidCallback onSettings;
  final VoidCallback onProfile;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DrawerHeader(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF5C0F0A), _maroon, Color(0xFFA32A1F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'La Vogue Vista',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.98),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Navigate',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 8),
              children: [
                ListTile(
                  leading: const Icon(Icons.home_rounded, color: _maroon),
                  title: const Text(
                    'Home',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: onHome,
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt_rounded, color: _maroon),
                  title: const Text(
                    'Live try-on',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: onLiveTryon,
                ),
                ListTile(
                  leading: const Icon(
                    Icons.face_retouching_natural_rounded,
                    color: _maroon,
                  ),
                  title: const Text(
                    'AI analysis — skin & hair',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: onAiSkinHair,
                ),
                const Divider(height: 24),
                ListTile(
                  leading: const Icon(Icons.settings_rounded, color: _maroon),
                  title: const Text(
                    'Settings',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: onSettings,
                ),
                ListTile(
                  leading: const Icon(Icons.person_rounded, color: _maroon),
                  title: const Text(
                    'Profile',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: onProfile,
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottomInset),
            child: Center(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _maroon,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.logout_rounded, size: 20),
                label: const Text(
                  'Log out',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                onPressed: () async {
                  await onLogout();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Home feed (Firestore + filter)
class _HomeFeed extends StatefulWidget {
  final ScrollController scrollController;
  const _HomeFeed({required this.scrollController});
  @override
  State<_HomeFeed> createState() => _HomeFeedState();
}

class _HomeFeedState extends State<_HomeFeed> {
  // MUST match Firestore category values
  static const _categories = ['All', 'Lip Sticks', 'Makeup', 'Hair'];
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

  Future<void> _openProductSearch() async {
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 28, vertical: 22),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  SizedBox(width: 16),
                  Text(
                    'Loading products…',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    try {
      final products = await FirestoreDb.instance.fetchAllProducts();
      if (!mounted) return;
      Navigator.of(context).pop();
      if (products.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No products to search yet.')),
        );
        return;
      }
      if (!mounted) return;
      final selected = await showSearch<Product?>(
        context: context,
        delegate: _ProductSearchDelegate(_dedupeSearchCatalog(products)),
      );
      if (!mounted) return;
      if (selected != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProductDetailPage(product: selected),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(content: Text('Could not open search: $e')),
        );
      }
    }
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
            controller: widget.scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: _HeaderBar(onSearchTap: _openProductSearch),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              // ── Category chips at top (All, Lip Sticks, Makeup, Hair) ───────
              SliverToBoxAdapter(
                child: _CenteredChips(
                  categories: _categories,
                  active: _category,
                  onChanged: (c) {
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
              if (FirebaseAuth.instance.currentUser != null) ...[
                const SliverToBoxAdapter(child: _DiscoverImagePager()),
                if (items.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _FeaturedProductsSwipe(
                      products: items.take(16).toList(),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
              ],
              if (_category == 'All' &&
                  items.isNotEmpty &&
                  FirebaseAuth.instance.currentUser == null)
                SliverToBoxAdapter(
                    child: _HeroCarousel(items: items.take(4).toList())),
              if (FirebaseAuth.instance.currentUser == null &&
                  _category == 'All' &&
                  items.isNotEmpty)
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

/// Removes:
/// 1) duplicate document ids
/// 2) same normalized name + brand (legacy double-seeded SKUs)
/// 3) rows that reuse the same hero image with a different brand/title (common re-seed dupes)
List<Product> _dedupeSearchCatalog(List<Product> raw) {
  String norm(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Stable key for the visual used in lists (storage path or URL without query).
  String mediaKey(Product p) {
    final path = p.imagePath.trim();
    if (path.isNotEmpty) return 'p:${path.toLowerCase()}';
    final u = p.imageUrl.trim();
    if (u.isEmpty) return '';
    try {
      final uri = Uri.parse(u);
      if (uri.hasScheme && uri.host.isNotEmpty) {
        return 'u:${uri.scheme}://${uri.host}${uri.path}'.toLowerCase();
      }
    } catch (_) {}
    return 'u:${u.toLowerCase()}';
  }

  Product preferCatalogWinner(Product a, Product b) {
    bool vogue(Product x) {
      final t = x.brand.toLowerCase();
      return t.contains('vogue') || t.contains('la vogue');
    }
    if (vogue(a) && !vogue(b)) return a;
    if (vogue(b) && !vogue(a)) return b;
    return a.id.compareTo(b.id) <= 0 ? a : b;
  }

  final byId = <String, Product>{};
  for (final p in raw) {
    byId.putIfAbsent(p.id, () => p);
  }

  final byNameBrand = <String, Product>{};
  for (final p in byId.values) {
    final key = '${norm(p.name)}|${norm(p.brand)}';
    final existing = byNameBrand[key];
    if (existing == null) {
      byNameBrand[key] = p;
    } else {
      byNameBrand[key] = preferCatalogWinner(existing, p);
    }
  }

  final list = byNameBrand.values.toList();
  final byMedia = <String, Product>{};
  for (final p in list) {
    final mk = mediaKey(p);
    if (mk.isEmpty) {
      byMedia['__noimg_${p.id}'] = p;
      continue;
    }
    final existing = byMedia[mk];
    if (existing == null) {
      byMedia[mk] = p;
    } else {
      byMedia[mk] = preferCatalogWinner(existing, p);
    }
  }

  return byMedia.values.toList();
}

class _ProductSearchDelegate extends SearchDelegate<Product?> {
  _ProductSearchDelegate(this._all);
  final List<Product> _all;

  @override
  String get searchFieldLabel => 'Search by name, brand, category…';

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  List<Product> _filtered(String q) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) {
      final sorted = [..._all]..sort((a, b) => a.name.compareTo(b.name));
      return sorted.take(28).toList();
    }
    final out =
        _all.where((p) {
          final blob =
              '${p.name} ${p.brand} ${p.category} ${p.subCategory} ${p.description}'
                  .toLowerCase();
          return blob.contains(t);
        }).toList();
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, null),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    if (query.isEmpty) return null;
    return [
      IconButton(
        icon: const Icon(Icons.clear_rounded),
        onPressed: () {
          query = '';
          showSuggestions(context);
        },
      ),
    ];
  }

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final items = _filtered(query);
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            query.trim().isEmpty
                ? 'Start typing to find a product.'
                : 'No products match “$query”.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontSize: 16),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final p = items[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: SizedBox(
            width: 52,
            height: 52,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _ProductImage(
                imageUrl: p.imageUrl,
                imagePath: p.imagePath,
                fit: BoxFit.contain,
              ),
            ),
          ),
          title: Text(
            p.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, color: _ink),
          ),
          subtitle: Text(
            [
              if (p.brand.trim().isNotEmpty) p.brand,
              p.category,
              rs(p.price),
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          onTap: () => close(context, p),
        );
      },
    );
  }
}

/// Full-width image stories: live try-on, AI, hair — with asset art + auto swipe.
class _DiscoverImagePager extends StatefulWidget {
  const _DiscoverImagePager();

  @override
  State<_DiscoverImagePager> createState() => _DiscoverImagePagerState();
}

class _DiscoverImagePagerState extends State<_DiscoverImagePager> {
  late final PageController _pageController =
      PageController(viewportFraction: 0.92);
  int _page = 0;
  Timer? _timer;

  static const _slides = <_DiscoverSlide>[
    _DiscoverSlide(
      bannerAsset: 'assets/discover/discover_live_makeup_hair.png',
      title: 'Live makeup & hair',
      subtitle: 'Try lipstick, looks, and hair colour on camera',
      accent: Color(0xFF7C150D),
      shadowColor: Color(0xFF4A0D09),
    ),
    _DiscoverSlide(
      bannerAsset: 'assets/discover/discover_ai_beauty.png',
      title: 'AI skin & hair lab',
      subtitle: 'Smart analysis and tips tailored to you',
      accent: Color(0xFFD4A843),
      shadowColor: Color(0xFF311B92),
    ),
    _DiscoverSlide(
      bannerAsset: 'assets/discover/discover_hair_style.png',
      title: 'Hair style match',
      subtitle: 'Find catalogue cuts that suit your face',
      accent: Color(0xFF90CAF9),
      shadowColor: Color(0xFF0D2847),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _slides.isEmpty) return;
      final next = (_page + 1) % _slides.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_mosaic_rounded,
                  size: 20, color: _maroon.withValues(alpha: 0.95)),
              const SizedBox(width: 8),
              const Text(
                'Discover',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: _pageController,
            itemCount: _slides.length,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) {
              final s = _slides[i];
              return Padding(
                padding: const EdgeInsets.only(left: 6, right: 6, bottom: 4),
                child: _DiscoverSlideCard(
                  slide: s,
                  onTap: () => _openDiscover(context, i),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_slides.length, (i) {
            final on = i == _page;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: on ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: on ? _maroon : const Color(0xFFE0D4D4),
              ),
            );
          }),
        ),
      ],
    );
  }

  void _openDiscover(BuildContext context, int i) {
    switch (i) {
      case 0:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => const VirtualTryOnLandingPage(),
          ),
        );
        break;
      case 1:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const EnhancedAIAssistantScreen(),
          ),
        );
        break;
      default:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const HairStyleMatcherScreen(),
          ),
        );
    }
  }
}

class _DiscoverSlide {
  final String bannerAsset;
  final String title;
  final String subtitle;
  final Color accent;
  final Color shadowColor;

  const _DiscoverSlide({
    required this.bannerAsset,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.shadowColor,
  });
}

class _DiscoverSlideCard extends StatelessWidget {
  final _DiscoverSlide slide;
  final VoidCallback onTap;

  const _DiscoverSlideCard({
    required this.slide,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      shadowColor: slide.shadowColor.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              slide.bannerAsset,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (_, __, ___) => ColoredBox(
                color: slide.shadowColor,
                child: const Center(
                  child: Icon(Icons.image_not_supported_outlined,
                      color: Colors.white54, size: 48),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.02),
                      Colors.black.withValues(alpha: 0.18),
                      Colors.black.withValues(alpha: 0.62),
                    ],
                    stops: const [0.0, 0.42, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: slide.accent.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Try it',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    slide.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      height: 1.1,
                      letterSpacing: 0.2,
                      shadows: [
                        Shadow(
                          color: Color(0x66000000),
                          blurRadius: 8,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    slide.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 13,
                      height: 1.25,
                      shadows: const [
                        Shadow(
                          color: Color(0x66000000),
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              right: 14,
              child: Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white.withValues(alpha: 0.9),
                size: 26,
                shadows: const [
                  Shadow(color: Color(0x66000000), blurRadius: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Large image product carousel — swipe to browse picks, tap for detail.
class _FeaturedProductsSwipe extends StatefulWidget {
  final List<Product> products;

  const _FeaturedProductsSwipe({required this.products});

  @override
  State<_FeaturedProductsSwipe> createState() => _FeaturedProductsSwipeState();
}

class _FeaturedProductsSwipeState extends State<_FeaturedProductsSwipe> {
  late final PageController _ctrl = PageController(viewportFraction: 0.86);
  int _idx = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.products.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Row(
            children: [
              Icon(Icons.local_mall_outlined,
                  size: 20, color: _maroon.withValues(alpha: 0.9)),
              const SizedBox(width: 8),
              const Text(
                'Featured',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              Text(
                '${widget.products.length} items',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _muted.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 268,
          child: PageView.builder(
            controller: _ctrl,
            itemCount: widget.products.length,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (i) => setState(() => _idx = i),
            itemBuilder: (context, i) {
              final p = widget.products[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                child: Material(
                  elevation: 5,
                  shadowColor: Colors.black.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(22),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ProductDetailPage(product: p),
                        ),
                      );
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: const Color(0xFFF8F0F0),
                          child: _ProductImage(
                            imageUrl: p.imageUrl,
                            imagePath: p.imagePath,
                            width: 600,
                            height: 600,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.08),
                                  Colors.black.withValues(alpha: 0.72),
                                ],
                                stops: const [0.35, 0.55, 1],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 14,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (p.brand.trim().isNotEmpty)
                                Text(
                                  p.brand.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.82),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                p.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    rs(p.price),
                                    style: const TextStyle(
                                      color: Color(0xFFFFE0B2),
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ...List.generate(5, (k) => _star(p.rating, k)),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.95),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'View',
                                      style: TextStyle(
                                        color: _maroon.withValues(alpha: 0.95),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Center(
            child: Text(
              '${_idx + 1} / ${widget.products.length}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _muted.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({this.onSearchTap});
  final VoidCallback? onSearchTap;
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
              tooltip: 'Menu',
              icon: const Icon(Icons.menu_rounded, color: _ink),
              onPressed: () =>
                  Scaffold.maybeOf(context)?.openDrawer(),
            ),
          ),
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<User?>(
                  stream: FirebaseAuth.instance.authStateChanges(),
                  builder: (context, authSnap) {
                    final u = authSnap.data;
                    if (u == null) {
                      return IconButton(
                        tooltip: 'Chat with admin',
                        icon: const Icon(Icons.message_outlined, color: _ink),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SupportChatScreen(),
                            ),
                          );
                        },
                      );
                    }
                    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('support_chats')
                          .doc(u.uid)
                          .snapshots(),
                      builder: (context, chatSnap) {
                        final unread = chatSnap.data?.data()?['unreadForUser'] == true;
                        return IconButton(
                          tooltip: 'Chat with admin',
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SupportChatScreen(),
                              ),
                            );
                          },
                          icon: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.message_outlined, color: _ink),
                              if (unread)
                                Positioned(
                                  right: -1,
                                  top: -1,
                                  child: Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFCC1F1A),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Search products',
                  icon: const Icon(Icons.search_rounded, color: _ink),
                  onPressed: onSearchTap,
                ),
              ],
            ),
          ),
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
                        productImage: item.imagePath.isNotEmpty
                            ? item.imagePath
                            : item.imageUrl,
                        productCategory: item.category,
                        shades: item.shades,
                      ),
                      settings: RouteSettings(
                        arguments: {
                          'productId': item.id,
                          'productName': item.name,
                          'productImage': item.imagePath.isNotEmpty
                              ? item.imagePath
                              : item.imageUrl,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _HairChip(data: chips[0]),
            const SizedBox(width: 12),
            _HairChip(data: chips[1]),
          ],
        ),
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
                      builder: (context) => const EnhancedAIAssistantScreen(),
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
