package com.example.virtual_tryon_makeup

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    // App-local plugin (not listed in .flutter-plugins). Without this, the
    // platform view factory for native_lip_renderer/view is never registered.
    flutterEngine.plugins.add(NativeLipRendererPlatformViewPlugin())
  }
}
