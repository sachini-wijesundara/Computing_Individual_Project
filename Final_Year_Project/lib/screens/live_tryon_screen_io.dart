import 'package:la_vogue_vista/widgets/firebase_image.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import '../native_lip_renderer.dart';
import 'selfie_capture_screen.dart';

import '../models/product.dart';
import '../widgets/live_tryon_widgets.dart';
import '../services/firestore_service.dart';
import '../services/tryon_activity_service.dart';
import '../services/simple_lip_detector.dart';
import '../widgets/realistic_lipstick_painter.dart';

class LiveTryOnScreen extends StatefulWidget {
  final String? productId;
  final String? productName;
  final String? productImage;
  final String? productCategory; // Explicit category from DB
  final Color? productColor;
  final String? shadeName;
  final List<Map<String, String>>? shades;

  const LiveTryOnScreen({
    super.key,
    this.productId,
    this.productName,
    this.productImage,
    this.productCategory,
    this.productColor,
    this.shadeName,
    this.shades,
  });

  // Helper static method for navigation
  static Route route({
    String? productId,
    String? productName,
    String? productImage,
    String? productCategory,
    Color? productColor,
    String? shadeName,
    List<Map<String, String>>? shades,
  }) {
    return MaterialPageRoute(
      builder: (_) => LiveTryOnScreen(
        productId: productId,
        productName: productName,
        productImage: productImage,
        productCategory: productCategory,
        productColor: productColor,
        shadeName: shadeName,
        shades: shades,
      ),
      settings: RouteSettings(
        arguments: {
          'productId': productId,
          'productName': productName,
          'productImage': productImage,
          'productCategory': productCategory,
          'productColor': productColor,
          'shadeName': shadeName,
          'shades': shades,
        },
      ),
    );
  }

  @override
  State<LiveTryOnScreen> createState() => _LiveTryOnScreenState();
}

class _LiveTryOnScreenState extends State<LiveTryOnScreen> {
  static const bool _useNativeLipRenderer =
      bool.fromEnvironment('USE_NATIVE_LIP_RENDERER', defaultValue: true);

  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isProcessing = false;
  double _intensity = 0.4;
  int _frames = 0;
  int _detections = 0;
  double _fps = 0.0;
  DateTime? _lastFpsSample;
  final int _segmentEveryNFrames = 1; // Process every frame for higher FPS/accuracy
  int _frameIndex = 0;
  FinishPreset _finish = FinishPreset.satin;
  int _selectedShadeIndex = 0;
  final SimpleLipDetector _mlDetector = SimpleLipDetector();
  LipRegion? _lipRegion;

  NativeLipRendererController? _nativeController;
  bool _nativeReady = false;
  double _nativeFps = 0.0;
  String? _nativeError;
  bool _nativeDebug = false;
  bool _showLandmarks = true; // Debug mode to see lip points
  bool _isCompareMode = false;
  double _splitPosition = 0.5; // Added
  List<Map<String, String>> _remoteShades = const [];
  bool _didLoadRouteShades = false;
  bool _didLoadProduct = false;
  Product? _activeProduct;
  bool _addingToCart = false;

  // ── Photo try-on (Option A: native offline render) ────────────────────────
  String? _uploadedPhotoPath;
  Uint8List? _renderedPhotoPng;
  bool _photoBusy = false;
  String? _photoError;
  final bool _mirrorSelfiePreview = true;
  Timer? _photoRenderDebounce;
  String? _photoPathSentToNative;

  bool get _isPhotoMode => _uploadedPhotoPath != null;

  bool get _shouldUseNativeRenderer =>
      _useNativeLipRenderer &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TryOnActivityService.start(
        productId: (widget.productId ?? '').trim(),
        productName: (widget.productName ?? 'Live try-on').trim(),
        productCategory: widget.productCategory,
      );
    });
    _loadShadesFromFirestore();
    // Debug: Show which renderer is being used
    debugPrint('🎯 Native Renderer Enabled: $_shouldUseNativeRenderer');
    debugPrint('🎯 Platform: $defaultTargetPlatform');
    
    if (_shouldUseNativeRenderer) {
      debugPrint('✅ Using NATIVE renderer (Android/iOS)');
      _isInitialized = true;
    } else {
      debugPrint('⚠️ Using FLUTTER renderer (fallback)');
      _initializeCamera();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _alignSelectedShadeIndexToProvidedColor();
    if (_didLoadRouteShades) return;
    _didLoadRouteShades = true;
    final args = _routeArgs;
    _loadShadesFromFirestore(
      productId: (args?['productId'] ?? '').toString(),
      productName: (args?['productName'] ?? '').toString(),
      imagePath: (args?['productImage'] ?? '').toString(),
    );
    if (!_didLoadProduct) {
      _didLoadProduct = true;
      _loadActiveProduct(
        productId: (args?['productId'] ?? '').toString(),
      );
    }
  }

  Map<String, dynamic>? get _routeArgs {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      return args.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  Future<void> _loadShadesFromFirestore({
    String? productId,
    String? productName,
    String? imagePath,
  }) async {
    final docId = productId ?? widget.productId;
    final name = productName ?? widget.productName;
    final path = imagePath ?? widget.productImage;
    if ((docId == null || docId.isEmpty) &&
        (name == null || name.isEmpty) &&
        (path == null || path.isEmpty)) {
      return;
    }

    final shades = await FirestoreDb.instance.getProductShades(
      productId: docId,
      productName: name,
      imagePath: path,
    );
    debugPrint('🎨 Firestore shades fetched: ${shades.length} for ${name ?? docId ?? "product"}');
    if (!mounted || shades.isEmpty) return;
    setState(() {
      _remoteShades = shades;
      _alignSelectedShadeIndexToProvidedColor();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyNativeEffect();
    });
  }

  Future<void> _loadActiveProduct({String? productId}) async {
    final id = (productId ?? widget.productId ?? '').trim();
    if (id.isEmpty) return;
    final product = await FirestoreDb.instance.getProduct(id);
    if (!mounted || product == null) return;
    setState(() {
      _activeProduct = product;
    });
    TryOnActivityService.updateProduct(
      productId: product.id,
      productName: product.name,
      productCategory: product.category,
    );
    // Re-apply once product subCategory is available (blush/highlighter/concealer).
    _applyNativeEffect();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _controller = CameraController(
        front,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _controller!.initialize();
      await _controller!.startImageStream(_onImage);
      if (!mounted) return;
      setState(() {
        _isInitialized = true;
      });
    } catch (e, st) {
      debugPrint('❌ _initializeCamera error: $e\n$st');
    }
  }

  void _onNativeViewCreated(NativeLipRendererController controller) {
    _nativeController = controller;
    controller.listen(_handleNativeEvent);
    if (!_isPhotoMode) {
      controller.start();
    }
    _applyNativeEffect();
    controller.setDebug(showLandmarks: _nativeDebug);
  }

  void _handleNativeEvent(NativeLipRendererEvent event) {
    if (!mounted) return;
    if (event.type == 'ready') {
      setState(() {
        _nativeReady = true;
        _nativeError = null;
      });
      debugPrint('✅ Native renderer READY');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyNativeEffect();
      });
      return;
    }
    setState(() {
      switch (event.type) {
        case 'fps':
          _nativeFps = event.fps ?? 0;
          debugPrint('📊 Native FPS: ${_nativeFps.toStringAsFixed(1)}');
          break;
        case 'error':
          _nativeReady = false;
          _nativeError = event.message ?? event.code;
          debugPrint('❌ Native error: $_nativeError');
          break;
        default:
          break;
      }
    });
  }

  Future<void> _applyNativeEffect() async {
    final controller = _nativeController;
    if (controller == null) {
      if (kDebugMode && _shouldUseNativeRenderer) {
        debugPrint('Native try-on: effect deferred (platform view not ready yet)');
      }
      return;
    }
    
    // Fallback to ModalRoute arguments if widget params are null
    final args = _routeArgs;
    final pId = ((widget.productId ?? args?['productId']) ?? '').toString();
    final pName =
        ((widget.productName ?? args?['productName']) ?? '').toString();
    final pPath =
        ((widget.productImage ?? args?['productImage']) ?? '').toString();
    final pCat =
        ((widget.productCategory ?? args?['productCategory']) ?? '').toString();
    
    debugPrint('🎨 APPLYING NATIVE EFFECT:');
    debugPrint('   Product ID: $pId');
    debugPrint('   Product Name: $pName');
    debugPrint('   Category: $pCat');
    debugPrint('   Image Path: $pPath');

    final arCommand = _resolveArCommand(
      productId: pId,
      productName: pName,
      productCategory: pCat,
      productImage: pPath,
    );
    
    debugPrint('🎨 Resolved AR Command: $arCommand');

    await controller.setEffect(
      shade: _currentShade,
      intensity: _intensity,
      category: arCommand,
      isCompareMode: _isCompareMode,
    );
    
    debugPrint('✅ Native setEffect() called successfully');

    if (_isPhotoMode) {
      _schedulePhotoRender();
    }
  }

  void _schedulePhotoRender() {
    _photoRenderDebounce?.cancel();
    _photoRenderDebounce = Timer(const Duration(milliseconds: 180), () {
      _photoRenderDebounce = null;
      if (!mounted) return;
      _renderPhotoTryOn();
    });
  }

  Future<void> _captureSelfieTryOn() async {
    try {
      final ctrl = _nativeController;
      // Release native camera before opening selfie capture to avoid camera resource conflicts.
      if (ctrl != null) {
        await ctrl.stop();
      }
      if (!mounted) return;

      // Small delay gives iOS time to release camera session before opening selfie capture.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      final path = await SelfieCaptureScreen.capture(context);
      if (path == null || !mounted) {
        // User canceled selfie capture; resume live camera preview.
        if (ctrl != null) {
          await ctrl.start();
          await _applyNativeEffect();
        }
        return;
      }
      setState(() {
        _uploadedPhotoPath = path;
        _renderedPhotoPng = null;
        _photoError = null;
        _photoPathSentToNative = null;
      });
      if (ctrl != null) {
        await _applyNativeEffect();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _photoError = e.toString());
    }
  }

  Future<void> _clearPhotoTryOn() async {
    final ctrl = _nativeController;
    setState(() {
      _uploadedPhotoPath = null;
      _renderedPhotoPng = null;
      _photoError = null;
      _photoPathSentToNative = null;
    });
    if (ctrl != null) {
      await ctrl.start();
    }
    await _applyNativeEffect();
  }

  Future<void> _renderPhotoTryOn() async {
    final ctrl = _nativeController;
    final path = _uploadedPhotoPath;
    if (ctrl == null || path == null) return;
    setState(() {
      _photoBusy = true;
      _photoError = null;
    });
    try {
      if (_photoPathSentToNative != path) {
        await ctrl.setPhoto(imageFilePath: path);
        _photoPathSentToNative = path;
      }
      final png = await ctrl.renderPhoto();
      if (!mounted) return;
      setState(() {
        _renderedPhotoPng = png;
        _photoBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _photoBusy = false;
        _photoError = e.toString();
      });
    }
  }

  String _resolveArCommand({
    required String productId,
    required String productName,
    required String productCategory,
    required String productImage,
  }) {
    final id = productId.toLowerCase();
    final name = productName.toLowerCase();
    final cat = productCategory.toLowerCase();
    final image = productImage.toLowerCase();
    final all = '$id $cat $name $image';

    bool hasAny(List<String> keys) => keys.any(all.contains);

    // 1) Hair product routing
    if (cat.contains('hair') || id.startsWith('hc_') || image.contains('/hair')) {
      return 'cmd_haircolor';
    }

    // 2) Strongest signal: seeded IDs by prefix
    if (id.startsWith('mas_')) return 'cmd_mascara';
    if (id.startsWith('es_'))  return 'cmd_eyeshadow';
    if (id.startsWith('el_'))  return 'cmd_eyeliner';
    if (id.startsWith('eb_'))  return 'cmd_eyebrow';
    if (id.startsWith('lip_')) return 'cmd_lipstick';

    // 3) Face product routing by subCategory (from widget or route args)
    if (id.startsWith('fp_') || cat == 'face') {
      final args = _routeArgs;
      final sub = (
        _activeProduct?.subCategory ??
        (args?['subCategory'] as String? ?? '')
      ).toLowerCase();

      if (sub == 'blush')              return 'cmd_blush';
      if (sub == 'highlighter')        return 'cmd_highlight';
      if (sub == 'contour & bronzer')  return 'cmd_highlight';
      // Use cmd_face (full-face mask) like full_makeup_screen — cmd_concealer’s multi-polygon
      // path overlaps under-eye + nose regions and evenOdd fill cancels overlap → “not applying”.
      if (sub == 'concealer')          return 'cmd_face';
      // foundation / powder → generic face overlay
      return 'cmd_face';
    }

    // 4) Stable folder names in image path
    if (image.contains('/mascara/'))    return 'cmd_mascara';
    if (image.contains('/eyeshadows/')) return 'cmd_eyeshadow';
    if (image.contains('/eyeliner/'))   return 'cmd_eyeliner';
    if (image.contains('/eyebrow/'))    return 'cmd_eyebrow';
    if (image.contains('/lipsticks/'))  return 'cmd_lipstick';
    if (image.contains('/face products/')) {
      if (image.contains('/blush/'))            return 'cmd_blush';
      if (image.contains('/highlighter/'))      return 'cmd_highlight';
      if (image.contains('/contour_bronzer/'))  return 'cmd_highlight';
      if (image.contains('/concealer/'))        return 'cmd_face';
      return 'cmd_face';
    }

    // 5) Product keyword fallback
    if (hasAny(['lip liner', 'lipliner', 'lip pencil'])) return 'cmd_lipliner';
    if (hasAny(['eyebrow', 'eye brow', 'brow']))         return 'cmd_eyebrow';
    if (hasAny(['mascara', 'masacara', 'masacra', 'lash'])) return 'cmd_mascara';
    if (hasAny(['eyeshadow', 'eye shadow', 'shadow stick', 'liquid eye shadow', 'palette'])) {
      return 'cmd_eyeshadow';
    }
    if (hasAny(['eyeliner', 'eye liner', 'kohl', 'kajal'])) return 'cmd_eyeliner';
    if (hasAny(['lipstick', 'lip gloss', 'lip balm', 'lip colour', 'lip color'])) {
      return 'cmd_lipstick';
    }
    if (hasAny(['blush', 'rouge']))                             return 'cmd_blush';
    if (hasAny(['highlighter', 'illuminator', 'glow']))         return 'cmd_highlight';
    if (hasAny(['bronzer', 'contour', 'sculpt']))               return 'cmd_highlight';
    if (hasAny(['concealer']))                                   return 'cmd_face';
    if (hasAny(['foundation', 'face powder', 'compact']))        return 'cmd_face';

    return 'cmd_lipstick';
  }

  Future<void> _onImage(CameraImage image) async {
    if (!_isInitialized) return;
    if (_isProcessing) return;
    _isProcessing = true;

    _frameIndex++;
    if (_frameIndex % _segmentEveryNFrames != 0) {
      _isProcessing = false;
      return;
    }

    _frames++;

    try {
      final description = _controller?.description;
      if (description == null) {
        _isProcessing = false;
        return;
      }
      final rotation = description.sensorOrientation;
      final front = description.lensDirection == CameraLensDirection.front;

      final mlResult = await _mlDetector.detectLipsFromYuv(
        image,
        rotationDegrees: rotation,
        frontCamera: front,
      );

      final now = DateTime.now();
      if (_lastFpsSample == null) {
        _lastFpsSample = now;
      } else {
        final dt = now.difference(_lastFpsSample!).inMilliseconds;
        if (dt > 500) {
          _fps = _frames * 1000 / dt;
          _frames = 0;
          _lastFpsSample = now;
        }
      }

      
      if (mlResult != null) {
        _detections += 1;
        _lipRegion = mlResult;
      } else {
        _lipRegion = null;
      }
    } catch (e, st) {
      debugPrint('❌ _onImage error: $e\n$st');
      _lipRegion = null;
    } finally {
      _isProcessing = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _photoRenderDebounce?.cancel();
    TryOnActivityService.stop();
    _controller?.dispose();
    _nativeController?.dispose();
    _mlDetector.dispose();
    super.dispose();
  }

  List<Map<String, String>> get _effectiveShades {
    if (_remoteShades.isNotEmpty) return _remoteShades;
    final args = _routeArgs;
    final argShades = _parseShades(args?['shades']);
    final widgetShades = _parseShades(widget.shades);
    if (argShades.isNotEmpty) return argShades;
    if (widgetShades.isNotEmpty) return widgetShades;
    return const [];
  }

  Color get _currentShade {
    final args = _routeArgs;

    // 1) Prefer actively selected shade from shades list for live updates.
    final shades = _effectiveShades;
    if (shades.isNotEmpty) {
      final index = _selectedShadeIndex.clamp(0, shades.length - 1);
      final hex = _shadeHex(shades[index]) ?? '#D4717A';
      return _hexToColor(hex);
    }

    // 2) Fallback to provided product color when no shade list exists.
    if (widget.productColor != null) return widget.productColor!;
    if (args?['productColor'] is Color) return args?['productColor'] as Color;

    return const Color(0xFFD4717A);
  }

  List<Map<String, String>> _parseShades(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) {
          final map = m.map((k, v) => MapEntry(k.toString(), v.toString()));
          final hex = _shadeHex(map);
          return {
            'name': map['name'] ?? map['shade'] ?? 'Shade',
            if (hex != null) 'hex': hex,
          };
        })
        .where((m) => m['hex'] != null)
        .toList();
  }

  String? _shadeHex(Map<String, String> shade) {
    final raw = shade['hex'] ??
        shade['colorHex'] ??
        shade['colourHex'] ??
        shade['color'] ??
        shade['colour'] ??
        shade['value'];
    if (raw == null || raw.isEmpty) return null;
    var s = raw.trim();
    if (s.startsWith('0x') || s.startsWith('0X')) s = s.substring(2);
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 8) s = s.substring(2);
    if (s.length != 6 || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s)) return null;
    return '#${s.toUpperCase()}';
  }

  void _alignSelectedShadeIndexToProvidedColor() {
    final shades = _effectiveShades;
    if (shades.isEmpty) return;

    final args = _routeArgs;
    Color? provided = widget.productColor;
    if (provided == null && args?['productColor'] is Color) {
      provided = args?['productColor'] as Color;
    }
    if (provided == null) return;

    final target = '#${(provided.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    final idx = shades.indexWhere((s) => _shadeHex(s) == target);
    if (idx >= 0) {
      _selectedShadeIndex = idx;
    }
  }

  Color _hexToColor(String hex) {
    var s = hex.replaceAll('#', '');
    if (s.length == 6) s = 'FF$s';
    return Color(int.parse(s, radix: 16));
  }

  String get _selectedShadeName {
    final shades = _effectiveShades;
    if (shades.isEmpty) return 'Default Shade';
    final idx = _selectedShadeIndex.clamp(0, shades.length - 1);
    return shades[idx]['name'] ?? 'Shade';
  }

  Future<void> _addCurrentProductToCart() async {
    if (_addingToCart) return;
    final product = _activeProduct;
    final user = FirebaseAuth.instance.currentUser;
    if (product == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product not ready yet.')),
      );
      return;
    }
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to add items to cart.')),
      );
      return;
    }
    setState(() => _addingToCart = true);
    await FirestoreDb.instance.addToCart(user.uid, product);
    if (!mounted) return;
    setState(() => _addingToCart = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.name} added to cart'),
        backgroundColor: const Color(0xFF1F8A43),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildCompareOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final splitX = width * _splitPosition.clamp(0.0, 1.0);

        void moveByDelta(double dx) {
          final next = (_splitPosition + (dx / width)).clamp(0.05, 0.95);
          setState(() => _splitPosition = next);
          _nativeController?.setCalibration(
            splitPosition: _splitPosition,
            isCompareMode: _isCompareMode,
          );
        }

        return Stack(
          children: [
            Positioned(
              left: splitX - 0.5,
              top: 0,
              bottom: 0,
              child: Container(
                width: 1,
                color: Colors.white.withValues(alpha: 0.95),
              ),
            ),
            Positioned(
              left: splitX - 28,
              top: (height * 0.55) - 28,
              child: GestureDetector(
                onHorizontalDragUpdate: (d) => moveByDelta(d.delta.dx),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black12),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.compare_arrows_rounded, color: Colors.black87),
                ),
              ),
            ),
            Positioned(
              left: 42,
              top: 110,
              child: _comparePill('BEFORE'),
            ),
            Positioned(
              right: 42,
              top: 110,
              child: _comparePill('AFTER'),
            ),
            Positioned(
              left: splitX - 24,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (d) => moveByDelta(d.delta.dx),
                child: const SizedBox(width: 48),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _comparePill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildProductPopupCard() {
    final name = widget.productName ?? _activeProduct?.name ?? 'Product';
    final path = widget.productImage ?? _activeProduct?.imagePath ?? '';
    final fallbackUrl = _activeProduct?.imageUrl ?? '';
    final imageRef = path.isNotEmpty ? path : fallbackUrl;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 44,
              height: 44,
            child: imageRef.isEmpty
                ? const Icon(Icons.inventory_2_outlined, color: Colors.black45)
                : FirebaseStorageImage(
                    storagePath: imageRef,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20 / 1.4),
                ),
                const SizedBox(height: 2),
                Text(
                  _selectedShadeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.favorite_border_rounded),
          ),
          const SizedBox(width: 2),
          SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: _addingToCart ? null : _addCurrentProductToCart,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(_addingToCart ? 'ADDING...' : 'ADD TO CART'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNativeBody() {
    return Stack(
      children: [
        const Positioned.fill(
          child: ColoredBox(color: Colors.black),
        ),
        // Keep the native view alive even in selfie mode so we still have a controller
        // for setPhoto/renderPhoto + makeup rendering. We just hide it under the photo.
        Positioned.fill(
          child: Opacity(
            opacity: _isPhotoMode ? 0.0 : 1.0,
            child: NativeLipRendererView(
              onViewCreated: _onNativeViewCreated,
              enableDebugOverlay: _nativeDebug,
            ),
          ),
        ),
        Positioned.fill(
          child: _isPhotoMode
              ? (_renderedPhotoPng != null
                  ? _buildMirroredIfNeeded(Image.memory(_renderedPhotoPng!, fit: BoxFit.cover))
                  : (_uploadedPhotoPath != null
                      ? _buildMirroredIfNeeded(Image.file(
                          File(_uploadedPhotoPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(
                              'Photo load failed. Please retake selfie.',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.92)),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ))
                      : const SizedBox.shrink()))
              : const SizedBox.shrink(),
        ),
        if (_photoBusy)
          const Positioned(
            left: 0,
            right: 0,
            top: 120,
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        if (_photoError != null)
          Positioned(
            left: 16,
            right: 16,
            top: 120,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _photoError!,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        if (_nativeError != null)
          Positioned(
            left: 16,
            right: 16,
            top: 88,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _nativeError!,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        Positioned(
          left: 16,
          top: 16,
          child: Hud(
            ready: _nativeReady,
            fps: _nativeFps,
            frames: 0,
            det: 0,
          ),
        ),
        Positioned(
          right: 16,
          top: 16,
          child: CircleButton(
            icon: _nativeDebug ? Icons.bug_report : Icons.bug_report_outlined,
            onTap: () {
              setState(() => _nativeDebug = !_nativeDebug);
              _nativeController?.setDebug(showLandmarks: _nativeDebug);
            },
          ),
        ),
        if (_isCompareMode)
          Positioned.fill(
            child: _buildCompareOverlay(),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 232,
          child: _buildProductPopupCard(),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: BottomTray(
            isCompareMode: _isCompareMode,
            onModeChange: (val) => setState(() {
              _isCompareMode = val;
              _applyNativeEffect();
            }),
            splitPosition: _splitPosition,
            onSplitChange: (val) => setState(() {
              _splitPosition = val;
              _nativeController?.setCalibration(
                splitPosition: val,
                isCompareMode: _isCompareMode,
              );
            }),
            height: 240,
            productImage: widget.productImage,
            shades: _effectiveShades,
            selectedIndex: _selectedShadeIndex,
            intensity: _intensity,
            onSelect: (index) {
              setState(() => _selectedShadeIndex = index);
              _applyNativeEffect();
            },
            onIntensityChange: (v) {
              setState(() => _intensity = v);
              _applyNativeEffect();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMirroredIfNeeded(Widget child) {
    if (!_mirrorSelfiePreview) return child;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.productName ?? (_isPhotoMode ? 'Virtual Try-On (Selfie)' : 'Virtual Try-On')),
        backgroundColor: const Color(0xFF8B0000),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            tooltip: _isPhotoMode ? 'Clear selfie' : 'Take selfie',
            icon: Icon(_isPhotoMode ? Icons.close_rounded : Icons.camera_alt_outlined),
            onPressed: () {
              if (_isPhotoMode) {
                _clearPhotoTryOn();
              } else {
                _captureSelfieTryOn();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: _shouldUseNativeRenderer
          ? _buildNativeBody()
          : (_isInitialized && _controller != null
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    final screenSize = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );

                    final previewSize = _controller!.value.previewSize!;
                    final double cameraWidth = previewSize.height.toDouble();
                    final double cameraHeight = previewSize.width.toDouble();

                    final double cameraAspect = cameraWidth / cameraHeight;
                    final double screenAspect =
                        screenSize.width / screenSize.height;

                    double drawWidth, drawHeight, dx, dy;

                    if (screenAspect > cameraAspect) {
                      // screen is wider → full height, centered horizontally
                      drawHeight = screenSize.height;
                      drawWidth = drawHeight * cameraAspect;
                      dx = (screenSize.width - drawWidth) / 2;
                      dy = 0;
                    } else {
                      // screen is taller → full width, centered vertically
                      drawWidth = screenSize.width;
                      drawHeight = drawWidth / cameraAspect;
                      dx = 0;
                      dy = (screenSize.height - drawHeight) / 2;
                    }

                    final previewRect =
                        Rect.fromLTWH(dx, dy, drawWidth, drawHeight);

                    return Stack(
                      children: [
                        // Background
                        const Positioned.fill(
                          child: ColoredBox(color: Colors.black),
                        ),

                        // Camera preview exactly in previewRect
                        Positioned.fromRect(
                          rect: previewRect,
                          child: CameraPreview(_controller!),
                        ),

                        // Lipstick overlay with adaptive smoothing and tracking
                        if (_lipRegion != null && _controller != null)
                          Positioned.fromRect(
                            rect: previewRect,
                            child: CustomPaint(
                              painter: RealisticLipstickPainter(
                                lipRegion: _lipRegion!,
                                previewRectOnScreen: previewRect,
                                shade: _currentShade,
                                intensity: _intensity,
                                isFrontFacing: _controller!.description.lensDirection == CameraLensDirection.front,
                                innerLipPoints: _lipRegion!.innerPoints,
                                showLandmarks: _showLandmarks, // Show debug points
                              ),
                            ),
                          ),

                        // HUD
                        Positioned(
                          left: 16,
                          top: 16,
                          child: Hud(
                            ready: _lipRegion != null,
                            fps: _fps,
                            frames: _frames,
                            det: _detections,
                          ),
                        ),

                        // Debug toggle button
                        Positioned(
                          right: 16,
                          top: 16,
                          child: CircleButton(
                            icon: _showLandmarks ? Icons.visibility : Icons.visibility_off,
                            onTap: () {
                              setState(() {
                                _showLandmarks = !_showLandmarks;
                              });
                            },
                          ),
                        ),
                        if (_isCompareMode)
                          Positioned.fill(
                            child: _buildCompareOverlay(),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 232,
                          child: _buildProductPopupCard(),
                        ),

                        // Bottom tray
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: BottomTray(
                            isCompareMode: _isCompareMode,
                            onModeChange: (val) => setState(() => _isCompareMode = val),
                            splitPosition: _splitPosition,
                            onSplitChange: (val) => setState(() => _splitPosition = val),
                            height: 240,
                            productImage: widget.productImage,
                            shades: _effectiveShades,
                            selectedIndex: _selectedShadeIndex,
                            intensity: _intensity,
                            onSelect: (index) {
                              setState(() => _selectedShadeIndex = index);
                            },
                            onIntensityChange: (v) {
                              setState(() => _intensity = v);
                            },
                          ),
                        ),
                      ],
                    );
                  },
                )
              : const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )),
    );
  }
}
