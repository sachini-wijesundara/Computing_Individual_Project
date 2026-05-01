// Nail try-on: Live = MediaPipe Hands on native camera (Android/iOS).
// Photo = static hand detection + draggable Flutter overlays + colours/art.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../native_lip_renderer.dart';
import '../services/hand_landmarker_platform.dart';

const _maroon = Color(0xFF7C150D);
const _gold = Color(0xFFDCB568);
const _bg = Color(0xFF121212);
const _muted = Color(0xFF9E9E9E);

enum _NailArtStyle { solid, frenchTip, ombre, sparkle }
enum _NailShape { natural, almond, square, stiletto }

class _NailSlot {
  double nx;
  double ny;
  double w;
  double h;
  double angle;
  _NailShape shape;

  _NailSlot(this.nx, this.ny, this.w, this.h, this.angle, {this.shape = _NailShape.natural});

  _NailSlot copy() => _NailSlot(nx, ny, w, h, angle, shape: shape);
}

List<_NailSlot> _defaultNailLayout() => [
      _NailSlot(0.30, 0.52, 0.038, 0.048, 0.12),
      _NailSlot(0.40, 0.46, 0.038, 0.048, 0.06),
      _NailSlot(0.50, 0.42, 0.038, 0.048, 0.0),
      _NailSlot(0.60, 0.46, 0.038, 0.048, -0.06),
      _NailSlot(0.72, 0.54, 0.042, 0.052, -0.38),
    ];

class NailTryOnScreen extends StatefulWidget {
  /// `true` = native back camera + MediaPipe nail overlay.
  const NailTryOnScreen({
    super.key,
    required this.liveMode,
    this.embedded = false,
    this.onClose,
  });

  final bool liveMode;
  final bool embedded;
  final VoidCallback? onClose;

  @override
  State<NailTryOnScreen> createState() => _NailTryOnScreenState();
}

class _NailTryOnScreenState extends State<NailTryOnScreen> {
  static const bool _useNative = bool.fromEnvironment('USE_NATIVE_LIP_RENDERER', defaultValue: true);

  bool get _nativeLive =>
      widget.liveMode &&
      _useNative &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  NativeLipRendererController? _nativeCtrl;
  File? _photoFile;
  ui.Image? _photoUi;
  final _picker = ImagePicker();

  List<_NailSlot> _slots = _defaultNailLayout().map((e) => e.copy()).toList();
  bool _adjustNails = true;
  double _slotScale = 1.0;
  double _polishOpacity = 0.72;
  Color _polishColor = const Color(0xFFC41E3A);
  _NailArtStyle _art = _NailArtStyle.solid;
  _NailShape _globalShape = _NailShape.natural;
  bool _detecting = false;

  static const _palette = <Color>[
    Color(0xFFC41E3A),
    Color(0xFF8E44AD),
    Color(0xFF1ABC9C),
    Color(0xFF2C3E50),
    Color(0xFFF39C12),
    Color(0xFFECF0F1),
    Color(0xFFFF6B9D),
    Color(0xFF00B894),
  ];

  @override
  void initState() {
    super.initState();
    if (!widget.liveMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickGallery());
    }
  }

  void _onNativeCreated(NativeLipRendererController c) {
    _nativeCtrl = c;
    // Apply `cmd_nails` before `start()` so the first session uses the back camera and nail routing.
    Future.microtask(() async {
      await _applyNativeNails();
      await c.start();
    });
  }

  Future<void> _applyNativeNails() async {
    final ctrl = _nativeCtrl;
    if (ctrl == null) return;
    await ctrl.setEffect(
      shade: _polishColor,
      intensity: _polishOpacity,
      category: 'cmd_nails',
      nailArtStyle: _art.index,
      nailShape: _globalShape.index,
    );
  }

  Future<void> _pickGallery() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (x == null) return;
    final file = File(x.path);
    setState(() {
      _photoFile = file;
      _photoUi = null;
      _slots = _defaultNailLayout().map((e) => e.copy()).toList();
      _detecting = true;
    });
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _photoUi = frame.image);

    final tips = await HandLandmarkerPlatform.detectTips(file.path);
    if (!mounted) return;
    if (tips.length >= 5) {
      setState(() {
        _slots = tips
            .take(5)
            .map(
              (t) => _NailSlot(
                t.nx.clamp(0.02, 0.98),
                t.ny.clamp(0.02, 0.98),
                (t.r * 1.75).clamp(0.022, 0.12),
                (t.r * 2.1).clamp(0.028, 0.14),
                t.angle + math.pi / 2,
                shape: _globalShape,
              ),
            )
            .toList();
        _detecting = false;
      });
    } else {
      setState(() {
        _slots = _defaultNailLayout().map((e) => e.copy()).toList();
        _detecting = false;
      });
    }
  }

  @override
  void dispose() {
    _nativeCtrl?.dispose();
    _photoUi?.dispose();
    super.dispose();
  }

  Size _containSize(Size box, double aspectWoverH) {
    if (aspectWoverH <= 0) return box;
    final bw = box.width;
    final bh = box.height;
    if (bw / bh > aspectWoverH) {
      return Size(bh * aspectWoverH, bh);
    }
    return Size(bw, bw / aspectWoverH);
  }

  double? _photoAspect() {
    final im = _photoUi;
    if (im == null || im.height == 0) return null;
    return im.width / im.height;
  }

  @override
  Widget build(BuildContext context) {
    final content = Stack(
      fit: StackFit.expand,
      children: [
          if (_nativeLive)
            NativeLipRendererView(onViewCreated: _onNativeCreated)
          else if (!widget.liveMode && _photoFile != null && _photoUi != null)
            LayoutBuilder(
              builder: (context, c) {
                final box = Size(c.maxWidth, c.maxHeight);
                final ar = _photoAspect();
                if (ar == null) return const SizedBox.shrink();
                final content = _containSize(box, ar);
                final ox = (box.width - content.width) / 2;
                final oy = (box.height - content.height) / 2;
                final rect = Rect.fromLTWH(ox, oy, content.width, content.height);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Colors.black),
                    Positioned(
                      left: rect.left,
                      top: rect.top,
                      width: rect.width,
                      height: rect.height,
                      child: Image.file(_photoFile!, fit: BoxFit.contain),
                    ),
                    Positioned(
                      left: rect.left,
                      top: rect.top,
                      width: rect.width,
                      height: rect.height,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (var i = 0; i < _slots.length; i++)
                            _DraggableNail(
                              slot: _slots[i],
                              index: i,
                              adjust: _adjustNails,
                              rectSize: rect.size,
                              scale: _slotScale,
                              color: _polishColor,
                              opacity: _polishOpacity,
                              art: _art,
                              shape: _slots[i].shape,
                              onPan: (dx, dy) {
                                setState(() {
                                  _slots[i].nx = (_slots[i].nx + dx / rect.width).clamp(0.02, 0.98);
                                  _slots[i].ny = (_slots[i].ny + dy / rect.height).clamp(0.02, 0.98);
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            )
          else if (!widget.liveMode)
            const ColoredBox(
              color: Colors.black,
              child: Center(child: CircularProgressIndicator(color: _gold)),
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Nail live try-on needs Android or iOS with the native renderer enabled.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                ),
              ),
            ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    widget.embedded ? Icons.close_rounded : Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    if (widget.onClose != null) {
                      widget.onClose!();
                      return;
                    }
                    Navigator.pop(context);
                  },
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.liveMode ? 'NAIL TRY-ON · LIVE' : 'NAIL TRY-ON · PHOTO',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        _nativeLive
                            ? '[v47] HSL-Texture PBR Engine Active'
                            : 'Drag nails if needed — MediaPipe placed them from your photo',
                        style: const TextStyle(color: _muted, fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_detecting && !widget.liveMode)
          const Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Center(
              child: Chip(
                label: Text('Detecting hand…'),
                backgroundColor: Colors.black54,
                labelStyle: TextStyle(color: Colors.white),
              ),
            ),
          ),
        Positioned(left: 0, right: 0, bottom: 0, child: _bottomPanel(context)),
      ],
    );

    if (widget.embedded) {
      return ColoredBox(color: _bg, child: content);
    }

    return Scaffold(
      backgroundColor: _bg,
      body: content,
    );
  }

  Widget _bottomPanel(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _bg.withValues(alpha: 0.94),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white12),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.liveMode) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _pickGallery,
                    icon: const Icon(Icons.photo_library_outlined, color: _gold),
                    label: const Text('Choose different photo', style: TextStyle(color: _gold)),
                  ),
                ),
                const SizedBox(height: 10),
                FilterChip(
                  label: const Text('Adjust nails'),
                  selected: _adjustNails,
                  onSelected: (v) => setState(() => _adjustNails = v),
                  selectedColor: _maroon.withValues(alpha: 0.35),
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: _adjustNails ? Colors.white : _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _slots = _defaultNailLayout().map((e) => e.copy()).toList();
                  }),
                  icon: const Icon(Icons.restart_alt_rounded, color: _gold, size: 18),
                  label: const Text('Reset layout', style: TextStyle(color: _gold)),
                ),
                const SizedBox(height: 8),
              ],
              const Text('COLOUR', style: TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _palette.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final col = _palette[i];
                    final sel = col == _polishColor;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _polishColor = col);
                        if (_nativeLive) _applyNativeNails();
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: col,
                          border: Border.all(color: sel ? _gold : Colors.white24, width: sel ? 2.5 : 1),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              const Text('NAIL ART', style: TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _artChip('Solid', _NailArtStyle.solid),
                  _artChip('French tip', _NailArtStyle.frenchTip),
                  _artChip('Ombré', _NailArtStyle.ombre),
                  _artChip('Sparkle', _NailArtStyle.sparkle),
                ],
              ),
              const SizedBox(height: 14),
              const Text('SHAPE', style: TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _shapeChip('Natural', _NailShape.natural),
                  _shapeChip('Almond', _NailShape.almond),
                  _shapeChip('Square', _NailShape.square),
                  _shapeChip('Stiletto', _NailShape.stiletto),
                ],
              ),
              if (!widget.liveMode) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Size', style: TextStyle(color: _muted, fontSize: 11)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: _gold,
                          inactiveTrackColor: Colors.white12,
                          thumbColor: Colors.white,
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          value: _slotScale,
                          min: 0.55,
                          max: 1.45,
                          onChanged: (v) => setState(() => _slotScale = v),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              Row(
                children: [
                  const Text('Opacity', style: TextStyle(color: _muted, fontSize: 11)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: _maroon,
                        inactiveTrackColor: Colors.white12,
                        thumbColor: Colors.white,
                        overlayShape: SliderComponentShape.noOverlay,
                      ),
                      child: Slider(
                        value: _polishOpacity,
                        min: 0.35,
                        max: 0.95,
                        onChanged: (v) {
                          setState(() => _polishOpacity = v);
                          if (_nativeLive) _applyNativeNails();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _artChip(String label, _NailArtStyle style) {
    final on = _art == style;
    return ChoiceChip(
      label: Text(label),
      selected: on,
      onSelected: (_) {
        setState(() => _art = style);
        if (_nativeLive) _applyNativeNails();
      },
      selectedColor: _maroon,
      labelStyle: TextStyle(
        color: on ? Colors.white : _muted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _shapeChip(String label, _NailShape shape) {
    final on = _globalShape == shape;
    return ChoiceChip(
      label: Text(label),
      selected: on,
      onSelected: (_) {
        setState(() {
          _globalShape = shape;
          for (var s in _slots) {
            s.shape = shape;
          }
        });
        if (_nativeLive) _applyNativeNails();
      },
      selectedColor: _gold.withValues(alpha: 0.8),
      labelStyle: TextStyle(
        color: on ? Colors.black : _muted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _DraggableNail extends StatelessWidget {
  final _NailSlot slot;
  final int index;
  final bool adjust;
  final Size rectSize;
  final double scale;
  final Color color;
  final double opacity;
  final _NailArtStyle art;
  final _NailShape shape;
  final void Function(double dx, double dy) onPan;

  const _DraggableNail({
    required this.slot,
    required this.index,
    required this.adjust,
    required this.rectSize,
    required this.scale,
    required this.color,
    required this.opacity,
    required this.art,
    required this.shape,
    required this.onPan,
  });

  @override
  Widget build(BuildContext context) {
    final bw = math.min(rectSize.width, rectSize.height);
    final w = slot.w * bw * scale;
    final h = slot.h * bw * scale;
    final left = slot.nx * rectSize.width - w / 2;
    final top = slot.ny * rectSize.height - h / 2;

    final nail = CustomPaint(
      size: Size(w, h),
      painter: _NailArtPainter(
        seed: index,
        color: color,
        opacity: opacity,
        style: art,
        shape: shape,
        showOutline: adjust,
      ),
    );

    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: adjust
          ? GestureDetector(onPanUpdate: (d) => onPan(d.delta.dx, d.delta.dy), child: Transform.rotate(angle: slot.angle, child: nail))
          : Transform.rotate(angle: slot.angle, child: nail),
    );
  }
}

class _NailArtPainter extends CustomPainter {
  final int seed;
  final Color color;
  final double opacity;
  final _NailArtStyle style;
  final _NailShape shape;
  final bool showOutline;

  _NailArtPainter({
    required this.seed,
    required this.color,
    required this.opacity,
    required this.style,
    required this.shape,
    required this.showOutline,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();

    // Create a path based on nail shape
    switch (shape) {
      case _NailShape.natural:
        // Slightly tapered oval
        path.moveTo(w * 0.1, h * 0.15);
        path.quadraticBezierTo(w * 0.5, -h * 0.1, w * 0.9, h * 0.15);
        path.lineTo(w, h * 0.82);
        path.quadraticBezierTo(w * 0.5, h * 1.05, 0, h * 0.82);
        path.close();
        break;
      case _NailShape.almond:
        // Pointy but rounded tip
        path.moveTo(w * 0.05, h * 0.5);
        path.quadraticBezierTo(w * 0.5, -h * 0.25, w * 0.95, h * 0.5);
        path.cubicTo(w, h * 0.9, w * 0.75, h, w * 0.5, h);
        path.cubicTo(w * 0.25, h, 0, h * 0.9, w * 0.05, h * 0.5);
        path.close();
        break;
      case _NailShape.square:
        // Broad tip with rounded corners
        const rad = 0.12;
        path.moveTo(w * rad, 0);
        path.lineTo(w * (1 - rad), 0);
        path.quadraticBezierTo(w, 0, w, h * rad);
        path.lineTo(w, h * (1 - rad));
        path.quadraticBezierTo(w, h, w * (1 - rad), h);
        path.lineTo(w * rad, h);
        path.quadraticBezierTo(0, h, 0, h * (1 - rad));
        path.lineTo(0, h * rad);
        path.quadraticBezierTo(0, 0, w * rad, 0);
        path.close();
        break;
      case _NailShape.stiletto:
        // Sharp point
        path.moveTo(w * 0.5, -h * 0.15);
        path.lineTo(w * 0.95, h * 0.6);
        path.quadraticBezierTo(w * 0.7, h * 1.1, w * 0.5, h * 0.95);
        path.quadraticBezierTo(w * 0.3, h * 1.1, 0.05, h * 0.6);
        path.close();
        break;
    }

    final rect = Offset.zero & size;

    switch (style) {
      case _NailArtStyle.solid:
        final paint = Paint()
          ..color = color.withValues(alpha: opacity)
          ..blendMode = BlendMode.multiply; // Better realism
        canvas.drawPath(path, paint);
        break;
      case _NailArtStyle.frenchTip:
        canvas.save();
        canvas.clipPath(path);
        // Base color (usually sheer/pinkish, but using user choice)
        final base = Paint()
          ..color = color.withValues(alpha: opacity * 0.7)
          ..blendMode = BlendMode.multiply;
        canvas.drawPath(path, base);
        // The white tip
        final tipPaint = Paint()
          ..color = const Color(0xFFF8F4F0).withValues(alpha: opacity * 0.98);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h * 0.32), tipPaint);
        canvas.restore();
        break;
      case _NailArtStyle.ombre:
        final p = Paint()
          ..blendMode = BlendMode.multiply
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [color.withValues(alpha: opacity), color.withValues(alpha: opacity * 0.2)],
          ).createShader(rect);
        canvas.drawPath(path, p);
        break;
      case _NailArtStyle.sparkle:
        final base = Paint()
          ..color = color.withValues(alpha: opacity * 0.75)
          ..blendMode = BlendMode.multiply;
        canvas.drawPath(path, base);
        final rnd = math.Random(seed);
        final dot = Paint()..isAntiAlias = true;
        for (var k = 0; k < 22; k++) {
          final ox = rnd.nextDouble() * w;
          final oy = rnd.nextDouble() * h;
          if (!path.contains(Offset(ox, oy))) continue;
          dot.color = Colors.white.withValues(alpha: opacity * (0.3 + rnd.nextDouble() * 0.6));
          canvas.drawCircle(Offset(ox, oy), 0.5 + rnd.nextDouble() * 1.5, dot);
        }
        break;
    }

    if (showOutline) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NailArtPainter old) =>
      old.seed != seed ||
      old.color != color ||
      old.opacity != opacity ||
      old.style != style ||
      old.showOutline != showOutline;
}
