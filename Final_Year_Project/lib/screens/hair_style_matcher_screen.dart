// lib/screens/hair_style_matcher_screen.dart
//
// Hair Style Matcher — browse styles, try uploaded look, AI recommendations.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:convert';

const _bg      = Color(0xFF111111);
const _surface = Color(0xFF1C1C1C);
const _card    = Color(0xFF242424);
const _red     = Color(0xFFC41E3A);
const _gold    = Color(0xFFD4A843);

// ─── Hair style catalogue ─────────────────────────────────────────────────────
class _Style {
  final String id, name, description, bestFor, emoji;
  final Color accent;
  final List<String> tags;
  const _Style({required this.id, required this.name, required this.description,
      required this.bestFor, required this.emoji, required this.accent,
      required this.tags});
}

const _styles = [
  _Style(id: 'blunt_bob', name: 'Blunt Bob', emoji: '✂️',
    description: 'Clean, straight cut at the jaw. Timeless and bold.',
    bestFor: 'Oval, Square, Heart faces',
    accent: Color(0xFFC41E3A), tags: ['Short', 'Classic', 'Low Maintenance']),
  _Style(id: 'beachy_waves', name: 'Beachy Waves', emoji: '🌊',
    description: 'Effortless textured waves for a relaxed, sun-kissed look.',
    bestFor: 'All face shapes',
    accent: Color(0xFF4A90D9), tags: ['Medium', 'Casual', 'Volume']),
  _Style(id: 'curtain_bangs', name: 'Curtain Bangs', emoji: '🪶',
    description: 'Parted fringe framing the face. Vintage chic meets modern.',
    bestFor: 'Oval, Square faces',
    accent: Color(0xFF9B59B6), tags: ['Bangs', 'Trendy', 'Face-Framing']),
  _Style(id: 'layer_lob', name: 'Layered Lob', emoji: '🌿',
    description: 'Long bob with movement-adding layers for effortless texture.',
    bestFor: 'Round, Heart faces',
    accent: Color(0xFF27AE60), tags: ['Medium', 'Volume', 'Natural']),
  _Style(id: 'sleek_straight', name: 'Sleek Straight', emoji: '💎',
    description: 'Ultra-polished, straight strands for a powerful statement.',
    bestFor: 'Oval, Oblong faces',
    accent: Color(0xFF2C3E50), tags: ['Polished', 'Formal', 'Low Frizz']),
  _Style(id: 'big_curls', name: 'Big Voluminous Curls', emoji: '🌀',
    description: 'Bouncy, defined curls with maximum volume and drama.',
    bestFor: 'Oval, Long faces',
    accent: Color(0xFFE67E22), tags: ['Curly', 'Volume', 'Glam']),
  _Style(id: 'braid_crown', name: 'Braided Crown', emoji: '👑',
    description: 'Halo braid for an ethereal, bohemian goddess look.',
    bestFor: 'Oval, Heart, Square faces',
    accent: Color(0xFFD4A843), tags: ['Updo', 'Bridal', 'Bohemian']),
  _Style(id: 'wolf_cut', name: 'Wolf Cut', emoji: '🐺',
    description: 'Shaggy layers blending 70s rocker vibes with modern texture.',
    bestFor: 'Oval, Square faces',
    accent: Color(0xFF6C3483), tags: ['Edgy', 'Trendy', 'Layers']),
  _Style(id: 'slick_bun', name: 'Slick Bun', emoji: '🎀',
    description: 'Polished high bun for a clean, editorial look.',
    bestFor: 'All face shapes',
    accent: Color(0xFFC0392B), tags: ['Updo', 'Sleek', 'Professional']),
  _Style(id: 'textured_pixie', name: 'Textured Pixie', emoji: '⚡',
    description: 'Bold short cut with tousled layers for a daring edge.',
    bestFor: 'Oval, Heart faces',
    accent: Color(0xFF16A085), tags: ['Short', 'Bold', 'Edgy']),
];

// ═════════════════════════════════════════════════════════════════════════════
class HairStyleMatcherScreen extends StatefulWidget {
  const HairStyleMatcherScreen({super.key});
  @override
  State<HairStyleMatcherScreen> createState() => _HairStyleMatcherState();
}

class _HairStyleMatcherState extends State<HairStyleMatcherScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _picker = ImagePicker();
  File? _image;
  String _aiResult = '';
  bool _analyzing = false;
  String _filterTag = 'All';
  _Style? _selectedStyle;

  static const _allTags = ['All', 'Short', 'Medium', 'Curly', 'Updo',
      'Trendy', 'Classic', 'Bold', 'Casual'];

  List<_Style> get _filteredStyles => _filterTag == 'All'
      ? _styles
      : _styles.where((s) => s.tags.contains(_filterTag)).toList();

  Future<void> _analyzeWithGemini() async {
    if (_image == null) return;
    setState(() { _analyzing = true; _aiResult = ''; });
    try {
      final bytes = await _image!.readAsBytes();
      final model = GenerativeModel(
        model: 'gemini-2.5-flash', apiKey: 'AIzaSyDTBPPWWZWQjGgf7WZhr8hkdGon1CcmwBg',
        generationConfig: GenerationConfig(temperature: 0.4, maxOutputTokens: 500),
      );
      final prompt = '''
Analyze this photo and recommend the 3 best hair styles from this list: 
${_styles.map((s) => s.name).join(', ')}.

Also detect:
- Face shape 
- Current hair type (straight/wavy/curly/coily)
- Current hair length (short/medium/long)

Reply in valid JSON:
{"face_shape":"Oval","hair_type":"Wavy","hair_length":"Medium","recommendations":[{"style":"Beachy Waves","reason":"Enhances your natural texture"},{"style":"Curtain Bangs","reason":"Frames your oval face beautifully"},{"style":"Layered Lob","reason":"Perfect for your medium length"}]}
''';
      final content = [Content.multi([
        TextPart(prompt),
        DataPart('image/jpeg', bytes),
      ])];
      final resp = await model.generateContent(content)
          .timeout(const Duration(seconds: 25));
      final text = resp.text ?? '';
      final jsonMatch = RegExp(r'\{[\s\S]+\}').firstMatch(text);
      if (jsonMatch != null) {
        final data = json.decode(jsonMatch.group(0)!) as Map<String, dynamic>;
        final recs = (data['recommendations'] as List?)
            ?.map((r) => '• **${r['style']}** — ${r['reason']}')
            .join('\n') ?? '';
        setState(() {
          _aiResult = '''**Face Shape:** ${data['face_shape'] ?? 'N/A'}
**Hair Type:** ${data['hair_type'] ?? 'N/A'}  
**Hair Length:** ${data['hair_length'] ?? 'N/A'}

**Recommended Styles:**
$recs''';
        });
      } else {
        setState(() => _aiResult = text);
      }
    } catch (e) {
      setState(() => _aiResult = '❌ Could not analyse. Please check your connection and try again.');
    } finally {
      setState(() => _analyzing = false);
    }
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context)),
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('STYLE MATCH', style: TextStyle(color: Colors.white,
              fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          Text('Find your perfect hair style', style: TextStyle(
              color: Color(0xFF888888), fontSize: 11)),
        ]),
        bottom: TabBar(
          controller: _tabs,
          labelColor: _red, unselectedLabelColor: Colors.white38,
          indicatorColor: _red, dividerColor: Colors.white12,
          tabs: const [
            Tab(text: 'BROWSE STYLES'),
            Tab(text: 'AI MATCH'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _buildBrowseTab(),
        _buildAIMatchTab(),
      ]),
    );
  }

  Widget _buildBrowseTab() {
    return Column(children: [
      // Filter chips
      SizedBox(height: 52, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _allTags.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final tag = _allTags[i];
          final active = _filterTag == tag;
          return GestureDetector(
            onTap: () => setState(() { _filterTag = tag; _selectedStyle = null; }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: active ? _red : _card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: active ? _red : Colors.white12),
              ),
              child: Text(tag, style: TextStyle(
                color: active ? Colors.white : Colors.white60,
                fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          );
        },
      )),
      // Style grid
      Expanded(child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, mainAxisExtent: 200, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemCount: _filteredStyles.length,
        itemBuilder: (_, i) => _styleCard(_filteredStyles[i]),
      )),
    ]);
  }

  Widget _styleCard(_Style s) {
    final isSelected = _selectedStyle?.id == s.id;
    return GestureDetector(
      onTap: () => setState(() => _selectedStyle = isSelected ? null : s),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected ? s.accent.withOpacity(0.15) : _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? s.accent : Colors.white12, width: 1.5),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 8),
          Text(s.name, style: TextStyle(
            color: isSelected ? s.accent : Colors.white,
            fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(s.description, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.4)),
          const Spacer(),
          Row(children: [
            Icon(Icons.face_rounded, size: 12, color: _gold),
            const SizedBox(width: 4),
            Flexible(child: Text(s.bestFor,
                style: const TextStyle(color: _gold, fontSize: 10),
                overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 4, children: s.tags.take(2).map((t) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: s.accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8)),
            child: Text(t, style: TextStyle(color: s.accent, fontSize: 9, fontWeight: FontWeight.w700)),
          )).toList()),
        ]),
      ),
    );
  }

  Widget _buildAIMatchTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        // Upload area
        GestureDetector(
          onTap: () async {
            final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
            if (f != null) setState(() { _image = File(f.path); _aiResult = ''; });
          },
          child: Container(
            width: double.infinity, height: 220,
            decoration: BoxDecoration(
              color: _surface, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _red.withOpacity(0.4), width: 1.5)),
            child: _image != null
                ? ClipRRect(borderRadius: BorderRadius.circular(15),
                    child: Image.file(_image!, fit: BoxFit.cover))
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_photo_alternate_outlined,
                        color: _red.withOpacity(0.7), size: 48),
                    const SizedBox(height: 12),
                    const Text('Upload your photo', style: TextStyle(
                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text('AI will recommend the best styles for your face',
                        style: TextStyle(color: Color(0xFF888888), fontSize: 12),
                        textAlign: TextAlign.center),
                  ]),
          ),
        ),
        const SizedBox(height: 16),
        // Analyse button
        SizedBox(width: double.infinity, height: 52,
          child: ElevatedButton.icon(
            onPressed: _image == null || _analyzing ? null : _analyzeWithGemini,
            icon: _analyzing
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.auto_awesome, size: 18),
            label: Text(_analyzing ? 'Analysing…' : 'Find My Style with AI'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _red, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ),
        ),
        // Result
        if (_aiResult.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _surface, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _gold.withOpacity(0.25))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.auto_awesome, color: _gold, size: 16),
                SizedBox(width: 6),
                Text('AI Style Analysis', style: TextStyle(
                    color: _gold, fontSize: 13, fontWeight: FontWeight.w800)),
              ]),
              const Divider(color: Colors.white12, height: 20),
              Text(_aiResult, style: const TextStyle(
                  color: Colors.white, fontSize: 13, height: 1.6)),
            ]),
          ),
        ],
      ]),
    );
  }
}
