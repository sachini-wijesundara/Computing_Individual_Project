// lib/screens/hair_color_tryon_screen.dart
//
// Hair Color Live Try-On Screen
// Uses camera feed with hair-region color overlay using blend modes.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';

// ─── Color palette ────────────────────────────────────────────────────────────
const _bg      = Color(0xFF111111);
const _surface = Color(0xFF1C1C1C);
const _red     = Color(0xFFC41E3A);
const _gold    = Color(0xFFD4A843);

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

// Shades based on the user screenshot:
// Brown/Brunette, Blonde, Red, Black, Bold, Platinum Blonde, Gray Hair Coverage
const _hairCategories = [
  _HairCategory('Brown/Brunette', [
    _HairShade('Dark Brown',     Color(0xFF3B1F0A), '#3B1F0A'),
    _HairShade('Medium Brown',   Color(0xFF7A4520), '#7A4520'),
    _HairShade('Chestnut',       Color(0xFF6B3020), '#6B3020'),
    _HairShade('Warm Brown',     Color(0xFF9A5530), '#9A5530'),
    _HairShade('Caramel',        Color(0xFFB07040), '#B07040'),
  ]),
  _HairCategory('Blonde', [
    _HairShade('Honey Blonde',   Color(0xFFC89050), '#C89050'),
    _HairShade('Golden Blonde',  Color(0xFFD4A840), '#D4A840'),
    _HairShade('Sandy Blonde',   Color(0xFFC8A060), '#C8A060'),
    _HairShade('Ash Blonde',     Color(0xFFB1A28A), '#B1A28A'),
  ]),
  _HairCategory('Platinum Blonde', [
    _HairShade('Platinum',       Color(0xFFE8D8B8), '#E8D8B8'),
    _HairShade('Icy Blonde',     Color(0xFFF0EBE1), '#F0EBE1'),
    _HairShade('Pearl Blonde',   Color(0xFFE2DACC), '#E2DACC'),
  ]),
  _HairCategory('Red', [
    _HairShade('Auburn',         Color(0xFF8B3010), '#8B3010'),
    _HairShade('Burgundy',       Color(0xFF6A1020), '#6A1020'),
    _HairShade('Vibrant Red',    Color(0xFFC01020), '#C01020'),
    _HairShade('Copper',         Color(0xFFB86030), '#B86030'),
    _HairShade('Cherry',         Color(0xFF87161F), '#87161F'),
  ]),
  _HairCategory('Black', [
    _HairShade('Natural Black',  Color(0xFF1A0A00), '#1A0A00'),
    _HairShade('Jet Black',      Color(0xFF0F0F0F), '#0F0F0F'),
    _HairShade('Blue Black',     Color(0xFF0A0820), '#0A0820'),
    _HairShade('Soft Black',     Color(0xFF2C2C2C), '#2C2C2C'),
  ]),
  _HairCategory('Bold', [
    _HairShade('Rose Gold',      Color(0xFFD0807A), '#D0807A'),
    _HairShade('Purple Tint',    Color(0xFF402060), '#402060'),
    _HairShade('Magenta',        Color(0xFFB01080), '#B01080'),
    _HairShade('Teal',           Color(0xFF208080), '#208080'),
    _HairShade('Silver',         Color(0xFF9090A0), '#9090A0'),
  ]),
  _HairCategory('Gray Hair Coverage', [
    _HairShade('Ash Brown',      Color(0xFF6A6858), '#6A6858'),
    _HairShade('Mushroom',       Color(0xFF8F8881), '#8F8881'),
    _HairShade('Salt & Pepper',  Color(0xFF787878), '#787878'),
    _HairShade('Dark Blonde Cvr',Color(0xFF9C8868), '#9C8868'),
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
  CameraController? _camera;
  List<CameraDescription> _cameras = [];
  bool _cameraReady = false;
  bool _isLive = true;   // true = live camera, false = uploaded photo
  File? _uploadedImage;
  
  late _HairCategory _selectedCategory;
  late _HairShade _selected;

  double _intensity = 0.45;
  bool _isFrontCamera = true;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _selectedCategory = _hairCategories.first;
    _selected = _selectedCategory.shades.first;
    
    // Pre-select product shade if passed in
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
    _initCamera();
  }
  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      final cam = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first);
      _camera = CameraController(cam, ResolutionPreset.high,
          enableAudio: false);
      await _camera!.initialize();
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    _isFrontCamera = !_isFrontCamera;
    final cam = _isFrontCamera
        ? _cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front)
        : _cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back);
    await _camera?.dispose();
    _camera = CameraController(cam, ResolutionPreset.high, enableAudio: false);
    await _camera!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _uploadPhoto() async {
    final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (f != null) {
      setState(() { _uploadedImage = File(f.path); _isLive = false; });
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        // ── Camera / photo viewport ──────────────────────────────────────────
        Positioned.fill(child: _buildViewport()),

        // ── Top bar ──────────────────────────────────────────────────────────
        SafeArea(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            _iconBtn(Icons.arrow_back_ios_new_rounded,
                () => Navigator.pop(context)),
            const Spacer(),
            Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('COLOUR MATCH',
                  style: TextStyle(color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w900, letterSpacing: 1)),
              Text(_selected.name,
                  style: const TextStyle(color: _gold, fontSize: 11)),
            ]),
            const Spacer(),
            _iconBtn(Icons.flip_camera_ios_outlined, _switchCamera),
          ]),
        )),

        // ── Hair color overlay info ──────────────────────────────────────────
        Positioned(
          top: 80, right: 16,
          child: Column(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _selected.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 8)],
              ),
            ),
            const SizedBox(height: 4),
            Text(_selected.name,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 9,
                    fontWeight: FontWeight.w600)),
          ]),
        ),

        // ── Bottom controls ──────────────────────────────────────────────────
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: _buildBottomPanel(),
        ),
      ]),
    );
  }

  Widget _buildViewport() {
    Widget preview;
    if (!_isLive && _uploadedImage != null) {
      preview = Image.file(_uploadedImage!, fit: BoxFit.cover,
          width: double.infinity, height: double.infinity);
    } else if (_cameraReady && _camera != null) {
      preview = CameraPreview(_camera!);
    } else {
      preview = Container(color: Colors.black,
          child: const Center(child: CircularProgressIndicator(color: _red)));
    }

    // Overlay a color blend to simulate hair dye effect over the camera feed
    return ShaderMask(
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [
          _selected.color.withOpacity(_intensity),
          _selected.color.withOpacity(_intensity * 0.6),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 0.75],
      ).createShader(rect),
      blendMode: BlendMode.overlay, // Overlay blends color while preserving texture and contrast of hair
      child: preview,
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      decoration: BoxDecoration(
        color: _bg.withOpacity(0.94),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          // Live / Upload toggle
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _toggleChip('Live Camera', _isLive, () => setState(() { _isLive = true; _uploadedImage = null; })),
            const SizedBox(width: 12),
            _toggleChip('Upload Photo', !_isLive, _uploadPhoto),
          ]),
          const SizedBox(height: 14),
          // Intensity slider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Text('Intensity', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _red,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: Colors.white,
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: _intensity,
                  min: 0.1, max: 0.85,
                  onChanged: (v) => setState(() => _intensity = v),
                ),
              )),
              Text('${(_intensity * 100).toInt()}%',
                  style: const TextStyle(color: _gold, fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 10),
          // Category swatches
          SizedBox(
            height: 36,
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
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : Colors.white12,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      cat.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.black : Colors.white70,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          // Specific shades for selected category
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _selectedCategory.shades.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final shade = _selectedCategory.shades[i];
                final isSelected = _selected == shade;
                return GestureDetector(
                  onTap: () => setState(() => _selected = shade),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: isSelected ? 42 : 36,
                      height: isSelected ? 42 : 36,
                      decoration: BoxDecoration(
                        color: shade.color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? _red : Colors.white24,
                          width: isSelected ? 3 : 1),
                        boxShadow: isSelected
                            ? [BoxShadow(color: _red.withOpacity(.4), blurRadius: 8)]
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
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _toggleChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _red : _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? _red : Colors.white12),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: active ? Colors.white : Colors.white54)),
      ),
    );
  }
}
