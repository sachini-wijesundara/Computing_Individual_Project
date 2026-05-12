import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/tflite_analysis_service.dart';
import '../services/gemini_chat_service.dart';
import '../models/hair_style.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _bg       = Color(0xFF111111);   // neutral dark (matches screenshot)
const _surface  = Color(0xFF1C1C1C);   // card / surface
const _tabDark  = Color(0xFF242424);   // inactive tab
const _red      = Color(0xFFC41E3A);   // brand red (active tab, buttons)
const _gold     = Color(0xFFD4A843);   // RECOMMENDED PRODUCTS / CARE TIPS headers
const _muted    = Color(0xFF888888);   // subtitle / label text

// ═════════════════════════════════════════════════════════════════════════════
class EnhancedAIAssistantScreen extends StatefulWidget {
  const EnhancedAIAssistantScreen({super.key});
  @override
  State<EnhancedAIAssistantScreen> createState() =>
      _EnhancedAIAssistantScreenState();
}

class _EnhancedAIAssistantScreenState
    extends State<EnhancedAIAssistantScreen> {
  final _tflite = TFLiteAnalysisService();
  final _gemini = GeminiChatService();
  final _picker = ImagePicker();

  int  _tab          = 0;   // 0=SKIN  1=HAIR
  bool _analyzing    = false;
  bool _tipsExpanded = false;

  Uint8List? _previewBytes;
  SkinToneResult? _skin;
  HairResult? _hair;

  // ── Pick image ─────────────────────────────────────────────────────────────
  Future<void> _selfie() async {
    final f = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (f != null) _analyze(f);
  }
  Future<void> _upload() async {
    final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (f != null) _analyze(f);
  }

  // ── Analyze ────────────────────────────────────────────────────────────────
  Future<void> _analyze(XFile file) async {
    final bytes = await file.readAsBytes();
    setState(() {
      _previewBytes = bytes;
      _analyzing = true;
      _skin = null;
      _hair = null;
    });
    try {
      await _tflite.initialize();
      final skin = await _tflite.analyzeSkin(file);
      final hair = await _tflite.analyzeHair(file);
      _gemini.setBeautyProfile(BeautyProfile(
        skinTone: skin.skinTone, undertone: skin.undertone,
        hairType: hair.hairType, hairColor: hair.hairColor,
        inferenceMode: '${skin.inferenceMode}/${hair.inferenceMode}',
      ));
      if (!mounted) return;
      setState(() { _skin = skin; _hair = hair; _analyzing = false; });
    } catch (e, st) {
      debugPrint('Enhanced AI analysis error: $e\n$st');
      if (!mounted) return;
      setState(() => _analyzing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Analysis could not finish. If hair styles are missing, try again or check your network.\n$e',
            style: const TextStyle(fontSize: 13),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hasResult = (_tab == 0 ? _skin : _hair) != null;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(child: Column(children: [
        // ── Header ──────────────────────────────────────────────────────
        _header(),
        const SizedBox(height: 16),
        // ── SKIN / HAIR tabs ─────────────────────────────────────────────
        _tabs(),
        const SizedBox(height: 16),
        // ── Scrollable body ──────────────────────────────────────────────
        Expanded(child: SingleChildScrollView(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                // ── Big photo area ────────────────────────
                _photoArea(),
                const SizedBox(height: 16),
                // ── Action buttons ──────────────────────────────
                _actionButtons(),
                const SizedBox(height: 16),
                // ── Result card or Tips ─────────────────────────
                if (hasResult)
                  _tab == 0 ? _skinCard() : _hairCard()
                else
                  _tips(),
              ]),
            ),
            const SizedBox(height: 24),
          ]),
        )),
      ])),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Header
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // AI badge — red square with icon
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: _red, borderRadius: BorderRadius.circular(6)),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 8),
          const Text('LA VOGUE VISTA',
            style: TextStyle(color: _red, fontSize: 12,
                fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: const Icon(Icons.close, color: Colors.white38, size: 20)),
        ]),
        const SizedBox(height: 8),
        const Text('BEAUTY ANALYSIS',
          style: TextStyle(color: Colors.white, fontSize: 28,
              fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        const SizedBox(height: 2),
        const Text('On-device AI powered by TFLite models',
          style: TextStyle(color: _muted, fontSize: 12)),
      ]),
    );
  }

  // Tabs
  Widget _tabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        _TabPill(label: 'SKIN',  icon: Icons.face_retouching_natural_outlined,
            active: _tab == 0, onTap: () {
              if (_tab != 0) {
                setState(() {
                  _tab = 0;
                  _previewBytes = null;
                  _skin = null;
                  _hair = null;
                  _analyzing = false;
                });
              }
            }),
        const SizedBox(width: 10),
        _TabPill(label: 'HAIR',  icon: Icons.self_improvement_outlined,
            active: _tab == 1, onTap: () {
              if (_tab != 1) {
                setState(() {
                  _tab = 1;
                  _previewBytes = null;
                  _skin = null;
                  _hair = null;
                  _analyzing = false;
                });
              }
            }),
      ]),
    );
  }

  // ── Photo area (landing) ───────────────────────────────────────────────────
  Widget _photoArea() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: double.infinity,
        height: 300,
        child: _previewBytes == null
            // ── Empty state ─────────────────────────────────────────────────
            ? Container(
                color: _surface,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24, width: 1.5),
                      borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.photo_camera_outlined,
                        color: Colors.white38, size: 32),
                  ),
                  const SizedBox(height: 16),
                  const Text('Take or upload a photo',
                    style: TextStyle(color: Colors.white, fontSize: 15,
                        fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  const Text(
                    'For best results, use good lighting\nand face the camera directly',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted, fontSize: 13, height: 1.5)),
                ]),
              )
            // ── Image preview ────────────────────────────────────────────────
            : Stack(fit: StackFit.expand, children: [
                Image.memory(_previewBytes!, fit: BoxFit.cover),

                // Analysing overlay
                if (_analyzing)
                  const ColoredBox(color: Color(0x8C000000),
                    child: Center(child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: _red, strokeWidth: 3),
                        SizedBox(height: 12),
                        Text('Analysing features…',
                          style: TextStyle(color: Colors.white, fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      ],
                    ))),

                // ── Reset/Refresh icon ── top right
                if (!_analyzing && _previewBytes != null)
                  Positioned(
                    top: 10, right: 10,
                    child: GestureDetector(
                      onTap: () => setState(() { _previewBytes = null; _skin = null; _hair = null; }),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24, width: 1.5),
                        ),
                        child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ),

              ]),
      ),
    );
  }


  // ─────────────────────────────────────────────────────────────────────────
  // Action buttons
  Widget _actionButtons() {
    return Row(children: [
      Expanded(child: _PillBtn(
        label: 'SELFIE MODE', icon: Icons.camera_alt_rounded,
        color: _red, onTap: _selfie)),
      const SizedBox(width: 10),
      Expanded(child: _PillBtn(
        label: 'UPLOAD PHOTO', icon: Icons.photo_library_outlined,
        color: _tabDark, onTap: _upload,
        border: Border.all(color: Colors.white24))),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SKIN result card
  Widget _skinCard() {
    final s = _skin!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Avatar + heading
      _resultHeading(
        icon: Icons.face_retouching_natural_outlined,
        val1: s.skinTone, val2: s.undertone,
        lbl1: 'Skin Tone', lbl2: 'Undertone',
        mode: s.inferenceMode, confidence: s.confidence,
      ),
      const SizedBox(height: 20),
      _sectionHeader('RECOMMENDED PRODUCTS'),
      const SizedBox(height: 8),
      ...s.makeupRecommendations.entries.map((e) => _productRow(e.key, e.value)),
    ]);
  }

  // HAIR result card
  Widget _hairCard() {
    final h = _hair!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _resultHeading(
        icon: Icons.self_improvement_outlined,
        val1: h.hairType, val2: h.hairColor,
        lbl1: 'Hair Type', lbl2: 'Hair Color',
        mode: h.inferenceMode, confidence: h.confidence,
      ),
      const SizedBox(height: 20),
      _sectionHeader('RECOMMENDED PRODUCTS'),
      const SizedBox(height: 8),
      ...h.productRecommendations.entries.map((e) => _productRow(e.key, e.value)),
      const SizedBox(height: 20),
      if (h.recommendedStyles.isNotEmpty) ...[
        _sectionHeader('RECOMMENDED HAIRSTYLES'),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: h.recommendedStyles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final name = h.recommendedStyles[i];
              final style = hairStyles.firstWhere(
                (s) => s.name.toLowerCase() == name.toLowerCase(),
                orElse: () => hairStyles.first,
              );
              return _styleMiniCard(style);
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
      _sectionHeader('CARE TIPS'),
      const SizedBox(height: 8),
      ...h.careTips.map((t) => _careTipRow(t)),
    ]);
  }

  Widget _styleMiniCard(HairStyle s) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: s.accent.withOpacity(.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: s.accent.withOpacity(.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: CustomPaint(
                    size: const Size(20, 18),
                    painter: HairIconPainter(shape: s.overlayShape, color: s.accent),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: s.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            s.bestFor,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Result heading widget
  Widget _resultHeading({
    required IconData icon,
    required String val1, required String val2,
    required String lbl1, required String lbl2,
    required String mode, required double confidence,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Circular icon avatar
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF3A2020),
              shape: BoxShape.circle),
            child: Icon(icon, color: _gold, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // "Wavy · Brown"
            RichText(text: TextSpan(
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                  color: Colors.white, letterSpacing: 0.3),
              children: [
                TextSpan(text: val1),
                const TextSpan(text: '  ·  ',
                  style: TextStyle(color: _muted, fontWeight: FontWeight.w300)),
                TextSpan(text: val2),
              ],
            )),
            const SizedBox(height: 4),
            Text('$lbl1   ·   $lbl2',
              style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 6),
            // Mode badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF2A1515),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12)),
              child: Text(_modeLabel(mode),
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ),
          ])),
        ]),
        const SizedBox(height: 14),
        // Confidence row
        Row(children: [
          const Text('Confidence',
            style: TextStyle(color: _muted, fontSize: 13)),
          const Spacer(),
          Text('${(confidence * 100).toStringAsFixed(1)}%',
            style: const TextStyle(color: _gold, fontSize: 13,
                fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: confidence,
            backgroundColor: const Color(0xFF2A1515),
            color: _red,
            minHeight: 5,
          ),
        ),
      ]),
    );
  }

  String _modeLabel(String m) {
    if (m.contains('server')) return 'Server Analysis';
    return 'Pixel Analysis';
  }

  // Section header
  Widget _sectionHeader(String title) {
    return Text(title,
      style: const TextStyle(color: _gold, fontSize: 11,
          fontWeight: FontWeight.w800, letterSpacing: 1.5));
  }

  // Product row — card style
  Widget _productRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _surface, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        SizedBox(width: 90,
          child: Text(label,
            style: const TextStyle(color: _muted, fontSize: 13))),
        Expanded(
          child: Text(value, textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white, fontSize: 13))),
      ]),
    );
  }

  // Care tip row — lightbulb icon
  Widget _careTipRow(String tip) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _surface, borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.lightbulb_outline, color: _gold, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(tip,
          style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4))),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tips collapsible
  Widget _tips() {
    const tips = [
      'Face the camera straight-on without sunglasses.',
      'Use natural daylight for the most accurate skin tone detection.',
      'Remove heavy makeup before skin analysis for best results.',
      'Ensure hair is visible from root for accurate hair type detection.',
    ];
    return GestureDetector(
      onTap: () => setState(() => _tipsExpanded = !_tipsExpanded),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF200A0A),
          borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.tips_and_updates_outlined, color: _red, size: 15),
            const SizedBox(width: 6),
            const Text('TIPS FOR BEST RESULTS',
              style: TextStyle(color: _red, fontSize: 11,
                  fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            const Spacer(),
            Icon(_tipsExpanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
              color: _red, size: 18),
          ]),
          if (_tipsExpanded) ...[
            const SizedBox(height: 8),
            ...tips.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('• ', style: TextStyle(color: _muted)),
                Expanded(child: Text(t,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.5))),
              ]),
            )),
          ],
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Tab pill
// ═════════════════════════════════════════════════════════════════════════════
class _TabPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _TabPill({required this.label, required this.icon,
      required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 48,
          decoration: BoxDecoration(
            color: active ? _red : _tabDark,
            borderRadius: BorderRadius.circular(10),
            border: active ? null : Border.all(color: Colors.white12)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 17,
                color: active ? Colors.white : const Color(0xFF9E7070)),
            const SizedBox(width: 7),
            Text(label, style: TextStyle(
              color: active ? Colors.white : const Color(0xFF9E7070),
              fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Pill button
// ═════════════════════════════════════════════════════════════════════════════
class _PillBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final Border? border;
  const _PillBtn({required this.label, required this.icon,
      required this.color, required this.onTap, this.border});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: border),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(
            color: Colors.white, fontSize: 13,
            fontWeight: FontWeight.w800, letterSpacing: 0.3)),
        ]),
      ),
    );
  }
}

// ── Stub classes to avoid breaking other imports ──────────────────────────────
class SkinToneAnalysis {
  final String skinTone, undertone, hairType, hairColor;
  final double confidence;
  final List<MakeupRecommendation> recommendations;
  SkinToneAnalysis({
    required this.skinTone, required this.undertone,
    required this.hairType, required this.hairColor,
    required this.confidence, required this.recommendations,
  });
}

class MakeupRecommendation {
  final String category, product, color, brand, price;
  final double confidence;
  MakeupRecommendation({
    required this.category, required this.product,
    required this.color, required this.brand,
    required this.price, required this.confidence,
  });
}
