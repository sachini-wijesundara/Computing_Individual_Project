
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/product.dart';
import '../native_lip_renderer.dart';
import '../services/firestore_service.dart';
import '../widgets/live_tryon_widgets.dart';
import '../widgets/firebase_image.dart';

// ── Colours ────────────────────────────────────────────────────────────────────
const _maroon = Color(0xFF7C150D);
const _gold   = Color(0xFFDCB568);
const _dark   = Color(0xFF121212);

enum TryOnMode { live, uploadPhoto }

// ── Category descriptor ────────────────────────────────────────────────────────
class _MakeupCat {
  final String label;
  final String firestoreCategory;
  final String? firestoreSubCategory;
  final String arCommand;
  final IconData icon;
  const _MakeupCat({
    required this.label,
    required this.firestoreCategory,
    this.firestoreSubCategory,
    required this.arCommand,
    required this.icon,
  });
}

const _kCats = <_MakeupCat>[
  _MakeupCat(label: 'Foundation',  firestoreCategory: 'Makeup', firestoreSubCategory: 'Foundation',        arCommand: 'cmd_face',      icon: Icons.water_drop_outlined),
  _MakeupCat(label: 'Concealer',   firestoreCategory: 'Makeup', firestoreSubCategory: 'Concealer',         arCommand: 'cmd_face',      icon: Icons.brush_outlined),
  _MakeupCat(label: 'Blush',       firestoreCategory: 'Makeup', firestoreSubCategory: 'Blush',             arCommand: 'cmd_blush',     icon: Icons.favorite_border_rounded),
  _MakeupCat(label: 'Highlighter', firestoreCategory: 'Makeup', firestoreSubCategory: 'Highlighter',       arCommand: 'cmd_highlight', icon: Icons.auto_awesome_outlined),
  _MakeupCat(label: 'Contour',     firestoreCategory: 'Makeup', firestoreSubCategory: 'Contour & Bronzer', arCommand: 'cmd_highlight', icon: Icons.palette_outlined),
  _MakeupCat(label: 'Lips',        firestoreCategory: 'Lip Sticks',                                      arCommand: 'cmd_lipstick',  icon: Icons.spa_outlined),
  _MakeupCat(label: 'Eye',         firestoreCategory: 'Makeup',                                          arCommand: 'cmd_eyeshadow', icon: Icons.remove_red_eye_outlined),
];

// ──────────────────────────────────────────────────────────────────────────────
class FullMakeupTryOnScreen extends StatefulWidget {
  final TryOnMode mode;
  const FullMakeupTryOnScreen({super.key, this.mode = TryOnMode.live});

  @override
  State<FullMakeupTryOnScreen> createState() => _FullMakeupTryOnScreenState();
}

class _FullMakeupTryOnScreenState extends State<FullMakeupTryOnScreen>
    with SingleTickerProviderStateMixin {

  // ── Native renderer ──────────────────────────────────────────────────────
  NativeLipRendererController? _nativeCtrl;
  bool _nativeReady = false;
  bool _nativeDebug = false;
  double _nativeFps  = 0;

  static const bool _useNative =
      bool.fromEnvironment('USE_NATIVE_LIP_RENDERER', defaultValue: true);
  bool get _shouldUseNative =>
      _useNative &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  // ── Makeup state ─────────────────────────────────────────────────────────
  int _activeCatIndex = 0;
  final Map<String, Product?> _applied       = {};  // label → applied Product
  final Map<String, int>      _shadeIdx      = {};  // label → shade index
  double _intensity = 0.4;

  // ── UI toggles ────────────────────────────────────────────────────────────
  bool   _showShades   = false;
  bool   _compareMode  = false;
  double _splitPos     = 0.5;

  // ── Upload photo ─────────────────────────────────────────────────────────
  String? _uploadedPath;

  // ── Firestore data ────────────────────────────────────────────────────────
  Set<String>               _favIds   = {};
  final Map<String, List<Product>> _products = {};
  final Map<String, bool>  _loading  = {};

  // ── Pulse anim ────────────────────────────────────────────────────────────
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _loadFavs();
    for (final c in _kCats) _loadProducts(c);
    if (widget.mode == TryOnMode.uploadPhoto) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickPhoto());
    }
  }

  @override
  void dispose() {
    _nativeCtrl?.dispose();
    _pulse.dispose();
    super.dispose();
  }

  // ── Firestore helpers ────────────────────────────────────────────────────
  Future<void> _loadFavs() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!mounted) return;
    setState(() => _favIds = Set<String>.from(doc.data()?['favourites'] ?? []));
  }

  Future<void> _loadProducts(_MakeupCat cat) async {
    if (_loading[cat.label] == true) return;
    setState(() => _loading[cat.label] = true);
    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('products')
          .where('category', isEqualTo: cat.firestoreCategory);
      if (cat.firestoreSubCategory != null) {
        q = q.where('subCategory', isEqualTo: cat.firestoreSubCategory);
      }
      final snap = await q.get();
      if (!mounted) return;
      setState(() {
        _products[cat.label] = snap.docs.map((d) => Product.fromFirestore(d)).toList();
        _loading[cat.label] = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading[cat.label] = false);
    }
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file != null && mounted) setState(() => _uploadedPath = file.path);
  }

  Future<void> _toggleFav(Product p) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirestoreDb.instance.toggleFavourite(uid, p.id);
    setState(() => _favIds.contains(p.id) ? _favIds.remove(p.id) : _favIds.add(p.id));
  }

  Future<void> _addToCart(Product p) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirestoreDb.instance.addToCart(uid, p);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${p.name} added to cart!'),
      backgroundColor: const Color(0xFF1F8A43),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── AR effect ─────────────────────────────────────────────────────────────
  void _applyEffect() {
    final ctrl = _nativeCtrl;
    if (ctrl == null) return;
    final cat     = _kCats[_activeCatIndex];
    final product = _applied[cat.label];
    if (product == null) {
      ctrl.setEffect(
          shade: const Color(0x00000000), intensity: 0,
          category: 'cmd_none', isCompareMode: _compareMode);
      return;
    }
    final shades = product.shades;
    final maxIdx = shades.isEmpty ? 0 : shades.length - 1;
    final idx    = (_shadeIdx[cat.label] ?? 0).clamp(0, maxIdx);
    final hex    = shades.isNotEmpty ? (shades[idx]['hex'] ?? product.colorHex) : product.colorHex;
    ctrl.setEffect(
      shade: _hex(hex),
      intensity: _intensity,
      category: cat.arCommand,
      isCompareMode: _compareMode,
    );
  }

  Color _hex(String h) {
    var s = h.replaceAll('#', '');
    if (s.length == 6) s = 'FF$s';
    return Color(int.parse(s, radix: 16));
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // Camera view
        Positioned.fill(child: _buildCamera()),
        // Compare overlay
        if (_compareMode) Positioned.fill(child: _buildCompare()),
        // Gradient fade at top and bottom for readability
        Positioned.fill(
          child: Column(children: [
            Container(height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
                ),
              ),
            ),
            const Spacer(),
            Container(height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter, end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.3), Colors.transparent],
                ),
              ),
            ),
          ]),
        ),
        // Top bar
        Positioned(top: 0, left: 0, right: 0,
          child: SafeArea(child: _buildTopBar())),
        // Bottom tray
        Positioned(bottom: 0, left: 0, right: 0,
          child: _buildBottomTray()),
      ]),
    );
  }

  // ── Camera ────────────────────────────────────────────────────────────────
  Widget _buildCamera() {
    if (widget.mode == TryOnMode.uploadPhoto && _uploadedPath != null) {
      return Image.asset(_uploadedPath!, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black));
    }
    if (_shouldUseNative) {
      return NativeLipRendererView(
        onViewCreated: (ctrl) {
          _nativeCtrl = ctrl;
          ctrl.listen((e) {
            if (!mounted) return;
            setState(() {
              if (e.type == 'ready') _nativeReady = true;
              if (e.type == 'fps') _nativeFps = e.fps ?? 0;
            });
          });
          ctrl.start();
          ctrl.setDebug(showLandmarks: false);
        },
        enableDebugOverlay: _nativeDebug,
      );
    }
    return const ColoredBox(color: _dark,
      child: Center(child: Text('Camera unavailable',
          style: TextStyle(color: Colors.white38))));
  }

  // ── Compare overlay ───────────────────────────────────────────────────────
  Widget _buildCompare() {
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth;
      final x = w * _splitPos.clamp(0.0, 1.0);
      void move(double dx) {
        setState(() => _splitPos = (_splitPos + dx / w).clamp(0.05, 0.95));
        _nativeCtrl?.setCalibration(splitPosition: _splitPos);
      }
      return Stack(children: [
        Positioned(left: x - 0.5, top: 0, bottom: 0,
          child: Container(width: 1, color: Colors.white.withValues(alpha: 0.9))),
        Positioned(left: x - 28, top: c.maxHeight * .5 - 28,
          child: GestureDetector(
            onHorizontalDragUpdate: (d) => move(d.delta.dx),
            child: Container(
              width: 56, height: 56,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)]),
              child: const Icon(Icons.compare_arrows_rounded, color: Colors.black87)),
          )),
        Positioned(left: x - 24, top: 0, bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: (d) => move(d.delta.dx),
            child: const SizedBox(width: 48))),
        const Positioned(left: 16, top: 80, child: _ComparePill('BEFORE')),
        const Positioned(right: 16, top: 80, child: _ComparePill('AFTER')),
      ]);
    });
  }

  // ── Top bar ───────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const Spacer(),
        const Text('VIRTUAL TRY-ON',
          style: TextStyle(color: Colors.white, fontSize: 14,
              fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        const Spacer(),
        Hud(ready: _nativeReady, fps: _nativeFps, frames: 0, det: 0),
        IconButton(
          icon: Icon(
            _nativeDebug ? Icons.bug_report : Icons.bug_report_outlined,
            color: Colors.white60, size: 20),
          onPressed: () {
            setState(() => _nativeDebug = !_nativeDebug);
            _nativeCtrl?.setDebug(showLandmarks: _nativeDebug);
          },
        ),
      ]),
    );
  }

  // ── Bottom tray ───────────────────────────────────────────────────────────
  Widget _buildBottomTray() {
    final cat          = _kCats[_activeCatIndex];
    final products     = _products[cat.label] ?? [];
    final loading      = _loading[cat.label] == true;
    final appliedProd  = _applied[cat.label];

    return Container(
      decoration: const BoxDecoration(
        color: _dark,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24), topRight: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Drag handle
        const SizedBox(height: 8),
        Container(width: 40, height: 4,
          decoration: BoxDecoration(
            color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 10),

        // ── Category tab strip ───────────────────────────────────────────
        SizedBox(
          height: 68,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _kCats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final c      = _kCats[i];
              final active = i == _activeCatIndex;
              final hasApplied = _applied[c.label] != null;
              return GestureDetector(
                onTap: () => setState(() { _activeCatIndex = i; _showShades = false; }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 66,
                  decoration: BoxDecoration(
                    color: active ? _maroon : Colors.white10,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(clipBehavior: Clip.none, children: [
                        Icon(c.icon, size: 22,
                          color: active ? Colors.white : Colors.white60),
                        if (hasApplied)
                          Positioned(top: -3, right: -3,
                            child: Container(width: 8, height: 8,
                              decoration: const BoxDecoration(
                                color: _gold, shape: BoxShape.circle))),
                      ]),
                      const SizedBox(height: 4),
                      Text(c.label,
                        style: TextStyle(fontSize: 10,
                          color: active ? Colors.white : Colors.white54,
                          fontWeight: FontWeight.w600)),
                    ]),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),

        // ── Products horizontal list ─────────────────────────────────────────
        SizedBox(
          height: 110,
          child: loading
              ? const Center(child: CircularProgressIndicator(color: _maroon))
              : products.isEmpty
                  ? const Center(child: Text('No products', style: TextStyle(color: Colors.white38, fontSize: 12)))
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: products.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) {
                        final p   = products[i];
                        final sel = appliedProd?.id == p.id;
                        final fav = _favIds.contains(p.id);
                        return _ProductTile(
                          product: p,
                          isSelected: sel,
                          isFavourite: fav,
                          onTap: () {
                            setState(() {
                              if (sel) { _applied.remove(cat.label); }
                              else     { _applied[cat.label] = p; _shadeIdx[cat.label] = 0; }
                            });
                            _applyEffect();
                          },
                          onFavourite: () => _toggleFav(p),
                          onAddToCart: () => _addToCart(p),
                        );
                      },
                    ),
        ),
        const SizedBox(height: 8),

        // ── SHADES | COMPARE action pills ────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            Expanded(child: _ActionPill(
              label: 'SHADES', icon: Icons.palette_outlined,
              active: _showShades,
              onTap: () {
                if (appliedProd == null) return;
                setState(() => _showShades = !_showShades);
              },
            )),
            const SizedBox(width: 12),
            Expanded(child: _ActionPill(
              label: 'COMPARE', icon: Icons.compare_arrows_rounded,
              active: _compareMode,
              onTap: () { setState(() => _compareMode = !_compareMode); _applyEffect(); },
            )),
          ]),
        ),
        const SizedBox(height: 4),

        // ── Inline shades sheet ──────────────────────────────────────────────
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          crossFadeState: _showShades && appliedProd != null
              ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: _ShadesSheet(
            product: appliedProd,
            selectedIdx: _shadeIdx[cat.label] ?? 0,
            intensity: _intensity,
            onShade: (i) { setState(() => _shadeIdx[cat.label] = i); _applyEffect(); },
            onIntensity: (v) { setState(() => _intensity = v); _applyEffect(); },
            hexToColor: _hex,
          ),
          secondChild: const SizedBox.shrink(),
        ),

        SizedBox(height: MediaQuery.of(context).padding.bottom + 4),
      ]),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ──────────────────────────────────────────────────────────────────────────────

class _ProductTile extends StatelessWidget {
  final Product product;
  final bool isSelected, isFavourite;
  final VoidCallback onTap, onFavourite, onAddToCart;
  const _ProductTile({
    required this.product, required this.isSelected,
    required this.isFavourite, required this.onTap,
    required this.onFavourite, required this.onAddToCart,
  });

  Color _hexC(String h) {
    var s = h.replaceAll('#', '');
    if (s.length == 6) s = 'FF$s';
    try { return Color(int.parse(s, radix: 16)); } catch (_) { return const Color(0xFFD4717A); }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 80,
        decoration: BoxDecoration(
          color: isSelected ? _maroon.withValues(alpha: 0.25) : Colors.white10,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? _maroon : Colors.transparent, width: 1.8),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // ♥ favourite
            Align(alignment: Alignment.topRight,
              child: GestureDetector(onTap: onFavourite,
                child: Padding(padding: const EdgeInsets.only(top: 4, right: 4),
                  child: Icon(
                    isFavourite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    size: 15,
                    color: isFavourite ? Colors.pink.shade300 : Colors.white30,
                  )))),
            // Product image
            Container(
              width: 46, height: 46,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8), color: Colors.white10),
              child: product.imagePath.startsWith('assets/')
                  ? ClipRRect(borderRadius: BorderRadius.circular(8),
                      child: FirebaseStorageImage(storagePath: product.imagePath, fit: BoxFit.contain))
                  : _shade(),
            ),
            // Name + cart
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: Column(children: [
                Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 9,
                      fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                GestureDetector(onTap: onAddToCart,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _maroon.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(6)),
                    child: const Text('+ Cart',
                      style: TextStyle(color: Colors.white, fontSize: 8,
                          fontWeight: FontWeight.w700)),
                  )),
              ]),
            ),
          ]),
      ),
    );
  }

  Widget _shade() => Center(child: Container(
    width: 28, height: 28,
    decoration: BoxDecoration(color: _hexC(product.colorHex), shape: BoxShape.circle),
  ));
}

// ── Shades sheet ──────────────────────────────────────────────────────────────
class _ShadesSheet extends StatelessWidget {
  final Product? product;
  final int selectedIdx;
  final double intensity;
  final ValueChanged<int> onShade;
  final ValueChanged<double> onIntensity;
  final Color Function(String) hexToColor;
  const _ShadesSheet({
    required this.product, required this.selectedIdx,
    required this.intensity, required this.onShade,
    required this.onIntensity, required this.hexToColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = product;
    if (p == null) return const SizedBox.shrink();
    final shades = p.shades;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (shades.isNotEmpty)
          Text(
            shades[selectedIdx.clamp(0, shades.length - 1)]['name'] ?? 'Shade',
            style: const TextStyle(color: Colors.white70, fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        if (shades.isNotEmpty)
          SizedBox(height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: shades.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final hex = shades[i]['hex'] ?? '#D4717A';
                final sel = i == selectedIdx;
                return GestureDetector(
                  onTap: () => onShade(i),
                  child: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: hexToColor(hex),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: sel ? Colors.white : Colors.white24,
                        width: sel ? 2.5 : 1),
                      boxShadow: sel ? [BoxShadow(
                        color: hexToColor(hex).withValues(alpha: 0.5),
                        blurRadius: 8)] : null,
                    ),
                    child: sel
                        ? const Icon(Icons.check, color: Colors.white, size: 13) : null,
                  ),
                );
              },
            )),
        const SizedBox(height: 6),
        // Intensity slider
        Row(children: [
          const Icon(Icons.brightness_low, color: Colors.white38, size: 16),
          Expanded(child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _gold,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              overlayColor: _gold.withValues(alpha: 0.2),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: intensity, min: 0.1, max: 1.0,
              onChanged: onIntensity,
            ),
          )),
          const Icon(Icons.brightness_high, color: Colors.white54, size: 16),
        ]),
      ]),
    );
  }
}

// ── Action pill ───────────────────────────────────────────────────────────────
class _ActionPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _ActionPill({required this.label, required this.icon,
      required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 40,
        decoration: BoxDecoration(
          color: active ? _maroon : Colors.white12,
          borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(
            color: Colors.white, fontSize: 13,
            fontWeight: FontWeight.w800, letterSpacing: 0.5)),
        ]),
      ),
    );
  }
}

// ── Compare pill ──────────────────────────────────────────────────────────────
class _ComparePill extends StatelessWidget {
  final String text;
  const _ComparePill(this.text);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: const TextStyle(
        color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}
