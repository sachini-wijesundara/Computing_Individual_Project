import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/hair_style.dart';
import '../services/openrouter_hair_analysis_service.dart';

// ─── La Vogue Vista theme (matches MaterialApp + dashboard) ─────────────────
const _roseTop = Color(0xFFF5E6E8);
const _roseBot = Color(0xFFEDD6DA);
const _primary = Color(0xFF8B0000);
const _secondary = Color(0xFFB8860B);
const _goldHighlight = Color(0xFFDCB568);
const _ink = Color(0xFF1F1F1F);
const _muted = Color(0xFF6B5A5E);
const _card = Colors.white;
const _hairIndigo = Color(0xFF3949AB);
const _hairIndigoDeep = Color(0xFF1A237E);

// ═════════════════════════════════════════════════════════════════════════════
class HairStyleMatcherScreen extends StatefulWidget {
  const HairStyleMatcherScreen({super.key});
  @override
  State<HairStyleMatcherScreen> createState() => _HairStyleMatcherState();
}

class _AIStyleRec {
  final String style;
  final String reason;
  const _AIStyleRec({required this.style, required this.reason});
}

class _HairStyleMatcherState extends State<HairStyleMatcherScreen> {
  final _picker = ImagePicker();
  final _openRouter = OpenRouterHairAnalysisService();

  File? _image;
  bool _analyzing = false;

  String? _faceShape;
  String? _hairType;
  String? _hairLength;
  List<_AIStyleRec> _recommendations = [];
  String? _analysisNote;

  void _clearAnalysis() {
    _faceShape = null;
    _hairType = null;
    _hairLength = null;
    _recommendations = [];
    _analysisNote = null;
  }

  Future<void> _analyzeWithOpenRouter() async {
    if (_image == null) return;
    setState(() {
      _analyzing = true;
      _clearAnalysis();
    });
    try {
      final bytes = await _image!.readAsBytes();
      final names = hairStyles.map((s) => s.name).join(', ');
      final result = await _openRouter.analyzeHairPhoto(
        jpegBytes: bytes,
        catalogStyleNames: names,
      );

      if (!mounted) return;

      final recs = result.recommendations
          .map((r) => _AIStyleRec(style: r.style, reason: r.reason))
          .where((r) => r.style.isNotEmpty)
          .toList();

      final hasTraits = result.faceShape != null ||
          result.hairType != null ||
          result.hairLength != null;
      final hasPayload = hasTraits || recs.isNotEmpty;

      if (!hasPayload && result.errorMessage != null) {
        setState(() => _analysisNote = result.errorMessage);
        return;
      }

      setState(() {
        _faceShape = result.faceShape;
        _hairType = result.hairType;
        _hairLength = result.hairLength;
        _recommendations = recs;
        _analysisNote = result.errorMessage ??
            (recs.isEmpty && hasTraits
                ? 'No style recommendations returned. Try again.'
                : null);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _analysisNote = 'Something went wrong: $e');
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  HairStyle? _catalogStyleForName(String name) {
    final n = name.toLowerCase().trim();
    for (final s in hairStyles) {
      if (s.name.toLowerCase() == n) return s;
    }
    for (final s in hairStyles) {
      if (n.contains(s.name.toLowerCase()) ||
          s.name.toLowerCase().contains(n)) {
        return s;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _openRouter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _roseTop,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.auto_awesome, size: 14, color: _goldHighlight),
                ),
                const SizedBox(width: 8),
                const Text(
                  'STYLE MATCH',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'AI · Vision · La Vogue Vista',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _secondary,
                  _goldHighlight,
                  _secondary,
                ],
              ),
            ),
          ),
        ),
      ),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_roseTop, _roseBot],
          ),
        ),
        child: _buildAIMatchTab(),
      ),
    );
  }

  Widget _buildAIMatchTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _hairIndigoDeep.withValues(alpha: 0.9),
                  _hairIndigo.withValues(alpha: 0.85),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _hairIndigo.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Text('💇', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Match your look',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Same flow as your dashboard Style Match chip',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Upload your photo',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Clear face and hair visible — we read face shape and suggest catalogue styles.',
            style: TextStyle(color: _muted, fontSize: 13, height: 1.35),
          ),
          if (OpenRouterHairAnalysisService.apiKey.isEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _secondary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _secondary.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.key_rounded, color: _secondary.withValues(alpha: 0.9), size: 22),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Add OPENROUTER_API_KEY to `.env` (see `.env.example`) or use '
                      '--dart-define=OPENROUTER_API_KEY=sk-or-v1-...',
                      style: TextStyle(color: _ink, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                final f = await _picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 85,
                );
                if (f != null) {
                  setState(() {
                    _image = File(f.path);
                    _clearAnalysis();
                  });
                }
              },
              borderRadius: BorderRadius.circular(20),
              child: Ink(
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _primary.withValues(alpha: 0.12),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _primary.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Container(
                  width: double.infinity,
                  height: 240,
                  alignment: Alignment.center,
                  child: _image != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Positioned.fill(
                                child: Image.file(_image!, fit: BoxFit.cover),
                              ),
                              Positioned(
                                right: 10,
                                bottom: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.edit_outlined,
                                          color: Colors.white, size: 14),
                                      SizedBox(width: 4),
                                      Text(
                                        'Change',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _primary.withValues(alpha: 0.08),
                              ),
                              child: Icon(
                                Icons.add_photo_alternate_outlined,
                                color: _primary.withValues(alpha: 0.85),
                                size: 40,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Tap to choose from gallery',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                'JPG, PNG, or HEIC — well-lit photos work best',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              onPressed: _image == null || _analyzing ? null : _analyzeWithOpenRouter,
              style: FilledButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _muted.withValues(alpha: 0.25),
                disabledForegroundColor: _muted,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              icon: _analyzing
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    )
                  : const Icon(Icons.auto_awesome, size: 20),
              label: Text(_analyzing ? 'Analysing…' : 'Find my style with AI'),
            ),
          ),
          if (_analysisNote != null) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: _primary.withValues(alpha: 0.85), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _analysisNote!,
                      style: TextStyle(
                        color: _ink.withValues(alpha: 0.9),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_faceShape != null || _hairType != null || _hairLength != null) ...[
            const SizedBox(height: 24),
            _sectionTitle('Your profile'),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _goldHighlight.withValues(alpha: 0.35)),
                boxShadow: [
                  BoxShadow(
                    color: _primary.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _secondary.withValues(alpha: 0.2),
                              _goldHighlight.withValues(alpha: 0.15),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.auto_awesome,
                            color: _secondary, size: 18),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'AI style read',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Divider(height: 1, color: _roseBot.withValues(alpha: 0.8)),
                  ),
                  if (_faceShape != null)
                    _resultRow(Icons.face_rounded, 'Face shape', _faceShape!),
                  if (_hairType != null)
                    _resultRow(Icons.waves_rounded, 'Hair type', _hairType!),
                  if (_hairLength != null)
                    _resultRow(
                        Icons.straighten_rounded, 'Hair length', _hairLength!),
                ],
              ),
            ),
          ],
          if (_recommendations.isNotEmpty) ...[
            const SizedBox(height: 24),
            _sectionTitle('Top picks for you'),
            const SizedBox(height: 12),
            ..._recommendations.map((r) {
              final cat = _catalogStyleForName(r.style);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AIResultStyleTile(
                  style: cat,
                  fallbackName: r.style,
                  aiReason: r.reason.isNotEmpty ? r.reason : null,
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: _secondary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: _muted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _resultRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: _primary.withValues(alpha: 0.9)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 16,
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
}

// ─── AI result style tile (catalog match + optional AI reason) ───────────────
class _AIResultStyleTile extends StatelessWidget {
  final HairStyle? style;
  final String fallbackName;
  final String? aiReason;

  const _AIResultStyleTile({
    required this.style,
    required this.fallbackName,
    this.aiReason,
  });

  @override
  Widget build(BuildContext context) {
    final s = style;
    final name = s?.name ?? fallbackName;
    final accent = s?.accent ?? _primary;
    final shape = s?.overlayShape ?? 'long';
    final bestFor = s?.bestFor ?? 'Suggested by AI';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.15),
                  accent.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: CustomPaint(
                size: const Size(28, 24),
                painter: HairIconPainter(shape: shape, color: accent),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  bestFor,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
                if (aiReason != null && aiReason!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _roseTop,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _primary.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Text(
                      aiReason!,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
