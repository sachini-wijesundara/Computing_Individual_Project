// lib/screens/hair_color_tryon_screen.dart
//
// Hair Color Live Try-On Screen
//
// Live camera: MediaPipe ImageSegmenter (native) → hair mask → HSL tint on preview.

import 'package:flutter/material.dart';
import '../native_lip_renderer.dart';

// ─── Color palette ────────────────────────────────────────────────────────────
const _bg      = Color(0xFF111111);
const _surface = Color(0xFF1C1C1C);
const _red     = Color(0xFFC41E3A);
const _gold    = Color(0xFFD4A843);
const _muted   = Color(0xFF888888);

// ─── Hair color options ───────────────────────────────────────────────────────
class _HairCategory {
  final String name;
  final List<_HairShade> shades;
  const _HairCategory(this.name, this.shades);
}

class _HairShade {
  final String name;
  final Color color;
  final String hex;
  const _HairShade(this.name, this.color, this.hex);
}

// ─────────────────────────────────────────────────────────────────────────────
// Hair colour palette — researched from L'Oréal Feria, Garnier Nutrisse,
// Schwarzkopf LIVE, Revlon ColorSilk, Clairol Nice'n Easy & Wella Koleston.
// ─────────────────────────────────────────────────────────────────────────────
const _hairCategories = [

  // ── 1. Vibrant Reds ─────────────────────────────────────────────────────
  // L'Oréal Feria Power Reds, Schwarzkopf LIVE Real Red / Pillar Box Red,
  // Garnier True Red (Pomegranate), Revlon Vibrant Red / Passion Red
  _HairCategory('Vibrant Reds', [
    _HairShade('Fire Red',       Color(0xFFCC1515), '#CC1515'),
    _HairShade('Pillar Box',     Color(0xFFE02020), '#E02020'),
    _HairShade('True Red',       Color(0xFFD72020), '#D72020'),
    _HairShade('Scarlet',        Color(0xFFC41E3A), '#C41E3A'),
    _HairShade('Cherry Red',     Color(0xFF9B1C25), '#9B1C25'),
    _HairShade('Passion Red',    Color(0xFFB22222), '#B22222'),
    _HairShade('Vivid Crimson',  Color(0xFFA01030), '#A01030'),
  ]),

  // ── 2. Auburn & Spice ───────────────────────────────────────────────────
  // Garnier R1–R3 Intense Auburns, Clairol 5WR Warm Auburn,
  // Revlon Bright Auburn / Medium Auburn, L'Oréal R68 Rich Auburn True Red
  _HairCategory('Auburn & Spice', [
    _HairShade('Bright Auburn',  Color(0xFFB55030), '#B55030'),
    _HairShade('Auburn Spice',   Color(0xFF9B3015), '#9B3015'),
    _HairShade('Warm Auburn',    Color(0xFF8A3C22), '#8A3C22'),
    _HairShade('Rich Auburn',    Color(0xFF7A3028), '#7A3028'),
    _HairShade('Dark Auburn',    Color(0xFF6B2810), '#6B2810'),
    _HairShade('Cinnamon',       Color(0xFFA06030), '#A06030'),
    _HairShade('Auburn Brown',   Color(0xFF724030), '#724040'),
  ]),

  // ── 3. Copper Tones ─────────────────────────────────────────────────────
  // L'Oréal Feria C74 Power Copper, Schwarzkopf LIVE Mango Twist / Cayenne
  // Copper, Schwarzkopf Brilliance Boho Copper, Revlon Reddish Brown
  _HairCategory('Copper Tones', [
    _HairShade('Light Copper',   Color(0xFFCC7830), '#CC7830'),
    _HairShade('Mango Copper',   Color(0xFFD26838), '#D26838'),
    _HairShade('Spiced Copper',  Color(0xFFB86030), '#B86030'),
    _HairShade('Burnt Copper',   Color(0xFF9E5020), '#9E5020'),
    _HairShade('Bronze',         Color(0xFFCC8030), '#CC8030'),
    _HairShade('Caramel Copper', Color(0xFFD08840), '#D08840'),
  ]),

  // ── 4. Burgundy & Wine ──────────────────────────────────────────────────
  // L'Oréal Casting R48 Deep Burgundy, Revlon Dark Burgundy / Burgundy 48,
  // Schwarzkopf LIVE Cherry Cola Red, Garnier Sangria 56, Clairol Deep Wine
  _HairCategory('Burgundy & Wine', [
    _HairShade('Cherry Burg.',   Color(0xFF7A1830), '#7A1830'),
    _HairShade('Burgundy',       Color(0xFF6B2030), '#6B2030'),
    _HairShade('Deep Burgundy',  Color(0xFF4A0F1E), '#4A0F1E'),
    _HairShade('Wine Red',       Color(0xFF6B1428), '#6B1428'),
    _HairShade('Bordeaux',       Color(0xFF571022), '#571022'),
    _HairShade('Cherry Cola',    Color(0xFF5E2A30), '#5E2A30'),
  ]),

  // ── 5. Mahogany ─────────────────────────────────────────────────────────
  // Revlon Dark Mahogany Brown 32 / Medium Golden Mahogany (Garnier 535),
  // Schwarzkopf Brilliance, Clairol Nice'n Easy
  _HairCategory('Mahogany', [
    _HairShade('Red Mahogany',   Color(0xFF7A2820), '#7A2820'),
    _HairShade('Light Mahog.',   Color(0xFF7A3028), '#7A3028'),
    _HairShade('Mahogany',       Color(0xFF5E2820), '#5E2820'),
    _HairShade('Dark Mahog.',    Color(0xFF481815), '#481815'),
    _HairShade('Choc. Mahog.',   Color(0xFF5A2C28), '#5A2C28'),
  ]),

  // ── 6. Dark Browns ──────────────────────────────────────────────────────
  // Schwarzkopf LIVE Espresso Martini / Bitter Sweet Chocolate,
  // L'Oréal Casting Darkest Brown / Dark Chocolate Brown
  _HairCategory('Dark Browns', [
    _HairShade('Espresso',       Color(0xFF2A1008), '#2A1008'),
    _HairShade('Dark Chocolate', Color(0xFF3B1A08), '#3B1A08'),
    _HairShade('Dark Brown',     Color(0xFF4A2010), '#4A2010'),
    _HairShade('Bitter Choc.',   Color(0xFF3C2015), '#3C2015'),
    _HairShade('Brown Black',    Color(0xFF221408), '#221408'),
  ]),

  // ── 7. Medium Browns ────────────────────────────────────────────────────
  // Revlon Medium Brown 41 / Medium Auburn 42 / Medium Golden Brown 43,
  // Garnier 50 Truffle / 53 Chestnut, Clairol 5G Medium Golden Brown
  _HairCategory('Medium Browns', [
    _HairShade('Chestnut',       Color(0xFF6B3020), '#6B3020'),
    _HairShade('Medium Brown',   Color(0xFF7A4520), '#7A4520'),
    _HairShade('Rich Brown',     Color(0xFF5E2C10), '#5E2C10'),
    _HairShade('Cinnamon Brown', Color(0xFF7D3D18), '#7D3D18'),
    _HairShade('Warm Brown',     Color(0xFF8A4828), '#8A4828'),
    _HairShade('Milk Chocolate', Color(0xFF7A3E1E), '#7A3E1E'),
  ]),

  // ── 8. Caramel & Light Brown ────────────────────────────────────────────
  // Revlon Light Brown 51 / Light Golden Brown 54 / Lightest Golden Brown 57,
  // Garnier Chocolate Caramel, L'Oréal Caramel Toffee, Schwarzkopf L61 Bronde
  _HairCategory('Caramel & Honey', [
    _HairShade('Golden Brown',   Color(0xFFA86030), '#A86030'),
    _HairShade('Caramel',        Color(0xFFB07040), '#B07040'),
    _HairShade('Light Brown',    Color(0xFFB87040), '#B87040'),
    _HairShade('Honey Brown',    Color(0xFFC07838), '#C07838'),
    _HairShade('Toffee',         Color(0xFFC08040), '#C08040'),
    _HairShade('Warm Caramel',   Color(0xFFC88840), '#C88840'),
  ]),

  // ── 9. Blonde ───────────────────────────────────────────────────────────
  // Revlon Golden Blonde 71 / Warm Golden Blonde 75, L'Oréal Feria Golden,
  // Garnier, Clairol, Schwarzkopf Frosty Blonde / Nude Bronde
  _HairCategory('Blonde', [
    _HairShade('Strawberry',     Color(0xFFCC8850), '#CC8850'),
    _HairShade('Dark Blonde',    Color(0xFFB89050), '#B89050'),
    _HairShade('Golden Blonde',  Color(0xFFD4A840), '#D4A840'),
    _HairShade('Honey Blonde',   Color(0xFFC89050), '#C89050'),
    _HairShade('Sandy Blonde',   Color(0xFFC8A060), '#C8A060'),
    _HairShade('Warm Blonde',    Color(0xFFE0B870), '#E0B870'),
    _HairShade('Ash Blonde',     Color(0xFFB1A28A), '#B1A28A'),
  ]),

  // ── 10. Platinum & Icy ──────────────────────────────────────────────────
  // L'Oréal Feria Ultra Pearl / Ultra Cool Blonde,
  // Schwarzkopf LIVE Platinum Blonde B15 / Icy White, Revlon Ultra Light
  _HairCategory('Platinum & Icy', [
    _HairShade('Light Blonde',   Color(0xFFDECB80), '#DECB80'),
    _HairShade('Very Lt. Blonde',Color(0xFFE8D090), '#E8D090'),
    _HairShade('Platinum',       Color(0xFFEDE0B5), '#EDE0B5'),
    _HairShade('Cool Platinum',  Color(0xFFE5DCBA), '#E5DCBA'),
    _HairShade('Icy Blonde',     Color(0xFFF0EBE1), '#F0EBE1'),
    _HairShade('Pearl Blonde',   Color(0xFFF4F0E8), '#F4F0E8'),
  ]),

  // ── 11. Black ───────────────────────────────────────────────────────────
  // L'Oréal Casting Blue Black / Liquorice, Revlon Soft Black 11,
  // Schwarzkopf Deep Black 099, Clairol Brown Black
  _HairCategory('Black', [
    _HairShade('Soft Black',     Color(0xFF2C2C2C), '#2C2C2C'),
    _HairShade('Natural Black',  Color(0xFF1A0A00), '#1A0A00'),
    _HairShade('Jet Black',      Color(0xFF0F0F0F), '#0F0F0F'),
    _HairShade('Blue Black',     Color(0xFF0A0820), '#0A0820'),
    _HairShade('Plum Black',     Color(0xFF1A0820), '#1A0820'),
  ]),

  // ── 12. Fashion & Fantasy ───────────────────────────────────────────────
  // L'Oréal Feria Midnight Bold / Metropical, Schwarzkopf LIVE Ultra Brights,
  // Wella Color Fresh Create vivids, Schwarzkopf Urban Metallics
  _HairCategory('Fashion Colors', [
    _HairShade('Rose Gold',      Color(0xFFD48078), '#D48078'),
    _HairShade('Fuchsia',        Color(0xFFCC1888), '#CC1888'),
    _HairShade('Red Violet',     Color(0xFF9A1060), '#9A1060'),
    _HairShade('Purple',         Color(0xFF6A1090), '#6A1090'),
    _HairShade('Violet',         Color(0xFF501878), '#501878'),
    _HairShade('Lavender',       Color(0xFF9080C0), '#9080C0'),
    _HairShade('Indigo',         Color(0xFF201878), '#201878'),
    _HairShade('Cobalt Blue',    Color(0xFF0047AB), '#0047AB'),
    _HairShade('Teal',           Color(0xFF208080), '#208080'),
    _HairShade('Silver',         Color(0xFF909090), '#909090'),
  ]),
];

// ═════════════════════════════════════════════════════════════════════════════
class HairColorTryOnScreen extends StatefulWidget {
  final String? productName;
  final String? productHex;
  const HairColorTryOnScreen({super.key, this.productName, this.productHex});

  @override
  State<HairColorTryOnScreen> createState() => _HairColorTryOnState();
}

class _HairColorTryOnState extends State<HairColorTryOnScreen> {
  NativeLipRendererController? _nativeController;

  late _HairCategory _selectedCategory;
  late _HairShade _selected;

  double _intensity = 0.4;

  @override
  void initState() {
    super.initState();
    _selectedCategory = _hairCategories.first;
    _selected = _selectedCategory.shades.first;

    if (widget.productHex != null) {
      for (var cat in _hairCategories) {
        final match = cat.shades.where(
          (s) => s.hex.toLowerCase() == widget.productHex!.toLowerCase()).toList();
        if (match.isNotEmpty) {
          _selectedCategory = cat;
          _selected = match.first;
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _nativeController?.dispose();
    super.dispose();
  }

  void _onViewCreated(NativeLipRendererController controller) {
    _nativeController = controller;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await controller.setEffect(
          shade: _selected.color,
          intensity: _intensity,
          category: 'cmd_haircolor',
        );
      } catch (e, st) {
        debugPrint('Hair try-on: setEffect failed: $e\n$st');
      }
      if (!mounted) return;
      try {
        await controller.start();
      } catch (e, st) {
        debugPrint('Hair try-on: native camera start failed: $e\n$st');
      }
    });
  }

  void _updateHairEffect() {
    if (_nativeController != null) {
      _nativeController!.setEffect(
        shade: _selected.color,
        intensity: _intensity,
        category: 'cmd_haircolor',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
        Positioned.fill(child: _buildViewport()),

        SafeArea(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            _iconBtn(Icons.arrow_back_ios_new_rounded, () => Navigator.pop(context)),
            const Spacer(),
            Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('COLOUR MATCH',
                  style: TextStyle(color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w900, letterSpacing: 1)),
              Text(_selected.name,
                  style: const TextStyle(color: _gold, fontSize: 11)),
            ]),
            const Spacer(),
            const SizedBox(width: 40),
          ]),
        )),

        Positioned(
          top: 80, right: 16,
          child: Column(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _selected.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8)],
              ),
            ),
            const SizedBox(height: 4),
            Text(_selected.name,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 9,
                    fontWeight: FontWeight.w600)),
          ]),
        ),

        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.58,
                maxWidth: MediaQuery.sizeOf(context).width,
              ),
              child: Material(
                color: _bg,
                elevation: 8,
                shadowColor: Colors.black,
                child: SingleChildScrollView(
                  child: _buildBottomPanel(),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildViewport() {
    return NativeLipRendererView(onViewCreated: _onViewCreated);
  }

  Widget _buildBottomPanel() {
    return Container(
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Text('INTENSITY', style: TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Expanded(child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _red,
                  inactiveTrackColor: Colors.white10,
                  thumbColor: Colors.white,
                  overlayShape: SliderComponentShape.noOverlay,
                  trackHeight: 3,
                ),
                child: Slider(
                  value: _intensity,
                  min: 0.1, max: 0.85,
                  onChanged: (v) {
                    setState(() => _intensity = v);
                    _updateHairEffect();
                  },
                ),
              )),
              SizedBox(
                width: 32,
                child: Text('${(_intensity * 100).toInt()}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: _gold, fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          const Text('SELECT CATEGORY',
              style: TextStyle(color: _gold, fontSize: 9,
                  fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _hairCategories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final cat = _hairCategories[i];
                final isSelected = _selectedCategory == cat;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedCategory = cat;
                    _selected = cat.shades.first;
                    _updateHairEffect();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? _red : _surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? _red : Colors.white12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      cat.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: isSelected ? Colors.white : Colors.white54,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          const Text('SELECT SHADE',
              style: TextStyle(color: _gold, fontSize: 9,
                  fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _selectedCategory.shades.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (_, i) {
                final shade = _selectedCategory.shades[i];
                final isSelected = _selected == shade;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selected = shade);
                    _updateHairEffect();
                  },
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: isSelected ? 44 : 38,
                      height: isSelected ? 44 : 38,
                      decoration: BoxDecoration(
                        color: shade.color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.white24,
                          width: isSelected ? 2.5 : 1),
                        boxShadow: isSelected
                            ? [BoxShadow(color: shade.color.withValues(alpha: 0.4), blurRadius: 10)]
                            : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(shade.name.split(' ').last,
                        style: TextStyle(fontSize: 10,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : Colors.white54)),
                  ]),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
