package com.example.virtual_tryon_makeup

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import androidx.annotation.MainThread
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.graphics.ColorUtils
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
import com.google.mediapipe.framework.image.ByteBufferExtractor
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenter
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenterResult
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult
import java.io.ByteArrayOutputStream
import java.io.FileInputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.sqrt
import org.tensorflow.lite.Interpreter

private const val VIEW_TYPE = "native_lip_renderer/view"
private const val CHANNEL_PREFIX = "native_lip_renderer"
private const val HAND_STATIC_CHANNEL = "la_vogue_vista/hand_landmarker"
private const val CAMERA_PERMISSION_REQUEST = 9001

private fun handTipsNormalizedFromResult(result: HandLandmarkerResult?): List<Map<String, Double>> {
  if (result == null) return emptyList()
  val hands = result.landmarks()
  if (hands.isEmpty()) return emptyList()
  var bestIdx = 0
  var bestArea = 0f
  for (idx in hands.indices) {
    val lm = hands[idx]
    if (lm.isEmpty()) continue
    var minX = 1f
    var maxX = 0f
    var minY = 1f
    var maxY = 0f
    for (p in lm) {
      minX = min(minX, p.x())
      maxX = max(maxX, p.x())
      minY = min(minY, p.y())
      maxY = max(maxY, p.y())
    }
    val area = (maxX - minX) * (maxY - minY)
    if (area > bestArea) {
      bestArea = area
      bestIdx = idx
    }
  }
  val lm = hands[bestIdx]
  if (lm.size < 21) return emptyList()
  val tipIdx = intArrayOf(4, 8, 12, 16, 20)
  val dipIdx = intArrayOf(3, 7, 11, 15, 19)
  val out = ArrayList<Map<String, Double>>(5)
  for (i in 0 until tipIdx.size) {
    val t = lm[tipIdx[i]]
    val p = lm[dipIdx[i]]
    val dx = t.x() - p.x()
    val dy = t.y() - p.y()
    val dist = sqrt((dx * dx + dy * dy).toDouble()).coerceAtLeast(1e-4).toFloat()
    val ang = atan2(dy.toDouble(), dx.toDouble())
    // Shift toward free edge of nail (landmark sits slightly in from visible nail plate).
    val nudge = 0.18f
    val nx = (t.x() + (dx / dist) * dist * nudge).coerceIn(0.02f, 0.98f)
    val ny = (t.y() + (dy / dist) * dist * nudge).coerceIn(0.02f, 0.98f)
    out.add(
      mapOf(
        "nx" to nx.toDouble(),
        "ny" to ny.toDouble(),
        "r" to dist.toDouble(),
        "angle" to ang
      )
    )
  }
  return out
}

class NativeLipRendererPlatformViewPlugin : FlutterPlugin, ActivityAware,
  PluginRegistry.RequestPermissionsResultListener {
  private var pluginBinding: FlutterPlugin.FlutterPluginBinding? = null
  private var activityBinding: ActivityPluginBinding? = null
  private var factory: LipRendererFactory? = null
  private var handStaticChannel: MethodChannel? = null
  private val handStaticExecutor = Executors.newSingleThreadExecutor()
  @Volatile private var staticHandLandmarker: HandLandmarker? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    pluginBinding = binding
    val viewFactory = LipRendererFactory(binding.binaryMessenger, binding.applicationContext)
    factory = viewFactory
    binding.platformViewRegistry.registerViewFactory(VIEW_TYPE, viewFactory)

    handStaticChannel = MethodChannel(binding.binaryMessenger, HAND_STATIC_CHANNEL).also { ch ->
      ch.setMethodCallHandler { call, result ->
        if (call.method != "detectTips") {
          result.notImplemented()
          return@setMethodCallHandler
        }
        val path = call.argument<String>("path")
        if (path.isNullOrEmpty()) {
          result.error("bad_arg", "missing path", null)
          return@setMethodCallHandler
        }
        val ctx = binding.applicationContext
        handStaticExecutor.execute {
          try {
            if (staticHandLandmarker == null) {
              val base = BaseOptions.builder()
                .setModelAssetPath("flutter_assets/assets/models/hand_landmarker.task")
                .build()
              val opts = HandLandmarker.HandLandmarkerOptions.builder()
                .setBaseOptions(base)
                .setRunningMode(RunningMode.IMAGE)
                .setNumHands(2)
                .setMinHandDetectionConfidence(0.35f)
                .setMinHandPresenceConfidence(0.45f)
                .setMinTrackingConfidence(0.45f)
                .build()
              staticHandLandmarker = HandLandmarker.createFromOptions(ctx, opts)
            }
            val bmp = android.graphics.BitmapFactory.decodeFile(path)
              ?: run {
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                  result.error("decode", "Could not decode image", null)
                }
                return@execute
              }
            val mpImg = BitmapImageBuilder(bmp).build()
            val hResult = staticHandLandmarker!!.detect(mpImg)
            val tips = handTipsNormalizedFromResult(hResult)
            android.os.Handler(android.os.Looper.getMainLooper()).post {
              result.success(tips)
            }
          } catch (e: Throwable) {
            Log.e("HandStatic", "detectTips", e)
            android.os.Handler(android.os.Looper.getMainLooper()).post {
              result.error("hand", e.message, null)
            }
          }
        }
      }
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    handStaticChannel?.setMethodCallHandler(null)
    handStaticChannel = null
    handStaticExecutor.execute {
      staticHandLandmarker?.close()
      staticHandLandmarker = null
    }
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

// ─── Hair mask overlay (Canvas-based, 4th layer in container) ─────────────────
private class HairMaskOverlayView(context: Context) : View(context) {
  private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
  private var hairBitmap: Bitmap? = null

  fun drawHairMask(bmp: Bitmap?) { hairBitmap = bmp; postInvalidate() }
  fun clear() { hairBitmap = null; postInvalidate() }

  override fun onDraw(canvas: Canvas) {
    val bmp = hairBitmap ?: return
    canvas.drawBitmap(bmp, null, RectF(0f, 0f, width.toFloat(), height.toFloat()), paint)
  }
}

// Shared by NailPolishRenderer and LipRendererPlatformView (hair / photo paths).
private fun rgbToHSL(r: Float, g: Float, b: Float): Triple<Float, Float, Float> {
  val maxC = max(max(r, g), b)
  val minC = min(min(r, g), b)
  val delta = maxC - minC
  val l = (maxC + minC) / 2f
  if (delta < 0.001f) return Triple(0f, 0f, l)
  val s = delta / (1f - kotlin.math.abs(2f * l - 1f))
  val h = when {
    maxC == r -> {
      var h0 = (g - b) / delta
      if (h0 < 0) h0 += 6f
      h0
    }
    maxC == g -> (b - r) / delta + 2f
    else -> (r - g) / delta + 4f
  }
  return Triple(h / 6f, s, l)
}

private fun hslToRGB(h: Float, s: Float, l: Float): Triple<Float, Float, Float> {
  if (s < 0.001f) return Triple(l, l, l)
  val c = (1f - kotlin.math.abs(2f * l - 1f)) * s
  val x = c * (1f - kotlin.math.abs(((h * 6f) % 2f) - 1f))
  val m = l - c / 2f
  val (r1, g1, b1) = when (((h * 6f).toInt()) % 6) {
    0 -> Triple(c, x, 0f)
    1 -> Triple(x, c, 0f)
    2 -> Triple(0f, c, x)
    3 -> Triple(0f, x, c)
    4 -> Triple(x, 0f, c)
    else -> Triple(c, 0f, x)
  }
  return Triple(
    (r1 + m).coerceIn(0f, 1f),
    (g1 + m).coerceIn(0f, 1f),
    (b1 + m).coerceIn(0f, 1f)
  )
}

// ─── TFLite nail-polish renderer ──────────────────────────────────────────────
// Loads the custom MobileNetV2-UNet nail_segmenter.tflite, runs it per-frame
// inside each fingertip ROI, assembles a full-screen ARGB mask, then blends
// the chosen polish colour using MULTIPLY so natural nail texture shows through.
private class NailPolishRenderer(private val context: Context) {

  companion object {
    private const val MODEL  = "nail_segmenter.tflite"
    private const val SIZE   = 224   // model input size
    private const val TAG    = "NailPolishRenderer"
  }

  private var interpreter: Interpreter? = null
  private val inputBuf: ByteBuffer = ByteBuffer
    .allocateDirect(4 * SIZE * SIZE * 3).order(ByteOrder.nativeOrder())
  private val outputBuf: ByteBuffer = ByteBuffer
    .allocateDirect(4 * SIZE * SIZE * 1).order(ByteOrder.nativeOrder())

  // ── Lazy-load the interpreter ────────────────────────────────────────────
  fun ensureLoaded(): Boolean {
    if (interpreter != null) return true
    return try {
      // Try multiple locations because Flutter assets live under `flutter_assets/…`.
      val candidates = listOf(
        MODEL,
        "assets/models/$MODEL",
        "flutter_assets/assets/models/$MODEL",
      )
      var mapped: MappedByteBuffer? = null

      for (p in candidates) {
        try {
          val afd = context.assets.openFd(p) // works only if asset is uncompressed
          val fis = FileInputStream(afd.fileDescriptor)
          val chan = fis.channel
          mapped = chan.map(FileChannel.MapMode.READ_ONLY, afd.startOffset, afd.declaredLength)
          fis.close()
          Log.i(TAG, "Loaded $MODEL from assets: $p")
          break
        } catch (_: Throwable) {
          // fall through: try stream copy path below
        }
      }

      if (mapped == null) {
        // Fallback: stream-copy compressed Flutter asset to a temp file, then mmap it.
        val tmp = File(context.cacheDir, MODEL)
        if (!tmp.exists() || tmp.length() < 16_384L) {
          var copied = false
          for (p in candidates) {
            try {
              context.assets.open(p).use { input ->
                FileOutputStream(tmp).use { output -> input.copyTo(output) }
              }
              Log.i(TAG, "Copied $MODEL from assets stream: $p → ${tmp.absolutePath}")
              copied = true
              break
            } catch (_: Throwable) {}
          }
          if (!copied) throw IllegalStateException("Could not find $MODEL in assets (tried: $candidates)")
        }
        val fis = FileInputStream(tmp)
        val chan = fis.channel
        mapped = chan.map(FileChannel.MapMode.READ_ONLY, 0, chan.size())
        fis.close()
      }

      val opts = Interpreter.Options().apply { numThreads = 2 }
      interpreter = Interpreter(mapped!!, opts)
      true
    } catch (t: Throwable) {
      Log.e(TAG, "Cannot load $MODEL — falling back to landmark ellipses", t)
      false
    }
  }

  fun close() {
    try { interpreter?.close() } catch (_: Throwable) {}
    interpreter = null
  }

  /**
   * Given the full-frame [srcBitmap] and a list of per-fingertip bounding boxes
   * (in view-pixels), runs segmentation on each ROI and paints the nail mask
   * onto a new full-screen ARGB bitmap.
   *
   * @param boxes  list of RectF in [0, viewW] × [0, viewH] pixel space
   * @param viewW  width of the PreviewView
   * @param viewH  height of the PreviewView
   * @param polishColor ARGB int, e.g. Color.RED
   * @param alpha  opacity 0–1
   * @param artStyle 0=solid 1=french 2=ombre 3=sparkle
   */
  fun renderNailMask(
    srcBitmap: Bitmap,
    boxes: List<RectF>,
    viewW: Int,
    viewH: Int,
    polishColor: Int,
    alpha: Float,
    artStyle: Int
  ): Bitmap? {
    val interp = interpreter ?: return null
    if (boxes.isEmpty()) return null

    val out = Bitmap.createBitmap(viewW, viewH, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(out)

    val polishA  = (alpha * 220).toInt().coerceIn(30, 230)
    val polishR  = Color.red(polishColor)
    val polishG  = Color.green(polishColor)
    val polishB  = Color.blue(polishColor)

    // Scale camera frame → view dimensions (cover mode)
    val scaleX = viewW.toFloat() / srcBitmap.width
    val scaleY = viewH.toFloat() / srcBitmap.height
    val scale  = max(scaleX, scaleY)
    val offX   = (viewW - srcBitmap.width  * scale) / 2f
    val offY   = (viewH - srcBitmap.height * scale) / 2f

    for (box in boxes) {
      // Convert view-space box → bitmap-space box
      val bx0 = ((box.left   - offX) / scale).coerceIn(0f, srcBitmap.width.toFloat())
      val by0 = ((box.top    - offY) / scale).coerceIn(0f, srcBitmap.height.toFloat())
      val bx1 = ((box.right  - offX) / scale).coerceIn(0f, srcBitmap.width.toFloat())
      val by1 = ((box.bottom - offY) / scale).coerceIn(0f, srcBitmap.height.toFloat())
      val bw  = (bx1 - bx0).toInt()
      val bh  = (by1 - by0).toInt()
      if (bw < 4 || bh < 4) continue

      // Crop ROI from camera frame
      val roi = Bitmap.createBitmap(srcBitmap, bx0.toInt(), by0.toInt(), bw, bh)
      val roiScaled = Bitmap.createScaledBitmap(roi, SIZE, SIZE, true)
      roi.recycle()

      // Fill input buffer (RGB float32 normalised 0–1)
      inputBuf.rewind()
      val pixels = IntArray(SIZE * SIZE)
      roiScaled.getPixels(pixels, 0, SIZE, 0, 0, SIZE, SIZE)
      roiScaled.recycle()
      for (px in pixels) {
        inputBuf.putFloat(Color.red(px)   / 255f)
        inputBuf.putFloat(Color.green(px) / 255f)
        inputBuf.putFloat(Color.blue(px)  / 255f)
      }
      inputBuf.rewind()
      outputBuf.rewind()

      // Run inference — using specific run call to avoid ambiguity
      outputBuf.rewind()
      try {
        interp.run(inputBuf as Any, outputBuf as Any)
      } catch (t: Throwable) { Log.w(TAG, "Inference error", t); continue }

      // Build a nail-coloured ARGB bitmap for this ROI at 224×224 using HSL blending
      val maskPixels = IntArray(SIZE * SIZE)
      
      val tR = Color.red(polishColor) / 255f
      val tG = Color.green(polishColor) / 255f
      val tB = Color.blue(polishColor) / 255f
      val (tgtH, tgtS, tgtL) = rgbToHSL(tR, tG, tB)

      for (j in maskPixels.indices) {
        val conf = outputBuf.float   // 0–1 (sigmoid output)
        if (conf < 0.45f) { maskPixels[j] = Color.TRANSPARENT; continue }
        
        val maskA = (conf * polishA).toInt().coerceIn(0, 255)
        
        // Sample original camera pixel for highlights
        val srcPixel = pixels[j]
        val srcR = Color.red(srcPixel) / 255f
        val srcG = Color.green(srcPixel) / 255f
        val srcB = Color.blue(srcPixel) / 255f
        val (_, srcS, srcL) = rgbToHSL(srcR, srcG, srcB)

        // Texture Preservation: lift original luminance to meet target
        val resultL = max(srcL, tgtL * 0.72f)
        val (outR, outG, outB) = hslToRGB(tgtH, tgtS, resultL)
        
        val finalCol = Color.rgb((outR * 255).toInt(), (outG * 255).toInt(), (outB * 255).toInt())

        maskPixels[j] = when (artStyle) {
          1 -> { // French: white tip on top 25%, colour on rest
            val row = j / SIZE
            if (row < SIZE / 4) Color.argb((maskA * 0.98f).toInt(), 248, 244, 240)
            else ColorUtils.setAlphaComponent(finalCol, (maskA * 0.7f).toInt())
          }
          2 -> { // Ombré: gradient from base to tip
            val row  = j / SIZE
            val frac = row.toFloat() / SIZE          // 0=top (tip), 1=base
            val a2   = (maskA * (0.25f + frac * 0.75f)).toInt().coerceIn(0, 255)
            ColorUtils.setAlphaComponent(finalCol, a2)
          }
          3 -> { // Sparkle: colour + random glitter dots (applied below)
            ColorUtils.setAlphaComponent(finalCol, (maskA * 0.75f).toInt())
          }
          else -> ColorUtils.setAlphaComponent(finalCol, maskA)
        }
      }

      val nailBmp = Bitmap.createBitmap(SIZE, SIZE, Bitmap.Config.ARGB_8888)
      nailBmp.setPixels(maskPixels, 0, SIZE, 0, 0, SIZE, SIZE)

      // Sparkle overlay
      if (artStyle == 3) {
        val sparkCanvas = Canvas(nailBmp)
        val sparkPaint  = Paint(Paint.ANTI_ALIAS_FLAG)
        var s = (box.centerX() * 23 + box.centerY() * 37).toLong()
        fun rnd(): Float { s = (s * 48271L) % 2147483647L; return s / 2147483647f }
        for (k in 0 until 24) {
          val ox = rnd() * SIZE
          val oy = rnd() * SIZE
          val idx = (oy.toInt() * SIZE + ox.toInt()).coerceIn(0, maskPixels.size - 1)
          if (Color.alpha(maskPixels[idx]) < 50) continue
          sparkPaint.color = Color.argb((rnd() * polishA * 0.7f).toInt().coerceAtLeast(40), 255, 255, 255)
          sparkCanvas.drawCircle(ox, oy, 1.2f + rnd() * 2.2f, sparkPaint)
        }
      }

      // Composite directly: the overlay View sits above the camera preview.
      // Using MULTIPLY here would multiply against a transparent destination
      // (resulting in near-invisible pixels), so keep normal src-over.
      canvas.drawBitmap(nailBmp, null, box, Paint(Paint.FILTER_BITMAP_FLAG))
      nailBmp.recycle()
    }
    return out
  }
}

// ─── Segmentation-mask nail overlay ──────────────────────────────────────────
// Replaces NailMaskOverlayView's ellipses with the TFLite per-pixel mask.
private class NailSegmentOverlayView(context: Context) : View(context) {
  private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
  private var maskBitmap: Bitmap? = null

  fun drawMask(bmp: Bitmap?) { maskBitmap = bmp; postInvalidate() }
  fun clear() { maskBitmap = null; postInvalidate() }

  override fun onDraw(canvas: Canvas) {
    maskBitmap?.let { canvas.drawBitmap(it, null, RectF(0f, 0f, width.toFloat(), height.toFloat()), paint) }
  }
}

// ─── Nail polish overlay (MediaPipe hand tips → ellipses) ────────────────────
private class NailMaskOverlayView(context: Context) : View(context) {
  private val baseFill = Paint(Paint.ANTI_ALIAS_FLAG)
  private val tipFill = Paint(Paint.ANTI_ALIAS_FLAG)
  private val sparkle = Paint(Paint.ANTI_ALIAS_FLAG)
  private var centers: List<PointF> = emptyList()
  private var radii: List<Float> = emptyList()
  private var tiltsDeg: List<Float> = emptyList()
  private var nailShape: Int = 0 // 0=nat, 1=alm, 2=sq, 3=stil
  private var polishColor = Color.RED
  private var alphaF = 0.72f
  private var artStyle = 0

  fun setNailData(
    c: List<PointF>,
    r: List<Float>,
    deg: List<Float>,
    color: Int,
    intensity: Float,
    style: Int,
    shape: Int
  ) {
    centers = c
    radii = r
    tiltsDeg = deg
    polishColor = color
    alphaF = intensity.coerceIn(0.15f, 0.98f)
    artStyle = style
    nailShape = shape
    postInvalidate()
  }

  fun clear() {
    centers = emptyList()
    radii = emptyList()
    tiltsDeg = emptyList()
    postInvalidate()
  }

  override fun onDraw(canvas: Canvas) {
    if (centers.isEmpty()) return
    val a = (alphaF * 255).toInt().coerceIn(40, 252)
    val colorWithAlpha = ColorUtils.setAlphaComponent(polishColor, a)

    for (i in centers.indices) {
      val cx = centers[i].x
      val cy = centers[i].y
      val rad = if (i < radii.size) radii[i] else 24f
      val tilt = if (i < tiltsDeg.size) tiltsDeg[i] else 0f
      
      val rw = rad * 1.15f
      val rh = rad * 1.45f

      canvas.save()
      canvas.translate(cx, cy)
      canvas.rotate(tilt)

      val path = android.graphics.Path()
      when (nailShape) {
        1 -> { // Almond
          path.moveTo(-rw * 0.9f, 0f)
          path.cubicTo(-rw, -rh * 0.8f, 0f, -rh * 1.25f, rw * 0.9f, 0f)
          path.cubicTo(rw, rh * 0.8f, 0f, rh, -rw * 0.9f, 0f)
        }
        2 -> { // Square
          val r = 0.2f
          path.addRoundRect(-rw, -rh, rw, rh, rw * r, rw * r, android.graphics.Path.Direction.CW)
        }
        3 -> { // Stiletto
          path.moveTo(0f, -rh * 1.35f)
          path.lineTo(rw, rh * 0.5f)
          path.quadTo(0f, rh * 1.1f, -rw, rh * 0.5f)
          path.close()
        }
        else -> { // Natural
          path.moveTo(-rw * 0.85f, -rh * 0.7f)
          path.quadTo(0f, -rh * 1.15f, rw * 0.85f, -rh * 0.7f)
          path.lineTo(rw * 0.95f, rh * 0.75f)
          path.quadTo(0f, rh * 1.05f, -rw * 0.95f, rh * 0.75f)
          path.close()
        }
      }

      // This overlay is drawn in its own View layer above the camera preview.
      // PorterDuff MULTIPLY does not blend with underlying Views; keep normal paint.
      baseFill.xfermode = null
      baseFill.shader = null

      when (artStyle) {
        1 -> { // French
          baseFill.color = ColorUtils.setAlphaComponent(polishColor, (a * 0.75f).toInt())
          canvas.drawPath(path, baseFill)
          tipFill.color = Color.argb((a * 0.98f).toInt(), 248, 244, 240)
          canvas.save()
          canvas.clipPath(path)
          canvas.drawRect(-rw, -rh, rw, -rh * 0.35f, tipFill)
          canvas.restore()
        }
        2 -> { // Ombre
          val g = android.graphics.LinearGradient(
            0f, rh, 0f, -rh,
            ColorUtils.setAlphaComponent(polishColor, a),
            ColorUtils.setAlphaComponent(polishColor, (a * 0.25f).toInt()),
            android.graphics.Shader.TileMode.CLAMP
          )
          baseFill.shader = g
          canvas.drawPath(path, baseFill)
        }
        3 -> { // Sparkle
          baseFill.color = ColorUtils.setAlphaComponent(polishColor, (a * 0.75f).toInt())
          canvas.drawPath(path, baseFill)
          var s = (cx * 23 + cy * 37 + i * 13).toLong()
          fun rnd(): Float { s = (s * 48271L) % 2147483647L; return s / 2147483647f }
          sparkle.xfermode = null
          for (k in 0 until 18) {
            val ox = (rnd() - 0.5f) * rw * 1.7f
            val oy = (rnd() - 0.5f) * rh * 1.7f
            // Simple bound check
            sparkle.color = Color.argb((rnd() * a * 0.65f).toInt().coerceAtLeast(40), 255, 255, 255)
            canvas.drawCircle(ox, oy, 1f + rnd() * 1.8f, sparkle)
          }
        }
        else -> {
          baseFill.color = colorWithAlpha
          canvas.drawPath(path, baseFill)
        }
      }
      canvas.restore()
    }
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
  private val hairMaskOverlay: HairMaskOverlayView = HairMaskOverlayView(appContext)
  private val nailMaskOverlay: NailMaskOverlayView = NailMaskOverlayView(appContext)
  private val nailSegmentOverlay: NailSegmentOverlayView = NailSegmentOverlayView(appContext)
  private val nailRenderer: NailPolishRenderer = NailPolishRenderer(appContext)

  private var cameraProvider: ProcessCameraProvider? = null
  private var analyzer: ImageAnalysis? = null
  private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
  private var eventSink: EventChannel.EventSink? = null
  private var startRequested = false

  private var faceLandmarker: FaceLandmarker? = null
  private var hairSegmenter: ImageSegmenter? = null
  private var handLandmarker: HandLandmarker? = null
  private var nailVideoTimestamp = 0L
  private var useBackCameraNails = false
  @Volatile private var processing = false
  private var rgbaBitmap: Bitmap? = null
  // Stale-mask guard: clear overlay if processing falls too far behind the camera
  private var skippedHairFrames = 0
  private val kMaxSkip = 3

  private var currentCategory = "cmd_lipstick"
  private var isCompareMode = false
  private var currentSplitPosition = 0.5f
  private var currentShadeColor = Color.RED
  private var currentIntensity = 0.4f
  private var currentHairStyleShape = "long"
  private var currentNailArtStyle = 0
  private var currentNailShape = 0

  /** Offline photo try-on (setPhoto + renderPhoto); only touched from [photoExecutor]. */
  private val photoExecutor: ExecutorService = Executors.newSingleThreadExecutor()
  private var photoBitmap: Bitmap? = null
  private var photoFaceLandmarker: FaceLandmarker? = null
  private var useLayeredLook = false
  private var lookLayers: List<Triple<Int, Float, String>> = emptyList()

  init {
    methodChannel.setMethodCallHandler(this)
    eventChannel.setStreamHandler(this)
    previewView.scaleType = PreviewView.ScaleType.FILL_CENTER

    container.addView(previewView, FrameLayout.LayoutParams(-1, -1))
    container.addView(glOverlay, FrameLayout.LayoutParams(-1, -1))
    container.addView(hairMaskOverlay, FrameLayout.LayoutParams(-1, -1))
    container.addView(nailSegmentOverlay, FrameLayout.LayoutParams(-1, -1))  // TFLite mask (preferred)
    container.addView(nailMaskOverlay, FrameLayout.LayoutParams(-1, -1))     // Landmark fallback
    hairMaskOverlay.alpha = 1f
    nailMaskOverlay.visibility = View.GONE
    nailSegmentOverlay.visibility = View.GONE
  }

  override fun getView() = container

  override fun dispose() {
    stopCamera()
    eventChannel.setStreamHandler(null)
    methodChannel.setMethodCallHandler(null)
    cameraExecutor.shutdown()
    photoExecutor.execute {
      photoFaceLandmarker?.close()
      photoFaceLandmarker = null
      photoBitmap?.recycle()
      photoBitmap = null
    }
    photoExecutor.shutdown()
    hairSegmenter?.close()
    hairSegmenter = null
    faceLandmarker?.close()
    faceLandmarker = null
    handLandmarker?.close()
    handLandmarker = null
    nailRenderer.close()
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "start" -> { startRequested = true; startCameraIfReady(); result.success(null) }
      "stop" -> { startRequested = false; stopCamera(); result.success(null) }
      "setEffect" -> {
        val args = call.arguments as? Map<*, *>
        val shade = (args?.get("shade") as? Number)?.toInt() ?: 0
        val intensity = (args?.get("intensity") as? Number)?.toFloat() ?: 0.7f
        val category = args?.get("category") as? String ?: "cmd_lipstick"
        val compare = args?.get("isCompareMode") as? Boolean ?: false
        val hairShape = args?.get("hairStyleShape") as? String
        if (hairShape != null) currentHairStyleShape = hairShape.lowercase()
        currentNailArtStyle = (args?.get("nailArtStyle") as? Number)?.toInt() ?: 0
        currentNailShape = (args?.get("nailShape") as? Number)?.toInt() ?: 0

        val wasNails = currentCategory == "cmd_nails"
        currentCategory = category
        useLayeredLook = false
        lookLayers = emptyList()
        isCompareMode = compare
        currentShadeColor = shade
        currentIntensity = intensity

        val isNails = category == "cmd_nails"
        if (wasNails && !isNails) {
          handLandmarker?.close()
          handLandmarker = null
          nailVideoTimestamp = 0L
        }

        if (category != "cmd_haircolor" && category != "cmd_hairstyle") {
          android.os.Handler(android.os.Looper.getMainLooper()).post {
            hairMaskOverlay.clear()
          }
        }

        val backNow = isNails
        if (backNow != useBackCameraNails) {
          useBackCameraNails = backNow
          if (startRequested && cameraProvider != null && activity is LifecycleOwner) {
            bindCamera(cameraProvider!!, activity as LifecycleOwner)
          }
        }

        android.os.Handler(android.os.Looper.getMainLooper()).post {
          if (isNails) {
            glOverlay.hideAllOverlays()
            hairMaskOverlay.clear()
            nailSegmentOverlay.visibility = View.VISIBLE
            nailMaskOverlay.visibility = View.VISIBLE  // fallback if model not loaded
          } else {
            nailSegmentOverlay.clear()
            nailSegmentOverlay.visibility = View.GONE
            nailMaskOverlay.clear()
            nailMaskOverlay.visibility = View.GONE
          }
        }

        glOverlay.setEffect(shade, intensity, category, compare)
        result.success(null)
      }
      "setLook" -> {
        val args = call.arguments as? Map<*, *> ?: run {
          result.success(null)
          return@onMethodCall
        }
        val compare = args["isCompareMode"] as? Boolean ?: false
        val raw = args["layers"] as? List<*> ?: emptyList<Any>()
        val layers = mutableListOf<Triple<Int, Float, String>>()
        for (item in raw) {
          val m = item as? Map<*, *> ?: continue
          val shade = (m["shade"] as? Number)?.toInt() ?: continue
          val intensity = (m["intensity"] as? Number)?.toFloat() ?: 0.4f
          val category = (m["category"] as? String) ?: continue
          if (category.lowercase() == "cmd_none") continue
          layers.add(Triple(shade, intensity, category))
        }
        val capped = if (layers.size > 10) layers.take(10) else layers
        lookLayers = capped
        useLayeredLook = true
        glOverlay.setLook(capped, compare)
        result.success(null)
      }
      "setPhoto" -> {
        val args = call.arguments as? Map<*, *>
        val path = args?.get("imageFilePath") as? String
        photoExecutor.execute {
          try {
            if (path.isNullOrEmpty()) {
              photoBitmap?.recycle()
              photoBitmap = null
              android.os.Handler(android.os.Looper.getMainLooper()).post { result.success(null) }
              return@execute
            }
            val decoded = android.graphics.BitmapFactory.decodeFile(path)
            if (decoded == null) {
              android.os.Handler(android.os.Looper.getMainLooper()).post {
                result.error("decode", "Could not decode image", null)
              }
              return@execute
            }
            val scaled = downscalePhotoBitmap(decoded, 1280)
            if (scaled !== decoded) decoded.recycle()
            photoBitmap?.recycle()
            photoBitmap = scaled
            android.os.Handler(android.os.Looper.getMainLooper()).post { result.success(null) }
          } catch (t: Throwable) {
            Log.e("LipRenderer", "setPhoto", t)
            android.os.Handler(android.os.Looper.getMainLooper()).post {
              result.error("setPhoto", t.message, null)
            }
          }
        }
      }
      "renderPhoto" -> {
        photoExecutor.execute {
          try {
            val bytes = renderPhotoToPngBytes()
            android.os.Handler(android.os.Looper.getMainLooper()).post {
              if (bytes != null) result.success(bytes)
              else result.error("photo", "No photo or face not found.", null)
            }
          } catch (t: Throwable) {
            Log.e("LipRenderer", "renderPhoto", t)
            android.os.Handler(android.os.Looper.getMainLooper()).post {
              result.error("photo", t.message, null)
            }
          }
        }
      }
      "setDebug" -> {
        val show = (call.arguments as? Map<*, *>)?.get("showLandmarks") as? Boolean ?: false
        glOverlay.setShowLandmarks(show)
        result.success(null)
      }
      "setCalibration" -> {
        val args = call.arguments as? Map<*, *>
        val split = (args?.get("splitPosition") as? Number)?.toFloat() ?: 0.5f
        currentSplitPosition = split
        glOverlay.setCalibration(split)
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
    if (!startRequested || !hasCameraPermission()) return

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
      .also { it.setAnalyzer(cameraExecutor) { image -> processFrame(image) } }

    val selector =
      if (currentCategory == "cmd_nails") CameraSelector.DEFAULT_BACK_CAMERA
      else CameraSelector.DEFAULT_FRONT_CAMERA

    provider.unbindAll()
    provider.bindToLifecycle(lifecycleOwner, selector, preview, analyzer)
    cameraProvider = provider
    nailVideoTimestamp = 0L
    eventSink?.success(mapOf("type" to "ready"))
  }

  private fun stopCamera() { cameraProvider?.unbindAll(); analyzer?.clearAnalyzer(); cameraProvider = null }
  private fun hasCameraPermission() = ContextCompat.checkSelfPermission(appContext, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

  // ─── Route per-frame processing based on mode ─────────────────────────────
  private fun isHairSegmentationMode(): Boolean =
    currentCategory == "cmd_haircolor" || currentCategory == "cmd_hairstyle"

  private fun isNailMode(): Boolean = currentCategory == "cmd_nails"

  private fun processFrame(image: ImageProxy) {
    val isHair = isHairSegmentationMode()
    val isNails = isNailMode()

    if (processing) {
      if (isHair) {
        // Count skipped frames; clear stale mask after kMaxSkip to prevent
        // the hair overlay drifting onto the face when the phone moves.
        skippedHairFrames++
        if (skippedHairFrames >= kMaxSkip) {
          android.os.Handler(android.os.Looper.getMainLooper()).post {
            hairMaskOverlay.clear()
          }
        }
      }
      image.close()
      return
    }

    processing = true
    if (isHair) skippedHairFrames = 0

    val width = image.width
    val height = image.height
    if (rgbaBitmap == null || rgbaBitmap?.width != width || rgbaBitmap?.height != height) {
      rgbaBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    }

    val plane = image.planes[0]
    rgbaBitmap?.copyPixelsFromBuffer(plane.buffer)
    val mpImage = BitmapImageBuilder(rgbaBitmap).build()

    when {
      isNails -> runHandNails(mpImage, image)
      isHairSegmentationMode() -> runHairSegmentation(mpImage, image)
      else -> runFaceMesh(mpImage, image)
    }
  }

  /**
   * Maps normalized landmarks (0–1) to [PreviewView] pixels. Uses **aspect-fill (cover)**
   * to match [PreviewView.ScaleType.FILL_CENTER]; the old contain/letterbox mapping caused
   * polish to sit beside the real nails.
   */
  private fun mapNormToViewCover(
    nx: Float,
    ny: Float,
    iw: Int,
    ih: Int,
    rot: Int,
    vw: Float,
    vh: Float,
    mirrorX: Boolean
  ): PointF {
    val rotN = (rot + 360) % 360
    val rw: Float
    val rh: Float
    if (rotN % 180 == 0) {
      rw = iw.toFloat()
      rh = ih.toFloat()
    } else {
      rw = ih.toFloat()
      rh = iw.toFloat()
    }
    val (tx, ty) = when (rotN) {
      90 -> Pair(1f - ny, nx)
      180 -> Pair(1f - nx, 1f - ny)
      270 -> Pair(ny, 1f - nx)
      else -> Pair(nx, ny)
    }
    val fx = if (mirrorX) 1f - tx else tx
    val bx = fx * rw
    val by = ty * rh
    val scale = max(vw / rw, vh / rh)
    val dx = (vw - rw * scale) / 2f
    val dy = (vh - rh * scale) / 2f
    return PointF(bx * scale + dx, by * scale + dy)
  }

  private fun ensureHandVideoLandmarker(): Boolean {
    if (handLandmarker != null) return true
    return try {
      val baseOptions = BaseOptions.builder()
        .setModelAssetPath("flutter_assets/assets/models/hand_landmarker.task")
        .build()
      val options = HandLandmarker.HandLandmarkerOptions.builder()
        .setBaseOptions(baseOptions)
        .setRunningMode(RunningMode.VIDEO)
        .setNumHands(2)
        .setMinHandDetectionConfidence(0.35f)
        .setMinHandPresenceConfidence(0.45f)
        .setMinTrackingConfidence(0.45f)
        .build()
      handLandmarker = HandLandmarker.createFromOptions(appContext, options)
      nailVideoTimestamp = 0L
      true
    } catch (t: Throwable) {
      Log.e("HandNails", "HandLandmarker init failed", t)
      false
    }
  }

  private fun runHandNails(mpImage: MPImage, image: ImageProxy) {
    if (!ensureHandVideoLandmarker()) {
      processing = false
      image.close()
      return
    }
    val rot = image.imageInfo.rotationDegrees
    val iw = image.width
    val ih = image.height
    // Use camera timestamps (ms) for MediaPipe VIDEO mode for better temporal stability.
    val tsMs = (image.imageInfo.timestamp / 1_000_000L).coerceAtLeast(0L)
    nailVideoTimestamp = if (tsMs > nailVideoTimestamp) tsMs else nailVideoTimestamp + 33L
    val hResult = try {
      handLandmarker!!.detectForVideo(mpImage, nailVideoTimestamp)
    } catch (t: Throwable) {
      Log.e("HandNails", "detectForVideo", t)
      null
    }

    val tips = handTipsNormalizedFromResult(hResult)
    val vw = previewView.width.toFloat().coerceAtLeast(1f)
    val vh = previewView.height.toFloat().coerceAtLeast(1f)
    val mirrorX = false

    // ── Build per-finger bounding boxes for TFLite ROI cropping ────────────
    val boxes = ArrayList<RectF>(5)
    val centers = ArrayList<PointF>(5)
    val radii = ArrayList<Float>(5)
    val degs = ArrayList<Float>(5)

    for (m in tips) {
      val nx  = (m["nx"] ?: 0.0).toFloat()
      val ny  = (m["ny"] ?: 0.0).toFloat()
      val rN  = (m["r"]  ?: 0.05).toFloat()
      val ang = (m["angle"] ?: 0.0).toFloat()
      val pt  = mapNormToViewCover(nx, ny, iw, ih, rot, vw, vh, mirrorX)
      val rPx = (rN * min(vw, vh) * 1.38f).coerceIn(16f, 96f)
      centers.add(pt)
      radii.add(rPx)
      degs.add(Math.toDegrees(ang.toDouble()).toFloat() + 90f)
      // Inflate box around fingertip to fully cover nail plate
      val padX = rPx * 1.3f
      val padY = rPx * 1.7f
      boxes.add(RectF(pt.x - padX, pt.y - padY, pt.x + padX, pt.y + padY))
    }

    // ── Try TFLite segmentation first ──────────────────────────────────────
    val modelLoaded = nailRenderer.ensureLoaded()
    val maskBmp: Bitmap? = if (modelLoaded && rgbaBitmap != null && boxes.isNotEmpty()) {
      nailRenderer.renderNailMask(
        srcBitmap  = rgbaBitmap!!,
        boxes      = boxes,
        viewW      = vw.toInt(),
        viewH      = vh.toInt(),
        polishColor = currentShadeColor,
        alpha      = currentIntensity,
        artStyle   = currentNailArtStyle
      )
    } else null

    android.os.Handler(android.os.Looper.getMainLooper()).post {
      if (maskBmp != null) {
        // TFLite path: show segmentation mask, hide ellipse fallback
        nailSegmentOverlay.drawMask(maskBmp)
        nailSegmentOverlay.visibility = View.VISIBLE
        nailMaskOverlay.visibility = View.GONE
      } else if (centers.isNotEmpty()) {
        // Fallback: landmark ellipses (no model or no hand detected)
        nailSegmentOverlay.clear()
        nailSegmentOverlay.visibility = View.GONE
        nailMaskOverlay.visibility = View.VISIBLE
        nailMaskOverlay.setNailData(centers, radii, degs, currentShadeColor, currentIntensity, currentNailArtStyle, currentNailShape)
      } else {
        nailSegmentOverlay.clear()
        nailMaskOverlay.clear()
      }
    }

    processing = false
    image.close()
  }

  /** Push face-oval forehead/temple points toward the hairline in normalized Y (no inner mesh detours). */
  private fun foundationFaceOvalPoints(
    landmarks: List<NormalizedLandmark>,
    indices: IntArray,
  ): List<PointF> {
    val eyeY = (landmarks[33].y() + landmarks[263].y()).toFloat() * 0.5f
    val chinY = landmarks[152].y().toFloat()
    val faceLen = kotlin.math.abs(chinY - eyeY).coerceAtLeast(0.06f)
    val liftN = (faceLen * 0.095f).coerceIn(0.013f, 0.054f)
    val hairlineExtraN = 0.014f
    val hairlineCrownIds = setOf(10, 151, 109, 338, 297, 332, 284, 251)
    val w = hashMapOf(
      151 to 1f, 109 to 1f, 338 to 1f, 10 to 0.98f,
      297 to 0.60f, 332 to 0.60f, 284 to 0.42f, 251 to 0.42f,
      389 to 0.27f, 356 to 0.20f, 454 to 0.16f, 323 to 0.16f, 361 to 0.14f, 288 to 0.12f, 397 to 0.12f, 365 to 0.10f,
      379 to 0.07f, 378 to 0.07f, 400 to 0.06f, 377 to 0.06f,
      67 to 0.39f, 103 to 0.34f, 54 to 0.30f, 21 to 0.29f, 162 to 0.27f, 127 to 0.23f, 234 to 0.21f, 93 to 0.17f, 132 to 0.14f,
      172 to 0.10f, 58 to 0.085f,
    )
    val pts = indices.map { i ->
      val lm = landmarks[i]
      val wt = w[i] ?: 0f
      var y = lm.y().toFloat()
      if (wt > 0f) y -= liftN * wt
      if (i in hairlineCrownIds) y -= hairlineExtraN
      PointF(lm.x().toFloat(), y)
    }.toMutableList()
    smoothFoundationForeheadPolyline(pts)
    return pts
  }

  /** Same idea as iOS: soften crown + upper-face span to kill mesh “V” / zig-zag on GL mask. */
  private fun smoothFoundationForeheadPolyline(pts: MutableList<PointF>) {
    if (pts.size < 12) return
    fun smoothRange(lo: Int, hi: Int, passes: Int) {
      if (hi - lo < 2) return
      repeat(passes) {
        val snap = pts.map { PointF(it.x, it.y) }
        for (i in (lo + 1) until hi) {
          val p = snap[i]
          val a = snap[i - 1]
          val b = snap[i + 1]
          pts[i].x = p.x * 0.46f + (a.x + b.x) * 0.27f
          pts[i].y = p.y * 0.46f + (a.y + b.y) * 0.27f
        }
      }
    }
    val last = pts.size - 1
    smoothRange(0, minOf(6, last), 5)
    if (last >= 36) smoothRange(last - 10, last, 5)
    else if (last >= 35) smoothRange(last - 9, last, 5)
  }

  // ─── Face landmarks → GL lip/makeup overlay ───────────────────────────────
  private fun runFaceMesh(mpImage: MPImage, image: ImageProxy) {
    if (!ensureLandmarker()) { processing = false; image.close(); return }

    val result = faceLandmarker?.detect(mpImage)
    val landmarks = result?.faceLandmarks()?.firstOrNull()

    if (landmarks != null) {
      val outerLipIdx = intArrayOf(61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 308, 324, 318, 402, 317, 14, 87, 178, 88)
      val innerLipIdx = intArrayOf(78, 95, 88, 178, 87, 14, 317, 402, 318, 324)
      // 109→151→338 only; avoid 9/337/108 (re-entrant path + evenOdd = forehead hole).
      val faceOvalIdx = intArrayOf(338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109, 151, 10)
      val leftEyeIdx  = intArrayOf(33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246)
      val rightEyeIdx = intArrayOf(362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398)

      val outerLip = outerLipIdx.map { PointF(landmarks[it].x(), landmarks[it].y()) }
      val innerLip = innerLipIdx.map { PointF(landmarks[it].x(), landmarks[it].y()) }
      val faceOval = if (currentCategory == "cmd_face" ||
        currentCategory.contains("foundation", ignoreCase = true) ||
        currentCategory.contains("concealer", ignoreCase = true)
      ) {
        foundationFaceOvalPoints(landmarks, faceOvalIdx)
      } else {
        faceOvalIdx.map { PointF(landmarks[it].x(), landmarks[it].y()) }
      }
      val leftEye  = leftEyeIdx.map  { PointF(landmarks[it].x(), landmarks[it].y()) }
      val rightEye = rightEyeIdx.map { PointF(landmarks[it].x(), landmarks[it].y()) }

      glOverlay.setLandmarks(outerLip, innerLip, faceOval, leftEye, rightEye,
        image.width, image.height, image.imageInfo.rotationDegrees)
    }

    processing = false
    image.close()
  }

  // ─── Hair segmentation → luminance-boosted HSL mask ──────────────────────
  private fun runHairSegmentation(mpImage: MPImage, image: ImageProxy) {
    if (!ensureHairSegmenter()) { processing = false; image.close(); return }

    try {
      val result: ImageSegmenterResult = hairSegmenter!!.segment(mpImage)
      val coloredBitmap = if (currentCategory == "cmd_hairstyle") {
        buildHairStyleEffectBitmap(result)
      } else {
        buildHairColorBitmap(result)
      }
      val intensity = currentIntensity
      android.os.Handler(android.os.Looper.getMainLooper()).post {
        hairMaskOverlay.drawHairMask(coloredBitmap)
        hairMaskOverlay.alpha = intensity   // intensity = global strength, like lipstick alpha
        glOverlay.hideAllOverlays()
      }
    } catch (t: Throwable) {
      Log.e("HairSegmenter", "Segmentation error", t)
    }

    processing = false
    image.close()
  }

  // ─── Luminance-boosted HSL hair colour bitmap ─────────────────────────────
  //
  // Why previous attempts looked unrealistic on dark hair:
  //   • colorBlendMode / pure overlay: dark hair (L≈0.10) stays near-black even
  //     after hue/saturation replacement → auburn barely visible.
  //
  // This version mirrors how real hair dye works:
  //   1. Sample the ACTUAL camera pixel for each hair position
  //   2. Convert to HSL
  //   3. Apply target H + S  (the dye colour)
  //   4. Lift luminance: result_L = max(srcL, targetL × 0.75)
  //      → dark roots rise to 75% of the target's brightness (bleach simulation)
  //      → existing highlights (srcL > 0.75×targetL) keep their advantage
  //   5. Pre-multiply by confidence for smooth edge feathering
  //   6. View.alpha = currentIntensity (global strength knob)
  private fun buildHairColorBitmap(result: ImageSegmenterResult): Bitmap? {
    val masks = result.confidenceMasks().orElse(null) ?: return null
    if (masks.isEmpty()) return null

    val hairMaskImg = if (masks.size > 1) masks[1] else masks[0]
    val maskW = hairMaskImg.width
    val maskH = hairMaskImg.height
    if (maskW <= 0 || maskH <= 0) return null

    val byteBuffer = ByteBufferExtractor.extract(hairMaskImg)
    byteBuffer.rewind()
    val floatBuffer = byteBuffer.asFloatBuffer()
    val floatData = FloatArray(floatBuffer.capacity())
    floatBuffer.get(floatData)

    val tRf = Color.red(currentShadeColor)   / 255f
    val tGf = Color.green(currentShadeColor) / 255f
    val tBf = Color.blue(currentShadeColor)  / 255f
    val (tgtH, tgtS, tgtL) = rgbToHSL(tRf, tGf, tBf)

    val srcBmp = rgbaBitmap
    val srcW   = srcBmp?.width  ?: 1
    val srcH   = srcBmp?.height ?: 1

    // ── Process at 1/4 resolution → 16× fewer pixels → ~12 ms instead of ~180 ms
    // The HairMaskOverlayView stretches the bitmap to fill its bounds (smooth scale).
    val scale  = 4
    val procW  = max(1, maskW / scale)
    val procH  = max(1, maskH / scale)
    val pixels = IntArray(procW * procH)

    for (i in 0 until procW * procH) {
      val px = i % procW
      val py = i / procW

      // Sample confidence mask at 4× step
      val mx   = min(maskW - 1, px * scale)
      val my   = min(maskH - 1, py * scale)
      var conf = floatData[my * maskW + mx].coerceIn(0f, 1f)

      conf = if (conf < 0.20f) 0f
             else { val t = (conf - 0.20f) / 0.80f; t * t * (3f - 2f * t) }

      val alpha = (conf * 255f).toInt().coerceIn(0, 255)
      if (alpha == 0) { pixels[i] = 0; continue }

      // Sample camera bitmap at corresponding position
      val srcX = (px * srcW / procW).coerceIn(0, srcW - 1)
      val srcY = (py * srcH / procH).coerceIn(0, srcH - 1)

      val srcPixel = srcBmp?.getPixel(srcX, srcY) ?: currentShadeColor
      val srcR = Color.red(srcPixel)   / 255f
      val srcG = Color.green(srcPixel) / 255f
      val srcB = Color.blue(srcPixel)  / 255f

      val (_, _, srcL) = rgbToHSL(srcR, srcG, srcB)

      // Luminance floor: dark hair lifted to ≥75% of target brightness
      val resultL = max(srcL, tgtL * 0.75f)

      val (outR, outG, outB) = hslToRGB(tgtH, tgtS, resultL)

      val aN  = alpha / 255f
      val pR  = (outR * aN * 255f).toInt().coerceIn(0, 255)
      val pG  = (outG * aN * 255f).toInt().coerceIn(0, 255)
      val pB  = (outB * aN * 255f).toInt().coerceIn(0, 255)
      pixels[i] = Color.argb(alpha, pR, pG, pB)
    }

    // Bitmap at 1/4 size; HairMaskOverlayView stretches it to full screen
    val bmp = Bitmap.createBitmap(procW, procH, Bitmap.Config.ARGB_8888)
    bmp.setPixels(pixels, 0, procW, 0, 0, procW, procH)
    return bmp
  }

  private fun smoothstep(edge0: Float, edge1: Float, x: Float): Float {
    val t = ((x - edge0) / (edge1 - edge0)).coerceIn(0f, 1f)
    return t * t * (3f - 2f * t)
  }

  /// Style Match: MediaPipe hair mask + accent tint with per-shape grading (constrained to hair pixels).
  private fun buildHairStyleEffectBitmap(result: ImageSegmenterResult): Bitmap? {
    val masks = result.confidenceMasks().orElse(null) ?: return null
    if (masks.isEmpty()) return null

    val hairMaskImg = if (masks.size > 1) masks[1] else masks[0]
    val maskW = hairMaskImg.width
    val maskH = hairMaskImg.height
    if (maskW <= 0 || maskH <= 0) return null

    val byteBuffer = ByteBufferExtractor.extract(hairMaskImg)
    byteBuffer.rewind()
    val floatBuffer = byteBuffer.asFloatBuffer()
    val floatData = FloatArray(floatBuffer.capacity())
    floatBuffer.get(floatData)

    val tRf = Color.red(currentShadeColor) / 255f
    val tGf = Color.green(currentShadeColor) / 255f
    val tBf = Color.blue(currentShadeColor) / 255f
    val (tgtH0, tgtS0, tgtL0) = rgbToHSL(tRf, tGf, tBf)
    var tgtH = tgtH0
    var tgtS = tgtS0
    var tgtL = tgtL0

    val srcBmp = rgbaBitmap
    val srcW = srcBmp?.width ?: 1
    val srcH = srcBmp?.height ?: 1

    val shape = currentHairStyleShape.lowercase()
    val scale = 4
    val procW = max(1, maskW / scale)
    val procH = max(1, maskH / scale)
    val pixels = IntArray(procW * procH)

    for (i in 0 until procW * procH) {
      val px = i % procW
      val py = i / procW

      val mx = min(maskW - 1, px * scale)
      val my = min(maskH - 1, py * scale)
      var conf = floatData[my * maskW + mx].coerceIn(0f, 1f)

      conf = if (conf < 0.18f) 0f
      else {
        val t = (conf - 0.18f) / 0.82f
        t * t * (3f - 2f * t)
      }

      val u = px.toFloat() / max(1, procW)
      val v = py.toFloat() / max(1, procH)

      var lenMul = 1f
      when (shape) {
        "pixie", "textured_pixie" -> lenMul = smoothstep(0.58f, 0.22f, v)
        "buzz", "buzz_cut" -> lenMul = smoothstep(0.52f, 0.18f, v)
        "bob", "blunt_bob", "french_bob" -> lenMul = smoothstep(0.68f, 0.36f, v)
        "bangs", "curtain_bangs" -> lenMul = smoothstep(0.65f, 0.35f, v)
        "bun", "slick_bun", "braid", "braid_crown" ->
          lenMul = smoothstep(0.48f, 0.15f, v) * 0.92f + 0.08f
      }

      val alpha = (conf * 255f * lenMul).toInt().coerceIn(0, 255)
      if (alpha == 0) {
        pixels[i] = 0
        continue
      }

      val srcX = (px * srcW / procW).coerceIn(0, srcW - 1)
      val srcY = (py * srcH / procH).coerceIn(0, srcH - 1)

      val srcPixel = srcBmp?.getPixel(srcX, srcY) ?: currentShadeColor
      val srcR = Color.red(srcPixel) / 255f
      val srcG = Color.green(srcPixel) / 255f
      val srcB = Color.blue(srcPixel) / 255f

      val (_, srcS, srcL) = rgbToHSL(srcR, srcG, srcB)

      tgtH = tgtH0
      tgtS = tgtS0
      tgtL = tgtL0
      var effH = tgtH
      var effS = tgtS
      var resultL = max(srcL, tgtL * 0.72f)

      when (shape) {
        "waves", "beachy_waves", "layer_lob", "side_swept" -> {
          val wave = sin(u * PI.toFloat() * 10f + py * 0.065f) * 0.07f
          resultL = (resultL + wave).coerceIn(0f, 1f)
          effS = (effS * 1.06f).coerceIn(0f, 1f)
        }
        "curly", "big_curls" -> {
          val c = sin(u * PI.toFloat() * 14f) * sin(v * PI.toFloat() * 9f) * 0.11f
          resultL = (resultL + c).coerceIn(0f, 1f)
          effS = (effS * 1.14f).coerceIn(0f, 1f)
        }
        "sleek_straight", "straight" -> {
          effS = (effS * 0.94f).coerceIn(0f, 1f)
        }
        "wolf", "wolf_cut", "shaggy_mullet" -> {
          effS = (effS * 1.1f).coerceIn(0f, 1f)
          resultL = (resultL - (1f - v) * 0.06f).coerceIn(0f, 1f)
        }
        "braid", "braid_crown", "bun", "slick_bun" -> {
          resultL = (resultL + (1f - v) * 0.05f).coerceIn(0f, 1f)
        }
        else -> {
          resultL = (resultL + v * 0.04f).coerceIn(0f, 1f)
        }
      }

      val accentBoost = 0.25f
      effS = ((srcS * (1f - accentBoost)) + (effS * accentBoost)).coerceIn(0f, 1f)

      val (outR, outG, outB) = hslToRGB(effH, effS, resultL)

      val aN = alpha / 255f
      val pR = (outR * aN * 255f).toInt().coerceIn(0, 255)
      val pG = (outG * aN * 255f).toInt().coerceIn(0, 255)
      val pB = (outB * aN * 255f).toInt().coerceIn(0, 255)
      pixels[i] = Color.argb(alpha, pR, pG, pB)
    }

    val bmp = Bitmap.createBitmap(procW, procH, Bitmap.Config.ARGB_8888)
    bmp.setPixels(pixels, 0, procW, 0, 0, procW, procH)
    return bmp
  }

  private fun downscalePhotoBitmap(src: Bitmap, maxEdge: Int): Bitmap {
    val mw = max(src.width, src.height)
    if (mw <= maxEdge) return src
    val scale = maxEdge.toFloat() / mw
    val nw = (src.width * scale).roundToInt().coerceAtLeast(1)
    val nh = (src.height * scale).roundToInt().coerceAtLeast(1)
    return Bitmap.createScaledBitmap(src, nw, nh, true)
  }

  private fun ensurePhotoFaceLandmarker(): FaceLandmarker? {
    if (photoFaceLandmarker != null) return photoFaceLandmarker
    return try {
      val baseOptions = BaseOptions.builder()
        .setModelAssetPath("flutter_assets/assets/models/face_landmarker.task")
        .build()
      val options = FaceLandmarker.FaceLandmarkerOptions.builder()
        .setBaseOptions(baseOptions)
        .setRunningMode(RunningMode.IMAGE)
        .setNumFaces(1)
        .build()
      photoFaceLandmarker = FaceLandmarker.createFromOptions(appContext, options)
      photoFaceLandmarker
    } catch (t: Throwable) {
      Log.e("LipRenderer", "photo FaceLandmarker", t)
      null
    }
  }

  private fun isFoundationCategory(cat: String): Boolean {
    val c = cat.lowercase()
    return c == "cmd_face" || c == "cmd_foundation" || c == "cmd_concealer" ||
      c.contains("foundation")
  }

  private fun lipPixelPaths(landmarks: List<NormalizedLandmark>, w: Int, h: Int): Pair<Path, Path> {
    val outerLipIdx = intArrayOf(61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 308, 324, 318, 402, 317, 14, 87, 178, 88)
    val innerLipIdx = intArrayOf(78, 95, 88, 178, 87, 14, 317, 402, 318, 324)
    val outer = Path()
    outerLipIdx.forEachIndexed { i, idx ->
      val lm = landmarks[idx]
      val x = lm.x() * w
      val y = lm.y() * h
      if (i == 0) outer.moveTo(x, y) else outer.lineTo(x, y)
    }
    outer.close()
    val inner = Path()
    innerLipIdx.forEachIndexed { i, idx ->
      val lm = landmarks[idx]
      val x = lm.x() * w
      val y = lm.y() * h
      if (i == 0) inner.moveTo(x, y) else inner.lineTo(x, y)
    }
    inner.close()
    return outer to inner
  }

  private fun eyePixelPath(landmarks: List<NormalizedLandmark>, indices: IntArray, w: Int, h: Int): Path {
    val p = Path()
    indices.forEachIndexed { i, idx ->
      val lm = landmarks[idx]
      val x = lm.x() * w
      val y = lm.y() * h
      if (i == 0) p.moveTo(x, y) else p.lineTo(x, y)
    }
    p.close()
    return p
  }

  private fun faceFoundationPixelPath(landmarks: List<NormalizedLandmark>, w: Int, h: Int): Path {
    val faceOvalIdx = intArrayOf(338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109, 151, 10)
    val pts = foundationFaceOvalPoints(landmarks, faceOvalIdx)
    val p = Path()
    pts.forEachIndexed { i, pt ->
      val x = pt.x * w
      val y = pt.y * h
      if (i == 0) p.moveTo(x, y) else p.lineTo(x, y)
    }
    p.close()
    return p
  }

  private fun drawLipstickPhotoLayer(canvas: Canvas, landmarks: List<NormalizedLandmark>, color: Int, intensity: Float, w: Int, h: Int) {
    val (outer, inner) = lipPixelPaths(landmarks, w, h)
    val alpha = (255 * 0.6f * intensity.coerceIn(0f, 1f)).toInt().coerceIn(18, 245)
    val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      style = Paint.Style.FILL
      this.color = Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
    }
    canvas.drawPath(outer, p)
    p.xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_OUT)
    canvas.drawPath(inner, p)
    p.xfermode = null
  }

  private fun drawFoundationPhotoLayer(canvas: Canvas, landmarks: List<NormalizedLandmark>, color: Int, intensity: Float, w: Int, h: Int) {
    val facePath = faceFoundationPixelPath(landmarks, w, h)
    val (outerLip, _) = lipPixelPaths(landmarks, w, h)
    val leftEyeIdx  = intArrayOf(33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246)
    val rightEyeIdx = intArrayOf(362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398)
    val leftEye = eyePixelPath(landmarks, leftEyeIdx, w, h)
    val rightEye = eyePixelPath(landmarks, rightEyeIdx, w, h)
    val alpha = (255 * 0.3f * intensity.coerceIn(0f, 1f)).toInt().coerceIn(12, 200)
    val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      style = Paint.Style.FILL
      this.color = Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
    }
    canvas.drawPath(facePath, p)
    p.xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_OUT)
    canvas.drawPath(leftEye, p)
    canvas.drawPath(rightEye, p)
    canvas.drawPath(outerLip, p)
    p.xfermode = null
  }

  private fun drawPhotoCategory(canvas: Canvas, landmarks: List<NormalizedLandmark>, category: String, shade: Int, intensity: Float, w: Int, h: Int) {
    val c = category.lowercase()
    when {
      c == "cmd_haircolor" || c == "cmd_hairstyle" -> { /* hair is live-camera only */ }
      isFoundationCategory(c) -> drawFoundationPhotoLayer(canvas, landmarks, shade, intensity, w, h)
      else -> drawLipstickPhotoLayer(canvas, landmarks, shade, intensity, w, h)
    }
  }

  private fun renderPhotoToPngBytes(): ByteArray? {
    val bmp = photoBitmap ?: return null
    val lm = ensurePhotoFaceLandmarker() ?: return null
    val mpImage = BitmapImageBuilder(bmp).build()
    val result = try {
      lm.detect(mpImage)
    } catch (t: Throwable) {
      Log.e("LipRenderer", "detect photo", t)
      null
    } ?: return null
    val landmarks = result.faceLandmarks().firstOrNull() ?: return null

    val out = bmp.copy(Bitmap.Config.ARGB_8888, true)
    val canvas = Canvas(out)
    val w = out.width
    val h = out.height

    if (isCompareMode) {
      val split = currentSplitPosition.coerceIn(0.05f, 0.95f)
      canvas.save()
      canvas.clipRect(split * w, 0f, w.toFloat(), h.toFloat())
    }

    if (useLayeredLook && lookLayers.isNotEmpty()) {
      for (layer in lookLayers) {
        drawPhotoCategory(canvas, landmarks, layer.third, layer.first, layer.second, w, h)
      }
    } else {
      drawPhotoCategory(canvas, landmarks, currentCategory, currentShadeColor, currentIntensity, w, h)
    }

    if (isCompareMode) canvas.restore()

    val baos = ByteArrayOutputStream()
    if (!out.compress(Bitmap.CompressFormat.PNG, 92, baos)) return null
    return baos.toByteArray()
  }

  private fun ensureLandmarker(): Boolean {
    if (faceLandmarker != null) return true
    return try {
      val baseOptions = BaseOptions.builder()
        .setModelAssetPath("flutter_assets/assets/models/face_landmarker.task")
        .build()
      val options = FaceLandmarker.FaceLandmarkerOptions.builder()
        .setBaseOptions(baseOptions)
        .setRunningMode(RunningMode.IMAGE)
        .setNumFaces(1)
        .build()
      faceLandmarker = FaceLandmarker.createFromOptions(appContext, options)
      true
    } catch (t: Throwable) { Log.e("LipRenderer", "Landmarker fail", t); false }
  }

  private fun ensureHairSegmenter(): Boolean {
    if (hairSegmenter != null) return true
    return try {
      val baseOptions = BaseOptions.builder()
        .setModelAssetPath("flutter_assets/assets/models/hair_segmenter.tflite")
        .build()
      val options = ImageSegmenter.ImageSegmenterOptions.builder()
        .setBaseOptions(baseOptions)
        .setRunningMode(RunningMode.IMAGE)
        .setOutputConfidenceMasks(true)
        .setOutputCategoryMask(false)
        .build()
      hairSegmenter = ImageSegmenter.createFromOptions(appContext, options)
      true
    } catch (t: Throwable) { Log.e("HairSegmenter", "Init fail", t); false }
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
  fun setEffect(s: Int, i: Float, cat: String, comp: Boolean) = queueEvent { renderer.updateEffect(s, i, cat, comp) }
  fun setLook(layers: List<Triple<Int, Float, String>>, comp: Boolean) =
    queueEvent { renderer.setLook(layers, comp) }
  fun setShowLandmarks(s: Boolean) = queueEvent { renderer.showLandmarks = s }
  fun setCalibration(split: Float) = queueEvent { renderer.splitPosition = split }
  fun setLandmarks(o: List<PointF>, i: List<PointF>, f: List<PointF>, le: List<PointF>, re: List<PointF>, iw: Int, ih: Int, r: Int) =
    queueEvent { renderer.updateGeometry(o, i, f, le, re, iw.toFloat(), ih.toFloat(), width.toFloat(), height.toFloat(), r) }
  fun hideAllOverlays() = queueEvent { renderer.hideAll = true }
}

private class LipMaskRenderer : GLSurfaceView.Renderer {
  private var program = 0
  private var colorHandle = 0
  private var posHandle = 0

  private var outerLipBuf: java.nio.FloatBuffer? = null
  private var innerLipBuf: java.nio.FloatBuffer? = null
  private var faceOvalBuf: java.nio.FloatBuffer? = null
  private var leftEyeBuf: java.nio.FloatBuffer? = null
  private var rightEyeBuf: java.nio.FloatBuffer? = null

  private var outerLipCount = 0
  private var innerLipCount = 0
  private var faceOvalCount = 0
  private var leftEyeCount = 0
  private var rightEyeCount = 0

  @Volatile var showLandmarks = false
  @Volatile var splitPosition = 0.5f
  @Volatile var hideAll = false
  @Volatile private var color = floatArrayOf(1f, 0f, 0f, 0.5f)
  @Volatile private var category = "cmd_lipstick"
  @Volatile private var isCompareMode = false
  /// When true, [onDrawFrame] uses [effectLayers] instead of single [category] (may be empty = clear).
  @Volatile private var layeredLookEnabled = false
  @Volatile private var effectLayers: List<Triple<Int, Float, String>> = emptyList()

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

    // Hair mode is handled by HairMaskOverlayView; nothing to draw here
    if (hideAll) return

    GLES20.glUseProgram(program)

    if (layeredLookEnabled) {
      if (effectLayers.isEmpty()) return
      for (idx in effectLayers.indices) {
        if (idx > 0) GLES20.glClear(GLES20.GL_STENCIL_BUFFER_BIT)
        val layer = effectLayers[idx]
        val s = layer.first
        val i = layer.second
        val cat = layer.third
        color[0] = Color.red(s) / 255f
        color[1] = Color.green(s) / 255f
        color[2] = Color.blue(s) / 255f
        color[3] = (if (cat.contains("face", ignoreCase = true)) 0.3f else 0.6f) * i.coerceIn(0f, 1f)
        val ct = cat.lowercase()
        val isFoundation = ct == "cmd_face" || ct == "cmd_foundation" || ct == "cmd_concealer" ||
          ct.contains("foundation")
        GLES20.glUniform4fv(colorHandle, 1, color, 0)
        GLES20.glEnable(GLES20.GL_STENCIL_TEST)
        if (isFoundation) {
          val face = faceOvalBuf ?: continue
          if (faceOvalCount < 3) continue

          GLES20.glColorMask(false, false, false, false)
          GLES20.glStencilFunc(GLES20.GL_ALWAYS, 1, 0xFF)
          GLES20.glStencilOp(GLES20.GL_KEEP, GLES20.GL_KEEP, GLES20.GL_REPLACE)
          draw(face, faceOvalCount)

          GLES20.glStencilFunc(GLES20.GL_ALWAYS, 0, 0xFF)
          leftEyeBuf?.let { draw(it, leftEyeCount) }
          rightEyeBuf?.let { draw(it, rightEyeCount) }
          outerLipBuf?.let { draw(it, outerLipCount) }

          GLES20.glColorMask(true, true, true, true)
          GLES20.glStencilFunc(GLES20.GL_EQUAL, 1, 0xFF)
          draw(face, faceOvalCount)
        } else {
          val outer = outerLipBuf ?: continue
          if (outerLipCount < 3) continue

          GLES20.glColorMask(false, false, false, false)
          GLES20.glStencilFunc(GLES20.GL_ALWAYS, 1, 0xFF)
          GLES20.glStencilOp(GLES20.GL_KEEP, GLES20.GL_KEEP, GLES20.GL_REPLACE)
          draw(outer, outerLipCount)

          innerLipBuf?.let { GLES20.glStencilFunc(GLES20.GL_ALWAYS, 0, 0xFF); draw(it, innerLipCount) }

          GLES20.glColorMask(true, true, true, true)
          GLES20.glStencilFunc(GLES20.GL_EQUAL, 1, 0xFF)
          draw(outer, outerLipCount)
        }
        GLES20.glDisable(GLES20.GL_STENCIL_TEST)
      }
      return
    }

    GLES20.glUniform4fv(colorHandle, 1, color, 0)
    GLES20.glEnable(GLES20.GL_STENCIL_TEST)

    // cmd_face / cmd_foundation / cmd_concealer → full-face stencil. Avoid substring "concealer"
    // (matches unrelated strings); live try-on sends cmd_face for concealer products.
    val ct = category.lowercase()
    val isFoundation = ct == "cmd_face" || ct == "cmd_foundation" || ct == "cmd_concealer" ||
      ct.contains("foundation")

    if (isFoundation) {
      val face = faceOvalBuf ?: return
      if (faceOvalCount < 3) return

      GLES20.glColorMask(false, false, false, false)
      GLES20.glStencilFunc(GLES20.GL_ALWAYS, 1, 0xFF)
      GLES20.glStencilOp(GLES20.GL_KEEP, GLES20.GL_KEEP, GLES20.GL_REPLACE)
      draw(face, faceOvalCount)

      GLES20.glStencilFunc(GLES20.GL_ALWAYS, 0, 0xFF)
      leftEyeBuf?.let { draw(it, leftEyeCount) }
      rightEyeBuf?.let { draw(it, rightEyeCount) }
      outerLipBuf?.let { draw(it, outerLipCount) }

      GLES20.glColorMask(true, true, true, true)
      GLES20.glStencilFunc(GLES20.GL_EQUAL, 1, 0xFF)
      draw(face, faceOvalCount)
    } else {
      val outer = outerLipBuf ?: return
      if (outerLipCount < 3) return

      GLES20.glColorMask(false, false, false, false)
      GLES20.glStencilFunc(GLES20.GL_ALWAYS, 1, 0xFF)
      GLES20.glStencilOp(GLES20.GL_KEEP, GLES20.GL_KEEP, GLES20.GL_REPLACE)
      draw(outer, outerLipCount)

      innerLipBuf?.let { GLES20.glStencilFunc(GLES20.GL_ALWAYS, 0, 0xFF); draw(it, innerLipCount) }

      GLES20.glColorMask(true, true, true, true)
      GLES20.glStencilFunc(GLES20.GL_EQUAL, 1, 0xFF)
      draw(outer, outerLipCount)
    }

    GLES20.glDisable(GLES20.GL_STENCIL_TEST)
  }

  fun setLook(layers: List<Triple<Int, Float, String>>, comp: Boolean) {
    layeredLookEnabled = true
    effectLayers = layers
    isCompareMode = comp
    hideAll = false
  }

  fun updateEffect(s: Int, i: Float, cat: String, comp: Boolean) {
    layeredLookEnabled = false
    effectLayers = emptyList()
    color[0] = Color.red(s) / 255f; color[1] = Color.green(s) / 255f; color[2] = Color.blue(s) / 255f
    color[3] = (if (cat.contains("face")) 0.3f else 0.6f) * i.coerceIn(0f, 1f)
    category = cat
    isCompareMode = comp
    hideAll = (cat == "cmd_haircolor" || cat == "cmd_hairstyle")
  }

  fun updateGeometry(o: List<PointF>, i: List<PointF>, f: List<PointF>, le: List<PointF>, re: List<PointF>, iw: Float, ih: Float, vw: Float, vh: Float, r: Int) {
    outerLipBuf = build(o, iw, ih, vw, vh, r); outerLipCount = o.size
    innerLipBuf = build(i, iw, ih, vw, vh, r); innerLipCount = i.size
    faceOvalBuf = build(f, iw, ih, vw, vh, r); faceOvalCount = f.size
    leftEyeBuf  = build(le, iw, ih, vw, vh, r); leftEyeCount  = le.size
    rightEyeBuf = build(re, iw, ih, vw, vh, r); rightEyeCount = re.size
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

    val sc: Float; val dx: Float; val dy: Float
    if (vAsp > iAsp) { sc = vw / rw; dx = 0f; dy = (vh - rh * sc) / 2f }
    else { sc = vh / rh; dy = 0f; dx = (vw - rw * sc) / 2f }

    val arr = FloatArray(pts.size * 2)
    for (idx in pts.indices) {
      val p = pts[idx]
      val (tx, ty) = when (rot) {
        90 -> 1f - p.y to p.x
        180 -> 1f - p.x to 1f - p.y
        270 -> p.y to 1f - p.x
        else -> p.x to p.y
      }
      val fx = 1f - tx
      val px = dx + fx * rw * sc
      val py = dy + ty * rh * sc

      if (isCompareMode) {
        val screenXNormalized = px / vw
        if (screenXNormalized < splitPosition) {
          arr[idx * 2] = -2f; arr[idx * 2 + 1] = -2f; continue
        }
      }

      arr[idx * 2]     = (px / vw) * 2f - 1f
      arr[idx * 2 + 1] = 1f - (py / vh) * 2f
    }
    return ByteBuffer.allocateDirect(arr.size * 4).order(java.nio.ByteOrder.nativeOrder()).asFloatBuffer().apply { put(arr); position(0) }
  }

  companion object {
    private const val VERT = "attribute vec2 aPos; void main() { gl_Position = vec4(aPos, 0.0, 1.0); }"
    private const val FRAG = """
      precision mediump float;
      uniform vec4 uColor;
      void main() {
        gl_FragColor = uColor;
      }
    """
  }
}
