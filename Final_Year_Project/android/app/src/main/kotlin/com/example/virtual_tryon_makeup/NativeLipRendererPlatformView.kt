package com.example.virtual_tryon_makeup

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PointF
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.util.Log
import android.widget.FrameLayout
import androidx.annotation.MainThread
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.core.ImageProcessingOptions
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.max

private const val VIEW_TYPE = "native_lip_renderer/view"
private const val CHANNEL_PREFIX = "native_lip_renderer"
private const val CAMERA_PERMISSION_REQUEST = 9001

class NativeLipRendererPlatformViewPlugin : FlutterPlugin, ActivityAware,
  PluginRegistry.RequestPermissionsResultListener {
  private var pluginBinding: FlutterPlugin.FlutterPluginBinding? = null
  private var activityBinding: ActivityPluginBinding? = null
  private var factory: LipRendererFactory? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    pluginBinding = binding
    val viewFactory = LipRendererFactory(binding.binaryMessenger, binding.applicationContext)
    factory = viewFactory
    binding.platformViewRegistry.registerViewFactory(VIEW_TYPE, viewFactory)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    factory?.dispose()
    factory = null
    pluginBinding = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activityBinding = binding
    factory?.bindActivity(binding.activity)
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activityBinding?.removeRequestPermissionsResultListener(this)
    factory?.unbindActivity()
    activityBinding = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    onAttachedToActivity(binding)
  }

  override fun onDetachedFromActivity() {
    activityBinding?.removeRequestPermissionsResultListener(this)
    factory?.unbindActivity()
    activityBinding = null
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray
  ): Boolean {
    if (requestCode != CAMERA_PERMISSION_REQUEST) return false
    val granted = grantResults.isNotEmpty() &&
      grantResults[0] == PackageManager.PERMISSION_GRANTED
    factory?.handlePermissionResult(granted)
    return true
  }
}

private class LipRendererFactory(
  private val messenger: BinaryMessenger,
  private val appContext: Context
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

  private var activity: Activity? = null
  private var lastView: LipRendererPlatformView? = null

  fun bindActivity(activity: Activity) { this.activity = activity }
  fun unbindActivity() { this.activity = null }
  fun dispose() { unbindActivity() }

  override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
    val view = LipRendererPlatformView(appContext, activity, messenger, viewId)
    lastView = view
    return view
  }

  fun handlePermissionResult(granted: Boolean) {
    lastView?.onPermissionResult(granted)
  }
}

private class LipRendererPlatformView(
  private val appContext: Context,
  private var activity: Activity?,
  messenger: BinaryMessenger,
  private val viewId: Int,
) : PlatformView, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

  private val methodChannel = MethodChannel(messenger, "$CHANNEL_PREFIX/$viewId")
  private val eventChannel = EventChannel(messenger, "$CHANNEL_PREFIX/$viewId/events")
  private val container: FrameLayout = FrameLayout(appContext)
  private val previewView: PreviewView = PreviewView(appContext)
  private val glOverlay: LipMaskGLSurfaceView = LipMaskGLSurfaceView(appContext)

  private var cameraProvider: ProcessCameraProvider? = null
  private var analyzer: ImageAnalysis? = null
  private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
  private var eventSink: EventChannel.EventSink? = null
  private var startRequested = false

  private var faceLandmarker: FaceLandmarker? = null
  @Volatile private var processing = false
  private var rgbaBitmap: Bitmap? = null

  init {
    methodChannel.setMethodCallHandler(this)
    eventChannel.setStreamHandler(this)

    // Match PreviewView to FILL_CENTER for Snapchat-like full screen
    previewView.scaleType = PreviewView.ScaleType.FILL_CENTER
    
    container.addView(previewView, FrameLayout.LayoutParams(-1, -1))
    container.addView(glOverlay, FrameLayout.LayoutParams(-1, -1))
  }

  override fun getView() = container

  override fun dispose() {
    stopCamera()
    eventChannel.setStreamHandler(null)
    methodChannel.setMethodCallHandler(null)
    cameraExecutor.shutdown()
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "start" -> { startRequested = true; startCameraIfReady(); result.success(null) }
      "stop" -> { startRequested = false; stopCamera(); result.success(null) }
      "setEffect" -> {
        val args = call.arguments as? Map<*, *>
        val shade = (args?.get("shade") as? Number)?.toInt() ?: 0
        val intensity = (args?.get("intensity") as? Number)?.toFloat() ?: 0.7f
        glOverlay.setEffect(shade, intensity)
        result.success(null)
      }
      "setDebug" -> {
        val show = (call.arguments as? Map<*, *>)?.get("showLandmarks") as? Boolean ?: false
        glOverlay.setShowLandmarks(show)
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  override fun onListen(args: Any?, events: EventChannel.EventSink?) { eventSink = events; if (startRequested) startCameraIfReady() }
  override fun onCancel(args: Any?) { eventSink = null }

  fun onPermissionResult(granted: Boolean) { if (granted) startCameraIfReady() }

  private fun startCameraIfReady() {
    val lifecycleOwner = (activity as? LifecycleOwner) ?: return
    if (!startRequested || !ensureLandmarker() || !hasCameraPermission()) return
    
    val providerFuture = ProcessCameraProvider.getInstance(appContext)
    providerFuture.addListener({
      val provider = providerFuture.get()
      bindCamera(provider, lifecycleOwner)
    }, ContextCompat.getMainExecutor(appContext))
  }

  private fun bindCamera(provider: ProcessCameraProvider, lifecycleOwner: LifecycleOwner) {
    val preview = Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) }
    analyzer = ImageAnalysis.Builder()
      .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
      .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
      .build()
      .also { it.setAnalyzer(cameraExecutor) { image -> runFaceMesh(image) } }

    provider.unbindAll()
    provider.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_FRONT_CAMERA, preview, analyzer)
    cameraProvider = provider
    eventSink?.success(mapOf("type" to "ready"))
  }

  private fun stopCamera() { cameraProvider?.unbindAll(); analyzer?.clearAnalyzer(); cameraProvider = null }
  private fun hasCameraPermission() = ContextCompat.checkSelfPermission(appContext, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

  private fun ensureLandmarker(): Boolean {
    if (faceLandmarker != null) return true
    return try {
      val baseOptions = BaseOptions.builder().setModelAssetPath("face_landmarker.task").build()
      val options = FaceLandmarker.FaceLandmarkerOptions.builder()
        .setBaseOptions(baseOptions)
        .setRunningMode(RunningMode.IMAGE)
        .setNumFaces(1)
        .build()
      faceLandmarker = FaceLandmarker.createFromOptions(appContext, options)
      true
    } catch (t: Throwable) { Log.e("LipRenderer", "Landmarker fail", t); false }
  }

  private fun runFaceMesh(image: ImageProxy) {
    if (processing) { image.close(); return }
    processing = true

    val width = image.width
    val height = image.height
    if (rgbaBitmap == null || rgbaBitmap?.width != width || rgbaBitmap?.height != height) {
      rgbaBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    }
    
    val plane = image.planes[0]
    rgbaBitmap?.copyPixelsFromBuffer(plane.buffer)
    val mpImage = BitmapImageBuilder(rgbaBitmap).build()
    
    val result = faceLandmarker?.detect(mpImage)
    val landmarks = result?.faceLandmarks()?.firstOrNull()

    if (landmarks != null) {
      val outerIdx = intArrayOf(61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 308, 324, 318, 402, 317, 14, 87, 178, 88)
      val innerIdx = intArrayOf(78, 95, 88, 178, 87, 14, 317, 402, 318, 324)
      
      val outer = outerIdx.map { PointF(landmarks[it].x(), landmarks[it].y()) }
      val inner = innerIdx.map { PointF(landmarks[it].x(), landmarks[it].y()) }

      glOverlay.setLandmarks(outer, inner, width, height, image.imageInfo.rotationDegrees)
    }
    
    processing = false
    image.close()
  }
}

private class LipMaskGLSurfaceView(context: Context) : GLSurfaceView(context) {
  private val renderer = LipMaskRenderer()
  init {
    setEGLContextClientVersion(2)
    setEGLConfigChooser(8, 8, 8, 8, 16, 8)
    setZOrderOnTop(true)
    holder.setFormat(android.graphics.PixelFormat.TRANSLUCENT)
    setRenderer(renderer)
    renderMode = RENDERMODE_CONTINUOUSLY
  }
  fun setEffect(s: Int, i: Float) = queueEvent { renderer.updateColor(s, i) }
  fun setShowLandmarks(s: Boolean) = queueEvent { renderer.showLandmarks = s }
  fun setLandmarks(o: List<PointF>, i: List<PointF>, iw: Int, ih: Int, r: Int) = 
    queueEvent { renderer.updateGeometry(o, i, iw.toFloat(), ih.toFloat(), width.toFloat(), height.toFloat(), r) }
}

private class LipMaskRenderer : GLSurfaceView.Renderer {
  private var program = 0
  private var colorHandle = 0
  private var posHandle = 0
  private var outerBuf: java.nio.FloatBuffer? = null
  private var innerBuf: java.nio.FloatBuffer? = null
  private var outerCount = 0
  private var innerCount = 0
  
  @Volatile var showLandmarks = false
  @Volatile private var color = floatArrayOf(1f, 0f, 0f, 0.5f)

  override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
    GLES20.glEnable(GLES20.GL_BLEND)
    GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
    program = GLES20.glCreateProgram().also {
      val v = GLES20.glCreateShader(GLES20.GL_VERTEX_SHADER).apply { GLES20.glShaderSource(this, VERT); GLES20.glCompileShader(this) }
      val f = GLES20.glCreateShader(GLES20.GL_FRAGMENT_SHADER).apply { GLES20.glShaderSource(this, FRAG); GLES20.glCompileShader(this) }
      GLES20.glAttachShader(it, v); GLES20.glAttachShader(it, f); GLES20.glLinkProgram(it)
    }
    posHandle = GLES20.glGetAttribLocation(program, "aPos")
    colorHandle = GLES20.glGetUniformLocation(program, "uColor")
  }

  override fun onSurfaceChanged(gl: GL10?, w: Int, h: Int) = GLES20.glViewport(0, 0, w, h)

  override fun onDrawFrame(gl: GL10?) {
    GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_STENCIL_BUFFER_BIT)
    val outer = outerBuf ?: return
    if (outerCount < 3) return

    GLES20.glUseProgram(program)
    GLES20.glUniform4fv(colorHandle, 1, color, 0)
    GLES20.glEnable(GLES20.GL_STENCIL_TEST)
    
    // Pass 1: Stencil outer
    GLES20.glColorMask(false, false, false, false)
    GLES20.glStencilFunc(GLES20.GL_ALWAYS, 1, 0xFF)
    GLES20.glStencilOp(GLES20.GL_KEEP, GLES20.GL_KEEP, GLES20.GL_REPLACE)
    draw(outer, outerCount)

    // Pass 2: Clear inner
    innerBuf?.let { GLES20.glStencilFunc(GLES20.GL_ALWAYS, 0, 0xFF); draw(it, innerCount) }

    // Pass 3: Draw Color
    GLES20.glColorMask(true, true, true, true)
    GLES20.glStencilFunc(GLES20.GL_EQUAL, 1, 0xFF)
    draw(outer, outerCount)
    GLES20.glDisable(GLES20.GL_STENCIL_TEST)
  }

  fun updateColor(s: Int, i: Float) {
    color[0] = Color.red(s) / 255f; color[1] = Color.green(s) / 255f; color[2] = Color.blue(s) / 255f
    color[3] = (0.6f * i).coerceIn(0f, 0.8f) // Lower opacity for realistic skin preservation
  }

  fun updateGeometry(o: List<PointF>, i: List<PointF>, iw: Float, ih: Float, vw: Float, vh: Float, r: Int) {
    outerBuf = build(o, iw, ih, vw, vh, r); outerCount = o.size
    innerBuf = build(i, iw, ih, vw, vh, r); innerCount = i.size
  }

  private fun draw(b: java.nio.FloatBuffer, c: Int) {
    GLES20.glEnableVertexAttribArray(posHandle)
    GLES20.glVertexAttribPointer(posHandle, 2, GLES20.GL_FLOAT, false, 0, b)
    GLES20.glDrawArrays(GLES20.GL_TRIANGLE_FAN, 0, c)
  }

  private fun build(pts: List<PointF>, iw: Float, ih: Float, vw: Float, vh: Float, r: Int): java.nio.FloatBuffer {
    val rot = (r + 360) % 360
    val (rw, rh) = if (rot % 180 == 0) iw to ih else ih to iw
    val iAsp = rw / rh
    val vAsp = vw / vh
    
    // Corrected FILL_CENTER logic to match PreviewView
    val sc: Float
    val dx: Float
    val dy: Float
    if (vAsp > iAsp) { sc = vw / rw; dx = 0f; dy = (vh - rh * sc) / 2f }
    else { sc = vh / rh; dy = 0f; dx = (vw - rw * sc) / 2f }

    val arr = FloatArray(pts.size * 2)
    for (idx in pts.indices) {
      val p = pts[idx]
      // Proper rotation for front camera sensor (usually 270)
      val (tx, ty) = when (rot) {
        90 -> 1f - p.y to p.x
        180 -> 1f - p.x to 1f - p.y
        270 -> p.y to 1f - p.x // Classic Portrait Front Camera mapping
        else -> p.x to p.y
      }
      val fx = 1f - tx // Mirror X for front camera
      val px = dx + fx * rw * sc
      val py = dy + ty * rh * sc
      arr[idx * 2] = (px / vw) * 2f - 1f
      arr[idx * 2 + 1] = 1f - (py / vh) * 2f
    }
    return ByteBuffer.allocateDirect(arr.size * 4).order(java.nio.ByteOrder.nativeOrder()).asFloatBuffer().apply { put(arr); position(0) }
  }

  companion object {
    private const val VERT = "attribute vec2 aPos; void main() { gl_Position = vec4(aPos, 0.0, 1.0); }"
    // Realistic Shader: Simulates 'Soft Light' and adding a subtle lip highlight
    private const val FRAG = """
      precision mediump float;
      uniform vec4 uColor;
      void main() {
        // High-end apps use 'Soft Light' blending. 
        // Since we can't sample background easily here, we use a gradient to mimic depth.
        float d = distance(gl_FragCoord.xy / 1000.0, vec2(0.5, 0.5));
        float highlight = smoothstep(0.4, 0.0, d) * 0.15;
        gl_FragColor = vec4(uColor.rgb + highlight, uColor.a);
      }
    """
  }
}
