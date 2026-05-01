// lib/screens/hair_color_tryon_screen.dart
//
// Hair Color Live Try-On Screen
//
// Live camera mode:  MediaPipe ImageSegmenter (native) → pixel-accurate mask →
//                    HSL color blend overlay on camera preview.
//
// Uploaded photo mode: tflite_flutter Interpreter runs hair_segmenter.tflite
//                      on the static image → per-pixel mask → CustomPainter
//                      with BlendMode.color for realistic recolouring.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
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

// ─── Isolate payload for hair segmentation ───────────────────────────────────
class _SegmentRequest {
  final String imagePath;
  final Uint8List modelBytes; // model bytes pre-loaded on main thread
  final int targetColorValue;
  final double intensity;
  const _SegmentRequest(this.imagePath, this.modelBytes, this.targetColorValue, this.intensity);
}

class _SegmentResult {
  final Uint8List? rgbaBytes; // RGBA bytes for a ui.Image
  final int width;
  final int height;
  const _SegmentResult(this.rgbaBytes, this.width, this.height);
}

// ─── HSL helpers (top-level, available in isolate) ───────────────────────────

/// Returns named record (h, s, l) all in [0, 1].
({double h, double s, double l}) _rgbToHSL(double r, double g, double b) {
  final maxC  = math.max(math.max(r, g), b);
  final minC  = math.min(math.min(r, g), b);
  final delta = maxC - minC;
  final l     = (maxC + minC) / 2.0;

  if (delta < 0.001) return (h: 0, s: 0, l: l);

  final s = delta / (1.0 - (2.0 * l - 1.0).abs());
  double h;
  if (maxC == r) {
    h = ((g - b) / delta) % 6.0;
    if (h < 0) h += 6.0;
  } else if (maxC == g) {
    h = (b - r) / delta + 2.0;
  } else {
    h = (r - g) / delta + 4.0;
  }
  return (h: h / 6.0, s: s, l: l);
}

/// Returns named record (r, g, b) all in [0, 1].
({double r, double g, double b}) _hslToRGB(double h, double s, double l) {
  if (s < 0.001) return (r: l, g: l, b: l);
  final c   = (1.0 - (2.0 * l - 1.0).abs()) * s;
  final x   = c * (1.0 - ((h * 6.0) % 2.0 - 1.0).abs());
  final m   = l - c / 2.0;
  final seg = (h * 6.0).toInt() % 6;
  final double r1, g1, b1;
  switch (seg) {
    case 0: r1 = c; g1 = x; b1 = 0;
    case 1: r1 = x; g1 = c; b1 = 0;
    case 2: r1 = 0; g1 = c; b1 = x;
    case 3: r1 = 0; g1 = x; b1 = c;
    case 4: r1 = x; g1 = 0; b1 = c;
    default:r1 = c; g1 = 0; b1 = x;
  }
  return (
    r: (r1 + m).clamp(0.0, 1.0),
    g: (g1 + m).clamp(0.0, 1.0),
    b: (b1 + m).clamp(0.0, 1.0),
  );
}

/// Runs in a background isolate: model bytes are already loaded on main thread.
/// Produces per-pixel RGBA overlay using proper HSL color transfer so hair
/// texture (highlights, shadows, strand detail) is fully preserved.
Future<_SegmentResult> _runHairSegmentIsolate(_SegmentRequest req) async {
  try {
    final bytes   = await File(req.imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return const _SegmentResult(null, 0, 0);

    // Work at 512×512 — good quality/speed balance on photos
    const kSize = 512;
    final resized = img.copyResize(decoded, width: kSize, height: kSize);

    // Create interpreter from pre-loaded bytes (rootBundle unavailable in isolate)
    final interpreter = Interpreter.fromBuffer(
      req.modelBytes,
      options: InterpreterOptions()..threads = 2,
    );

    final inputShape  = interpreter.getInputTensor(0).shape;
    final outputShape = interpreter.getOutputTensor(0).shape;
    final modelH = inputShape[1];
    final modelW = inputShape[2];

    final modelInput = img.copyResize(resized, width: modelW, height: modelH);

    final inputData = Float32List(modelH * modelW * 3);
    int idx = 0;
    for (int y = 0; y < modelH; y++) {
      for (int x = 0; x < modelW; x++) {
        final p = modelInput.getPixel(x, y);
        inputData[idx++] = p.r / 255.0;
        inputData[idx++] = p.g / 255.0;
        inputData[idx++] = p.b / 255.0;
      }
    }

    final inputTensor  = inputData.reshape([1, modelH, modelW, 3]);
    final numClasses   = outputShape.length >= 4 ? outputShape[3] : 1;
    final outputData   = Float32List(modelH * modelW * numClasses);
    final outputTensor = outputData.reshape([1, modelH, modelW, numClasses]);
    interpreter.run(inputTensor, outputTensor);
    interpreter.close();

    final hairChannel = numClasses > 1 ? 1 : 0;

    // Decompose target color → HSL
    final tR = ((req.targetColorValue >> 16) & 0xFF) / 255.0;
    final tG = ((req.targetColorValue >>  8) & 0xFF) / 255.0;
    final tB = ( req.targetColorValue        & 0xFF) / 255.0;
    final targetHSL = _rgbToHSL(tR, tG, tB);
    final tH = targetHSL.h;
    final tS = targetHSL.s;

    final outPixels = Uint8List(kSize * kSize * 4);

    for (int outY = 0; outY < kSize; outY++) {
      for (int outX = 0; outX < kSize; outX++) {
        final maskX   = (outX * modelW / kSize).toInt().clamp(0, modelW - 1);
        final maskY   = (outY * modelH / kSize).toInt().clamp(0, modelH - 1);
        final maskIdx = (maskY * modelW + maskX) * numClasses + hairChannel;

        var conf = outputData[maskIdx].clamp(0.0, 1.0);

        // Smoothstep with 0.25 cutoff
        if (conf < 0.25) {
          conf = 0.0;
        } else {
          final t = ((conf - 0.25) / 0.75).clamp(0.0, 1.0);
          conf = t * t * (3.0 - 2.0 * t);
        }

        final alpha = (conf * req.intensity * 240).round().clamp(0, 230);
        if (alpha == 0) continue;

        // Sample source pixel from the full-resolution resized image
        final srcPixel = resized.getPixel(outX, outY);
        final srcR = srcPixel.r / 255.0;
        final srcG = srcPixel.g / 255.0;
        final srcB = srcPixel.b / 255.0;

        // Proper HSL color replace: keep src luminance, apply target hue + saturation
        final srcHSL  = _rgbToHSL(srcR, srcG, srcB);
        final outRGB  = _hslToRGB(tH, tS, srcHSL.l);

        // Pre-multiply for correct srcOver compositing
        final aN   = alpha / 255.0;
        final base = (outY * kSize + outX) * 4;
        outPixels[base + 0] = (outRGB.r * aN * 255).round().clamp(0, 255);
        outPixels[base + 1] = (outRGB.g * aN * 255).round().clamp(0, 255);
        outPixels[base + 2] = (outRGB.b * aN * 255).round().clamp(0, 255);
        outPixels[base + 3] = alpha;
      }
    }

    return _SegmentResult(outPixels, kSize, kSize);
  } catch (e) {
    debugPrint('⚠️ Hair segmentation isolate error: $e');
    return const _SegmentResult(null, 0, 0);
  }
}

// ─── CustomPainter for photo hair colour overlay ──────────────────────────────
class _HairColorPainter extends CustomPainter {
  final ui.Image sourceImage;
  final ui.Image? maskImage;

  const _HairColorPainter({required this.sourceImage, this.maskImage});

  @override
  void paint(Canvas canvas, Size size) {
    final srcRect  = Rect.fromLTWH(0, 0, sourceImage.width.toDouble(), sourceImage.height.toDouble());
    final dstRect  = Rect.fromLTWH(0, 0, size.width, size.height);

    // 1) Draw the original photo
    canvas.drawImageRect(sourceImage, srcRect, dstRect, Paint());

    // 2) Blend the mask using BlendMode.plus (src-over with pre-multiplied alpha
    //    gives natural blending; the mask pixels ARE the HSL-blended hair color)
    if (maskImage != null) {
      final maskRect = Rect.fromLTWH(0, 0, maskImage!.width.toDouble(), maskImage!.height.toDouble());
      canvas.drawImageRect(
        maskImage!,
        maskRect,
        dstRect,
        Paint()..blendMode = BlendMode.srcOver,
      );
    }
  }

  @override
  bool shouldRepaint(_HairColorPainter old) =>
      old.maskImage != maskImage || old.sourceImage != sourceImage;
}

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
  bool _isLive = true;
  File? _uploadedImage;

  late _HairCategory _selectedCategory;
  late _HairShade _selected;

  double _intensity = 0.45;
  final _picker = ImagePicker();

  // Uploaded photo segmentation state
  ui.Image? _sourceUiImage;
  ui.Image? _hairMaskUiImage;
  bool _segmenting = false;
  Uint8List? _segmenterModelBytes;

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
    _sourceUiImage?.dispose();
    _hairMaskUiImage?.dispose();
    super.dispose();
  }

  void _onViewCreated(NativeLipRendererController controller) {
    _nativeController = controller;
    _nativeController?.start();
    _updateHairEffect();
  }

  void _updateHairEffect() {
    if (_isLive && _nativeController != null) {
      _nativeController!.setEffect(
        shade: _selected.color,
        intensity: _intensity,
        category: 'cmd_haircolor',
      );
    } else if (!_isLive && _uploadedImage != null) {
      _runPhotoSegmentation();
    }
  }

  Future<void> _uploadPhoto() async {
    final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (f == null) return;
    final file = File(f.path);
    setState(() {
      _uploadedImage = file;
      _isLive = false;
      _hairMaskUiImage = null;
      _sourceUiImage = null;
    });
    await _loadSourceImage(file);
    _runPhotoSegmentation();
  }

  Future<void> _loadSourceImage(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (mounted) {
      setState(() => _sourceUiImage = frame.image);
    }
  }

  Future<void> _runPhotoSegmentation() async {
    final file = _uploadedImage;
    if (file == null || _segmenting) return;
    setState(() => _segmenting = true);

    try {
      // Load model bytes on the main thread (rootBundle not available in isolates)
      if (_segmenterModelBytes == null) {
        try {
          final byteData = await rootBundle.load('assets/models/hair_segmenter.tflite');
          _segmenterModelBytes = byteData.buffer.asUint8List();
        } catch (e) {
          debugPrint('⚠️ hair_segmenter.tflite not found in assets: $e');
        }
      }

      if (_segmenterModelBytes == null) {
        // No segmenter model — skip
        if (mounted) setState(() => _segmenting = false);
        return;
      }

      final result = await compute(
        _runHairSegmentIsolate,
        _SegmentRequest(file.path, _segmenterModelBytes!, _selected.color.value, _intensity),
      );

      if (result.rgbaBytes != null && result.width > 0 && mounted) {
        final codec = await ui.ImageDescriptor.raw(
          await ui.ImmutableBuffer.fromUint8List(result.rgbaBytes!),
          width: result.width,
          height: result.height,
          pixelFormat: ui.PixelFormat.rgba8888,
        ).instantiateCodec();
        final frame  = await codec.getNextFrame();
        if (mounted) {
          setState(() {
            _hairMaskUiImage?.dispose();
            _hairMaskUiImage = frame.image;
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ Photo hair segmentation failed: $e');
    } finally {
      if (mounted) setState(() => _segmenting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
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

        // Segmentation progress indicator (photo mode)
        if (!_isLive && _segmenting)
          Positioned(
            top: 80, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  SizedBox(width: 10),
                  Text('Analysing hair…',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ]),
              ),
            ),
          ),

        Positioned(
          bottom: 0, left: 0, right: 0,
          child: _buildBottomPanel(),
        ),
      ]),
    );
  }

  Widget _buildViewport() {
    if (!_isLive) {
      final src = _sourceUiImage;
      if (src == null && _uploadedImage != null) {
        // Show raw image while ui.Image is loading
        return Image.file(_uploadedImage!, fit: BoxFit.cover,
            width: double.infinity, height: double.infinity);
      }
      if (src == null) return const SizedBox.shrink();

      return CustomPaint(
        painter: _HairColorPainter(
          sourceImage: src,
          maskImage: _hairMaskUiImage,
        ),
        size: Size.infinite,
      );
    }

    return NativeLipRendererView(onViewCreated: _onViewCreated);
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
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _toggleChip('Live Camera', _isLive, () {
              setState(() { _isLive = true; _uploadedImage = null; });
              _updateHairEffect();
            }),
            const SizedBox(width: 12),
            _toggleChip('Upload Photo', !_isLive, _uploadPhoto),
          ]),
          const SizedBox(height: 14),
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
                            ? [BoxShadow(color: shade.color.withOpacity(.4), blurRadius: 10)]
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
