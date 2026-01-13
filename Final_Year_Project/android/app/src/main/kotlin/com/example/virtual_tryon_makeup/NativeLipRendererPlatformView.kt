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

private const val VIEW_TYPE = "native_lip_renderer/view"
private const val CHANNEL_PREFIX = "native_lip_renderer"
private const val CAMERA_PERMISSION_REQUEST = 9001
private const val DEFAULT_OVERLAY_SCALE = 1.0f
private const val DEFAULT_OVERLAY_OFFSET_X = 0.0f // positive => right
private const val DEFAULT_OVERLAY_OFFSET_Y = 0.0f // positive => down

/** Registers the PlatformView factory and keeps a reference to the host Activity. */
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
    val f = factory
    f?.handlePermissionResult(granted)
    return f != null
  }
}

private class LipRendererFactory(
  private val messenger: BinaryMessenger,
  private val appContext: Context
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

  @Volatile
  private var activity: Activity? = null
  @Volatile
  private var lastView: LipRendererPlatformView? = null

  fun bindActivity(activity: Activity) {
    this.activity = activity
  }

  fun unbindActivity() {
    this.activity = null
  }

  fun dispose() {
    unbindActivity()
  }

  override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
    val view = LipRendererPlatformView(
      appContext = appContext,
      activity = activity,
      messenger = messenger,
      viewId = viewId,
    )
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
  private var camera: Camera? = null
  private var analyzer: ImageAnalysis? = null
  private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
  private var eventSink: EventChannel.EventSink? = null
  private var startRequested = false

  private var frameCount = 0
  private var lastFpsSampleNs = 0L
  private var faceLandmarker: FaceLandmarker? = null
  @Volatile private var processing = false
  private var rgbaBitmap: Bitmap? = null
  @Volatile private var overlayScale = DEFAULT_OVERLAY_SCALE
  @Volatile private var overlayOffsetX = DEFAULT_OVERLAY_OFFSET_X
  @Volatile private var overlayOffsetY = DEFAULT_OVERLAY_OFFSET_Y
  @Volatile private var mirrorX = true

  init {
    methodChannel.setMethodCallHandler(this)
    eventChannel.setStreamHandler(this)

    previewView.scaleType = PreviewView.ScaleType.FILL_CENTER
    previewView.implementationMode = PreviewView.ImplementationMode.PERFORMANCE

    container.addView(
      previewView,
      FrameLayout.LayoutParams(
        FrameLayout.LayoutParams.MATCH_PARENT,
        FrameLayout.LayoutParams.MATCH_PARENT
      )
    )
    container.addView(
      glOverlay,
      FrameLayout.LayoutParams(
        FrameLayout.LayoutParams.MATCH_PARENT,
        FrameLayout.LayoutParams.MATCH_PARENT
      )
    )
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
      "start" -> {
        startRequested = true
        startCameraIfReady()
        result.success(null)
      }
      "stop" -> {
        startRequested = false
        stopCamera()
        result.success(null)
      }
      "setEffect" -> {
        val args = call.arguments as? Map<*, *>
        val shade = (args?.get("shade") as? Number)?.toInt()
        val intensity = (args?.get("intensity") as? Number)?.toFloat()
        if (shade != null && intensity != null) {
          glOverlay.setEffect(shade, intensity)
        }
        result.success(null)
      }
      "setDebug" -> {
        val args = call.arguments as? Map<*, *>
        val showLandmarks = args?.get("showLandmarks") as? Boolean ?: false
        glOverlay.setShowLandmarks(showLandmarks)
        result.success(null)
      }
      "setCalibration" -> {
        val args = call.arguments as? Map<*, *>
        overlayScale = (args?.get("scale") as? Number)?.toFloat() ?: overlayScale
        overlayOffsetX = (args?.get("offsetX") as? Number)?.toFloat() ?: overlayOffsetX
        overlayOffsetY = (args?.get("offsetY") as? Number)?.toFloat() ?: overlayOffsetY
        mirrorX = args?.get("mirrorX") as? Boolean ?: mirrorX
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
    if (startRequested) {
      startCameraIfReady()
    }
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  fun onPermissionResult(granted: Boolean) {
    if (granted) {
      startCameraIfReady()
    } else {
      sendError("permission", "Camera permission denied.")
    }
  }

  private fun startCameraIfReady() {
    val lifecycleOwner = (activity as? LifecycleOwner)
    if (!startRequested) return
    if (activity == null || lifecycleOwner == null) {
      sendError("no_activity", "Activity is not attached; cannot start camera.")
      return
    }
    if (!ensureLandmarker()) {
      sendError("landmarker", "Failed to load face landmarker.")
      return
    }
    if (!hasCameraPermission()) {
      requestCameraPermission()
      sendError("permission", "Camera permission not granted.")
      return
    }
    val providerFuture = ProcessCameraProvider.getInstance(appContext)
    providerFuture.addListener(
      {
        try {
          val provider = providerFuture.get()
          bindCamera(provider, lifecycleOwner)
        } catch (t: Throwable) {
          sendError("camera_provider", "Failed to start camera: ${t.message}")
          Log.e("NativeLipRenderer", "Failed to start camera", t)
        }
      },
      ContextCompat.getMainExecutor(appContext)
    )
  }

  @MainThread
  private fun bindCamera(provider: ProcessCameraProvider, lifecycleOwner: LifecycleOwner) {
    val preview = Preview.Builder()
      .build()
      .also { it.setSurfaceProvider(previewView.surfaceProvider) }

    analyzer = ImageAnalysis.Builder()
      .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
      .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
      .build()
      .also { analysis ->
        analysis.setAnalyzer(cameraExecutor) { image ->
          try {
            sampleFps()
            runFaceMesh(image)
          } catch (t: Throwable) {
            sendError("analyzer", "Analyzer failure: ${t.message}")
          } finally {
            image.close()
          }
        }
      }

    provider.unbindAll()
    camera = provider.bindToLifecycle(
      lifecycleOwner,
      CameraSelector.DEFAULT_FRONT_CAMERA,
      preview,
      analyzer
    )
    cameraProvider = provider
    sendReady()
  }

  private fun stopCamera() {
    try {
      cameraProvider?.unbindAll()
      analyzer?.clearAnalyzer()
      cameraProvider = null
    } catch (t: Throwable) {
      Log.w("NativeLipRenderer", "stopCamera failed", t)
    }
  }

  private fun hasCameraPermission(): Boolean {
    return ContextCompat.checkSelfPermission(
      appContext,
      Manifest.permission.CAMERA
    ) == PackageManager.PERMISSION_GRANTED
  }

  private fun requestCameraPermission() {
    val hostActivity = activity ?: return
    ActivityCompat.requestPermissions(
      hostActivity,
      arrayOf(Manifest.permission.CAMERA),
      CAMERA_PERMISSION_REQUEST
    )
  }

  private fun sampleFps() {
    frameCount += 1
    val nowNs = System.nanoTime()
    if (lastFpsSampleNs == 0L) {
      lastFpsSampleNs = nowNs
      return
    }
    val elapsedMs = (nowNs - lastFpsSampleNs) / 1_000_000
    if (elapsedMs > 750) {
      val fps = frameCount * 1000f / elapsedMs
      sendEvent(mapOf("type" to "fps", "value" to fps))
      frameCount = 0
      lastFpsSampleNs = nowNs
    }
  }

  private fun sendReady() {
    sendEvent(mapOf("type" to "ready"))
  }

  private fun sendError(code: String, message: String) {
    sendEvent(mapOf("type" to "error", "code" to code, "message" to message))
  }

  private fun sendEvent(payload: Map<String, Any>) {
    val sink = eventSink ?: return
    ContextCompat.getMainExecutor(appContext).execute {
      sink.success(payload)
    }
  }

  private fun ensureLandmarker(): Boolean {
    if (faceLandmarker != null) {
      Log.d("NativeLipRenderer", "✅ FaceLandmarker already initialized")
      return true
    }
    
    Log.d("NativeLipRenderer", "🔧 Initializing MediaPipe FaceLandmarker...")
    return try {
      val baseOptions = BaseOptions.builder()
        .setModelAssetPath("face_landmarker.task")
        .build()
      Log.d("NativeLipRenderer", "📦 Model path set: face_landmarker.task")
      
      val options = FaceLandmarker.FaceLandmarkerOptions.builder()
        .setBaseOptions(baseOptions)
        .setRunningMode(RunningMode.IMAGE)
        .setNumFaces(1)
        .setMinFaceDetectionConfidence(0.3f)  // Lower threshold for better detection
        .setMinFacePresenceConfidence(0.3f)   // Lower threshold
        .setMinTrackingConfidence(0.3f)       // Lower threshold
        .build()
      Log.d("NativeLipRenderer", "⚙️ Options: IMAGE mode, numFaces=1, confidence=0.3")
      
      faceLandmarker = FaceLandmarker.createFromOptions(appContext, options)
      Log.d("NativeLipRenderer", "✅ FaceLandmarker created successfully!")
      true
    } catch (t: Throwable) {
      Log.e("NativeLipRenderer", "❌ Failed to load FaceLandmarker", t)
      Log.e("NativeLipRenderer", "Error details: ${t.javaClass.simpleName}: ${t.message}")
      false
    }
  }

  private fun runFaceMesh(image: ImageProxy) {
    if (processing) return
    processing = true
    
    Log.d("NativeLipRenderer", "🔍 runFaceMesh START - processing frame")
    
    val planes = image.planes
    if (planes.isEmpty()) {
      Log.e("NativeLipRenderer", "❌ No image planes available")
      processing = false
      return
    }

    val width = image.width
    val height = image.height
    Log.d("NativeLipRenderer", "📐 Image size: ${width}x${height}")
    
    val plane = planes[0]
    val rowStride = plane.rowStride
    val pixelStride = plane.pixelStride
    val buffer = plane.buffer
    buffer.rewind()

    Log.d("NativeLipRenderer", "📊 Plane info: rowStride=$rowStride, pixelStride=$pixelStride, buffer remaining=${buffer.remaining()}")

    if (rgbaBitmap == null || rgbaBitmap?.width != width || rgbaBitmap?.height != height) {
      rgbaBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
      Log.d("NativeLipRenderer", "🖼️ Created new bitmap: ${width}x${height}")
    }
    val target = rgbaBitmap!!

    if (rowStride == width * 4 && pixelStride == 4) {
      target.copyPixelsFromBuffer(buffer)
      Log.d("NativeLipRenderer", "✅ Direct buffer copy (optimal path)")
    } else {
      Log.d("NativeLipRenderer", "⚠️ Using manual copy (stride mismatch)")
      val data = ByteArray(width * height * 4)
      var offset = 0
      val rowData = ByteArray(rowStride)
      for (y in 0 until height) {
        buffer.position(y * rowStride)
        buffer.get(rowData, 0, rowStride.coerceAtMost(buffer.remaining()))
        var x = 0
        while (x < width) {
          val i = x * pixelStride
          if (i + 3 < rowData.size) {
            data[offset] = rowData[i]
            data[offset + 1] = rowData[i + 1]
            data[offset + 2] = rowData[i + 2]
            data[offset + 3] = rowData[i + 3]
          }
          offset += 4
          x++
        }
      }
      target.copyPixelsFromBuffer(ByteBuffer.wrap(data))
    }

    Log.d("NativeLipRenderer", "🎨 Bitmap prepared, creating MPImage")
    val mpImage: MPImage = BitmapImageBuilder(target).build()
    
    Log.d("NativeLipRenderer", "🔬 Calling MediaPipe FaceLandmarker.detect()")
    val result: FaceLandmarkerResult? = try {
      faceLandmarker?.detect(
        mpImage,
        ImageProcessingOptions.builder()
          .setRotationDegrees(0) // handle rotation in renderer mapping
          .build()
      )
    } catch (t: Throwable) {
      Log.e("NativeLipRenderer", "❌ MediaPipe detect() failed: ${t.message}", t)
      null
    }

    if (result == null) {
      Log.e("NativeLipRenderer", "❌ Detection result is NULL")
      processing = false
      return
    }

    val faceLandmarks = result.faceLandmarks()
    Log.d("NativeLipRenderer", "📋 Detection complete. Face count: ${faceLandmarks.size}")
    
    val landmarks = faceLandmarks.firstOrNull()
    if (landmarks == null) {
      Log.w("NativeLipRenderer", "⚠️ No face landmarks detected (empty list)")
      processing = false
      return
    }

    Log.d("NativeLipRenderer", "✅ Face landmarks detected! Landmark count: ${landmarks.size}")

    val outerIdx = intArrayOf(
      61, 146, 91, 181, 84, 17,
      314, 405, 321, 375, 291, 308,
      324, 318, 402, 317, 14, 87,
      178, 88
    )
    val innerIdx = intArrayOf(
      78, 95, 88, 178, 87, 14,
      317, 402, 318, 324
    )

    val outerPts = mutableListOf<PointF>()
    for (i in outerIdx) {
      if (i < landmarks.size) {
        val lm = landmarks[i]
        outerPts.add(PointF(lm.x(), lm.y()))
      }
    }
    val innerPts = mutableListOf<PointF>()
    for (i in innerIdx) {
      if (i < landmarks.size) {
        val lm = landmarks[i]
        innerPts.add(PointF(lm.x(), lm.y()))
      }
    }

    Log.d("NativeLipRenderer", "👄 Extracted lip points: outer=${outerPts.size}, inner=${innerPts.size}")

    glOverlay.post {
      glOverlay.setLandmarks(
        outerPts,
        innerPts,
        width,
        height,
        image.imageInfo.rotationDegrees,
        overlayScale,
        overlayOffsetX,
        overlayOffsetY,
        mirrorX
      )
    }

    Log.d("NativeLipRenderer", "✅ runFaceMesh COMPLETE - landmarks sent to renderer")
    processing = false
  }
}

private class LipMaskGLSurfaceView(context: Context) : GLSurfaceView(context) {
  private val renderer = LipMaskRenderer()

  init {
    setEGLContextClientVersion(2)
    // RGBA + depth + stencil for punched-out inner mouth
    setEGLConfigChooser(8, 8, 8, 8, 16, 8)
    setZOrderOnTop(true)
    holder.setFormat(android.graphics.PixelFormat.TRANSLUCENT)
    setRenderer(renderer)
    renderMode = RENDERMODE_CONTINUOUSLY
  }

  fun setEffect(shade: Int, intensity: Float) {
    queueEvent { renderer.updateColor(shade, intensity) }
  }

  fun setShowLandmarks(show: Boolean) {
    queueEvent { renderer.showLandmarks = show }
  }

  fun setLandmarks(
    outer: List<PointF>,
    inner: List<PointF>,
    imageWidth: Int,
    imageHeight: Int,
    rotationDegrees: Int,
    scale: Float,
    offsetX: Float,
    offsetY: Float,
    mirrorX: Boolean
  ) {
    val viewW = width.takeIf { it > 0 } ?: this.width
    val viewH = height.takeIf { it > 0 } ?: this.height
    queueEvent {
      renderer.updateGeometry(
        outer,
        inner,
        imageWidth.toFloat(),
        imageHeight.toFloat(),
        viewW.toFloat(),
        viewH.toFloat(),
        rotationDegrees,
        scale,
        offsetX,
        offsetY,
        mirrorX
      )
    }
  }
}

private class LipMaskRenderer : GLSurfaceView.Renderer {
  private var program = 0
  private var positionHandle = 0
  private var colorHandle = 0
  private var outerBuffer: java.nio.FloatBuffer? = null
  private var innerBuffer: java.nio.FloatBuffer? = null
  private var outerCount = 0
  private var innerCount = 0

  @Volatile var showLandmarks = false
  @Volatile private var color = floatArrayOf(1f, 0f, 0f, 0.55f)

  override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
    GLES20.glClearColor(0f, 0f, 0f, 0f)
    GLES20.glEnable(GLES20.GL_BLEND)
    GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
    program = buildProgram(VERT_SRC, FRAG_SRC)
    positionHandle = GLES20.glGetAttribLocation(program, "aPosition")
    colorHandle = GLES20.glGetUniformLocation(program, "uColor")
  }

  override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
    GLES20.glViewport(0, 0, width, height)
  }

  override fun onDrawFrame(gl: GL10?) {
    GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
    val outer = outerBuffer ?: return
    if (outerCount < 3) return

    GLES20.glUseProgram(program)
    GLES20.glUniform4fv(colorHandle, 1, color, 0)

    // Stencil pass: mark outer (1), clear inner (0)
    GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT or GLES20.GL_STENCIL_BUFFER_BIT)
    GLES20.glEnable(GLES20.GL_STENCIL_TEST)
    GLES20.glColorMask(false, false, false, false)

    GLES20.glStencilFunc(GLES20.GL_ALWAYS, 1, 0xFF)
    GLES20.glStencilOp(GLES20.GL_KEEP, GLES20.GL_KEEP, GLES20.GL_REPLACE)
    drawFan(outer, outerCount)

    val inner = innerBuffer
    if (inner != null && innerCount >= 3) {
      GLES20.glStencilFunc(GLES20.GL_ALWAYS, 0, 0xFF)
      GLES20.glStencilOp(GLES20.GL_KEEP, GLES20.GL_KEEP, GLES20.GL_REPLACE)
      drawFan(inner, innerCount)
    }

    // Color pass only where stencil == 1
    GLES20.glColorMask(true, true, true, true)
    GLES20.glStencilFunc(GLES20.GL_EQUAL, 1, 0xFF)
    GLES20.glStencilOp(GLES20.GL_KEEP, GLES20.GL_KEEP, GLES20.GL_KEEP)
    drawFan(outer, outerCount)

    GLES20.glDisable(GLES20.GL_STENCIL_TEST)
  }

  fun updateColor(shade: Int, intensity: Float) {
    val a = (0.55f * intensity.coerceIn(0f, 1f)).coerceIn(0f, 0.8f)
    color[0] = ((shade shr 16) and 0xFF) / 255f
    color[1] = ((shade shr 8) and 0xFF) / 255f
    color[2] = (shade and 0xFF) / 255f
    color[3] = a
    
    // DEBUG: Log color updates
    android.util.Log.d("NativeLipRenderer", 
      "updateColor: shade=0x${shade.toString(16).padStart(8, '0')}, intensity=$intensity, " +
      "rgba=(${color[0]}, ${color[1]}, ${color[2]}, ${color[3]})")
  }

  fun updateGeometry(
    outer: List<PointF>,
    inner: List<PointF>,
    imageW: Float,
    imageH: Float,
    viewW: Float,
    viewH: Float,
    rotationDeg: Int,
    scale: Float,
    offsetX: Float,
    offsetY: Float,
    mirrorX: Boolean
  ) {
    outerBuffer = buildFan(outer, imageW, imageH, viewW, viewH, rotationDeg, scale, offsetX, offsetY, mirrorX)
    innerBuffer = buildFan(inner, imageW, imageH, viewW, viewH, rotationDeg, scale, offsetX, offsetY, mirrorX)
    outerCount = outerBuffer?.capacity()?.div(2) ?: 0
    innerCount = innerBuffer?.capacity()?.div(2) ?: 0
    
    // DEBUG: Log geometry updates
    android.util.Log.d("NativeLipRenderer",
      "updateGeometry: outer=$outerCount points, inner=$innerCount points, " +
      "rotation=$rotationDeg, scale=$scale, offset=($offsetX,$offsetY), mirror=$mirrorX")
  }

  private fun drawFan(buf: java.nio.FloatBuffer, count: Int) {
    GLES20.glEnableVertexAttribArray(positionHandle)
    GLES20.glVertexAttribPointer(positionHandle, 2, GLES20.GL_FLOAT, false, 0, buf)
    GLES20.glDrawArrays(GLES20.GL_TRIANGLE_FAN, 0, count)
    GLES20.glDisableVertexAttribArray(positionHandle)
  }

  private fun buildFan(
    points: List<PointF>,
    imageW: Float,
    imageH: Float,
    viewW: Float,
    viewH: Float,
    rotationDeg: Int,
    scale: Float,
    offsetX: Float,
    offsetY: Float,
    mirrorX: Boolean
  ): java.nio.FloatBuffer? {
    if (points.size < 3) return null
    // Fit-center mapping to match PreviewView fill-center behavior, with rotation applied.
    val rot = ((rotationDeg % 360) + 360) % 360
    val rotatedW = if (rot % 180 == 0) imageW else imageH
    val rotatedH = if (rot % 180 == 0) imageH else imageW
    val imgAspect = rotatedW / rotatedH
    val viewAspect = viewW / viewH
    val drawW: Float
    val drawH: Float
    val dx: Float
    val dy: Float
    if (viewAspect > imgAspect) {
      drawH = viewH
      drawW = drawH * imgAspect
      dx = (viewW - drawW) / 2f
      dy = 0f
    } else {
      drawW = viewW
      drawH = drawW / imgAspect
      dx = 0f
      dy = (viewH - drawH) / 2f
    }

    val arr = FloatArray(points.size * 2)
    for (i in points.indices) {
      val p = points[i]
      // Apply rotation transformation - FIXED for portrait front camera
      val (tx, ty) = when (rot) {
        90 -> Pair(1f - p.y, p.x)
        180 -> Pair(1f - p.x, 1f - p.y)
        270 -> Pair(p.y, 1f - p.x)  // CORRECTED: x_new = y, y_new = 1-x
        else -> Pair(p.x, p.y)
      }
      val rx = if (mirrorX) 1f - tx else tx
      val ry = ty
      val px = dx + (rx - 0.5f) * scale * drawW + drawW * 0.5f + offsetX * drawW
      val py = dy + (ry - 0.5f) * scale * drawH + drawH * 0.5f + offsetY * drawH
      arr[i * 2] = (px / viewW) * 2f - 1f
      arr[i * 2 + 1] = 1f - (py / viewH) * 2f
    }
    return java.nio.ByteBuffer.allocateDirect(arr.size * 4)
      .order(java.nio.ByteOrder.nativeOrder())
      .asFloatBuffer()
      .apply {
        put(arr)
        position(0)
      }
  }

  private fun buildProgram(vs: String, fs: String): Int {
    val v = compileShader(GLES20.GL_VERTEX_SHADER, vs)
    val f = compileShader(GLES20.GL_FRAGMENT_SHADER, fs)
    val program = GLES20.glCreateProgram()
    GLES20.glAttachShader(program, v)
    GLES20.glAttachShader(program, f)
    GLES20.glLinkProgram(program)
    return program
  }

  private fun compileShader(type: Int, source: String): Int {
    val shader = GLES20.glCreateShader(type)
    GLES20.glShaderSource(shader, source)
    GLES20.glCompileShader(shader)
    return shader
  }

  companion object {
    private const val VERT_SRC = """
      attribute vec2 aPosition;
      void main() {
        gl_Position = vec4(aPosition, 0.0, 1.0);
      }
    """
    private const val FRAG_SRC = """
      precision mediump float;
      uniform vec4 uColor;
      void main() {
        gl_FragColor = uColor;
      }
    """
  }
}
