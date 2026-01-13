import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../native_lip_renderer.dart';

import '../widgets/live_tryon_widgets.dart';
import '../services/simple_lip_detector.dart';
import '../widgets/realistic_lipstick_painter.dart';

class LiveTryOnScreen extends StatefulWidget {
  final String? productName;
  final String? productImage;
  final Color? productColor;
  final String? shadeName;
  final List<Map<String, String>>? shades;

  const LiveTryOnScreen({
    super.key,
    this.productName,
    this.productImage,
    this.productColor,
    this.shadeName,
    this.shades,
  });

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
  double _intensity = 0.7;
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

  bool get _shouldUseNativeRenderer =>
      _useNativeLipRenderer &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
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
    controller.start();
    _applyNativeEffect();
    controller.setDebug(showLandmarks: _nativeDebug);
  }

  void _handleNativeEvent(NativeLipRendererEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event.type) {
        case 'ready':
          _nativeReady = true;
          _nativeError = null;
          debugPrint('✅ Native renderer READY');
          break;
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

  void _applyNativeEffect() {
    final controller = _nativeController;
    if (controller == null) {
      debugPrint('⚠️ Native controller is NULL - cannot apply effect');
      return;
    }
    
    debugPrint('🎨 APPLYING NATIVE EFFECT:');
    debugPrint('   Color: $_currentShade');
    debugPrint('   Intensity: $_intensity');
    
    controller.setEffect(
      shade: _currentShade,
      intensity: _intensity,
    );
    
    debugPrint('✅ Native setEffect() called successfully');
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
    _controller?.dispose();
    _nativeController?.dispose();
    _mlDetector.dispose();
    super.dispose();
  }

  Color get _currentShade {
    if (widget.productColor != null) {
      return widget.productColor!;
    }
    final shades = widget.shades;
    if (shades != null && shades.isNotEmpty) {
      final index = _selectedShadeIndex.clamp(0, shades.length - 1);
      final hex = shades[index]['hex'] ?? '#D4717A';
      return _hexToColor(hex);
    }
    return const Color(0xFFD4717A);
  }

  Color _hexToColor(String hex) {
    var s = hex.replaceAll('#', '');
    if (s.length == 6) s = 'FF$s';
    return Color(int.parse(s, radix: 16));
  }

  Widget _buildNativeBody() {
    return Stack(
      children: [
        const Positioned.fill(
          child: ColoredBox(color: Colors.black),
        ),
        Positioned.fill(
          child: NativeLipRendererView(
            onViewCreated: _onNativeViewCreated,
            enableDebugOverlay: _nativeDebug,
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
                color: Colors.red.withOpacity(0.8),
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
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: BottomTray(
            height: 180,
            productImage: widget.productImage,
            shades: widget.shades ?? const [],
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.productName ?? 'Live Try-On'),
        backgroundColor: const Color(0xFF8B0000),
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

                        // Bottom tray
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: BottomTray(
                            height: 180,
                            productImage: widget.productImage,
                            shades: widget.shades ?? const [],
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
