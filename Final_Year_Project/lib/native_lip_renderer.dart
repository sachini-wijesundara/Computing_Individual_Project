import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

const _viewType = 'native_lip_renderer/view';

/// Event payloads emitted by the native renderer.
class NativeLipRendererEvent {
  final String type; // ready | fps | error
  final double? fps;
  final String? code;
  final String? message;

  NativeLipRendererEvent({
    required this.type,
    this.fps,
    this.code,
    this.message,
  });

  factory NativeLipRendererEvent.fromMap(Map<dynamic, dynamic> map) {
    final type = map['type'] as String? ?? 'unknown';
    return NativeLipRendererEvent(
      type: type,
      fps: (map['value'] as num?)?.toDouble(),
      code: map['code'] as String?,
      message: map['message'] as String?,
    );
  }
}

typedef NativeLipRendererCreatedCallback = void Function(
  NativeLipRendererController controller,
);

/// Platform view hosting the native camera + GL pipeline.
class NativeLipRendererView extends StatefulWidget {
  const NativeLipRendererView({
    super.key,
    this.onViewCreated,
    this.enableDebugOverlay = false,
  });

  final NativeLipRendererCreatedCallback? onViewCreated;
  final bool enableDebugOverlay;

  @override
  State<NativeLipRendererView> createState() => _NativeLipRendererViewState();
}

class _NativeLipRendererViewState extends State<NativeLipRendererView> {
  NativeLipRendererController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _handlePlatformViewCreated(int id) {
    final controller = NativeLipRendererController(viewId: id);
    _controller = controller;
    if (widget.enableDebugOverlay) {
      controller.setDebug(showLandmarks: true);
    }
    // Default calibration: mirror X for front camera, full scale, no offset
    controller.setCalibration(
      mirrorX: true,
      scale: 1.0,
      offsetX: 0.0,
      offsetY: 0.0,
    );
    widget.onViewCreated?.call(controller);
  }

  @override
  Widget build(BuildContext context) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return PlatformViewLink(
          viewType: _viewType,
          surfaceFactory: (context, controller) {
            return AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            );
          },
          onCreatePlatformView: (params) {
            final controller = PlatformViewsService.initSurfaceAndroidView(
              id: params.id,
              viewType: _viewType,
              layoutDirection: TextDirection.ltr,
              creationParams: const <String, dynamic>{},
              creationParamsCodec: const StandardMessageCodec(),
            );
            controller.addOnPlatformViewCreatedListener((id) {
              params.onPlatformViewCreated(id);
              _handlePlatformViewCreated(id);
            });
            controller.create();
            return controller;
          },
        );
      case TargetPlatform.iOS:
        return UiKitView(
          viewType: _viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: const <String, dynamic>{},
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _handlePlatformViewCreated,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Controller used to call into native code via MethodChannel.
class NativeLipRendererController {
  NativeLipRendererController({required int viewId})
      : _methodChannel = MethodChannel('native_lip_renderer/$viewId'),
        _eventChannel = EventChannel('native_lip_renderer/$viewId/events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  Stream<NativeLipRendererEvent>? _eventStream;
  StreamSubscription<NativeLipRendererEvent>? _subscription;

  Stream<NativeLipRendererEvent> get events {
    _eventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((dynamic event) => NativeLipRendererEvent.fromMap(
              Map<dynamic, dynamic>.from(event as Map),
            ));
    return _eventStream!;
  }

  void listen(void Function(NativeLipRendererEvent event) onData) {
    _subscription?.cancel();
    _subscription = events.listen(onData);
  }

  Future<void> start() => _methodChannel.invokeMethod<void>('start');

  Future<void> stop() => _methodChannel.invokeMethod<void>('stop');

  Future<void> setEffect({
    required Color shade,
    required double intensity,
    String category = "cmd_lipstick",
    bool isCompareMode = false, // Added
  }) async {
    await _methodChannel.invokeMethod<void>('setEffect', {
      'shade': shade.value,
      'intensity': intensity,
      'category': category,
      'isCompareMode': isCompareMode, // Added
    });
  }

  Future<void> setDebug({required bool showLandmarks}) async {
    await _methodChannel.invokeMethod<void>('setDebug', {
      'showLandmarks': showLandmarks,
    });
  }

  Future<void> setCalibration({
    double? offsetX,
    double? offsetY,
    double? scale,
    bool? mirrorX,
    double? splitPosition, // Added
  }) async {
    await _methodChannel.invokeMethod<void>('setCalibration', {
      if (offsetX != null) 'offsetX': offsetX,
      if (offsetY != null) 'offsetY': offsetY,
      if (scale != null) 'scale': scale,
      if (mirrorX != null) 'mirrorX': mirrorX,
      if (splitPosition != null) 'splitPosition': splitPosition, // Added
    });
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}

/// Thin convenience API for consumers that prefer a simple facade.
class NativeLipRenderer {
  const NativeLipRenderer();

  Widget view({
    Key? key,
    NativeLipRendererCreatedCallback? onViewCreated,
    bool enableDebugOverlay = false,
  }) {
    return NativeLipRendererView(
      key: key,
      onViewCreated: onViewCreated,
      enableDebugOverlay: enableDebugOverlay,
    );
  }
}
