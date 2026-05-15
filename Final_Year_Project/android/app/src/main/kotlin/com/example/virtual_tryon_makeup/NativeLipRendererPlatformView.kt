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
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.RectF
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.util.Log
import android.view.Surface
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
import java.util.concurrent.TimeUnit
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.sqrt
import kotlin.math.hypot
import org.tensorflow.lite.Interpreter

private const val VIEW_TYPE = "native_lip_renderer/view"
private const val CHANNEL_PREFIX = "native_lip_renderer"

// Lip mesh indices — must match iOS `NativeLipRendererPlugin.drawLips` (evenOdd outer + inner hole).
private val MP_LIP_OUTER_IOS = intArrayOf(
  61, 185, 40, 39, 37, 0, 267, 269, 270, 409, 291, 375, 321, 405, 314, 17, 84, 181, 91, 146
)
private val MP_LIP_INNER_IOS = intArrayOf(
  78, 191, 80, 81, 82, 13, 312, 311, 310, 415, 308, 324, 318, 402, 317, 14, 87, 178, 88, 95
)
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

  fun bindActivity(activity: Activity) {
    this.activity = activity
    // Platform view may be created before ActivityAware fires; keep reference in sync.
    lastView?.syncActivity(activity)
  }
  fun unbindActivity() {
    this.activity = null
    lastView?.syncActivity(null)
  }
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

  fun drawHairMask(bmp: Bitmap?) {
    val prev = hairBitmap
    hairBitmap = bmp
    if (prev != null && prev !== bmp) prev.recycle()
    visibility = if (bmp != null) View.VISIBLE else View.GONE
    postInvalidate()
  }
  fun clear() {
    hairBitmap?.recycle()
    hairBitmap = null
    postInvalidate()
  }

  override fun onDraw(canvas: Canvas) {
    val bmp = hairBitmap ?: return
    // Match iOS `hairMaskLayer.contentsGravity = .resizeAspectFill` + PreviewView FILL_CENTER:
    // uniform scale and center-crop so mask pixels line up with the visible camera frame.
    val vw = width.toFloat()
    val vh = height.toFloat()
    val bw = bmp.width.toFloat()
    val bh = bmp.height.toFloat()
    if (bw <= 0f || bh <= 0f) return
    val scale = max(vw / bw, vh / bh)
    val dw = bw * scale
    val dh = bh * scale
    val left = (vw - dw) / 2f
    val top = (vh - dh) / 2f
    canvas.drawBitmap(bmp, null, RectF(left, top, left + dw, top + dh), paint)
  }
}

/**
 * Match iOS `selectHairConfidenceMask(from:)` in `NativeLipRendererPlugin.swift`:
 * when two confidence masks exist, one is often a diffuse "background" map and the other
 * localizes hair. Picking the wrong one paints colour on the forehead / face centre.
 */
private fun selectHairConfidenceMask(masks: List<MPImage>): MPImage {
  if (masks.size <= 1) return masks[0]
  val m0 = masks[0]
  val m1 = masks[1]
  if (m0.width != m1.width || m0.height != m1.height) return m0

  fun floatData(mask: MPImage): FloatArray {
    val bb = ByteBufferExtractor.extract(mask)
    bb.rewind()
    val fb = bb.asFloatBuffer()
    val arr = FloatArray(fb.remaining())
    fb.get(arr)
    return arr
  }

  val w = m0.width
  val h = m0.height
  val fp0 = floatData(m0)
  val fp1 = floatData(m1)

  fun globalHighFraction(fp: FloatArray): Float {
    var hi = 0
    var tot = 0
    val step = max(1, min(w, h) / 80)
    var y = 0
    while (y < h) {
      var x = 0
      while (x < w) {
        tot++
        if (fp[y * w + x] > 0.4f) hi++
        x += step
      }
      y += step
    }
    return hi.toFloat() / max(1, tot)
  }

  fun meanTopBand(fp: FloatArray): Float {
    val yMax = max(1, h / 8)
    val step = max(1, min(w, h) / 96)
    var sum = 0f
    var n = 0
    var y = 0
    while (y < yMax) {
      var x = 0
      while (x < w) {
        sum += fp[y * w + x]
        n++
        x += step
      }
      y += step
    }
    return if (n > 0) sum / n else 0f
  }

  val g0 = globalHighFraction(fp0)
  val g1 = globalHighFraction(fp1)
  if (abs(g0 - g1) > 0.08f) {
    return if (g0 <= g1) m0 else m1
  }
  val t0 = meanTopBand(fp0)
  val t1 = meanTopBand(fp1)
  return if (t0 >= t1) m0 else m1
}

/**
 * [ImageAnalysis] buffers are in sensor orientation; [PreviewView] shows rotation + (front) mirror.
 * Face landmarks compensate via [mapNormToViewCover]; hair is a bitmap and must use the same
 * display transform or the tint sits on the wrong region (e.g. forehead).
 */
private fun orientHairMaskLikePreview(source: Bitmap, rotationDegrees: Int, mirrorX: Boolean): Bitmap {
  val rot = ((rotationDegrees % 360) + 360) % 360
  if (rot == 0 && !mirrorX) return source
  var b = source
  if (rot != 0) {
    val m = Matrix().apply { postRotate(rot.toFloat()) }
    val r = Bitmap.createBitmap(b, 0, 0, b.width, b.height, m, true)
    b.recycle()
    b = r
  }
  if (mirrorX) {
    val m = Matrix().apply { postScale(-1f, 1f, b.width / 2f, b.height / 2f) }
    val r = Bitmap.createBitmap(b, 0, 0, b.width, b.height, m, true)
    b.recycle()
    b = r
  }
  return b
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
  private val makeupVectorOverlay = MakeupVectorOverlayView(appContext)
  private val hairMaskOverlay: HairMaskOverlayView = HairMaskOverlayView(appContext)
  private val nailMaskOverlay: NailMaskOverlayView = NailMaskOverlayView(appContext)
  private val nailSegmentOverlay: NailSegmentOverlayView = NailSegmentOverlayView(appContext)
  private val nailRenderer: NailPolishRenderer = NailPolishRenderer(appContext)

  private var cameraProvider: ProcessCameraProvider? = null
  private var analyzer: ImageAnalysis? = null
  private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
  /** Hair segmentation + tint off the camera analyzer thread so frames are not stalled by ML. */
  private val hairExecutor: ExecutorService = Executors.newSingleThreadExecutor { r ->
    Thread(r, "hair_ml").apply { priority = Thread.NORM_PRIORITY + 2 }
  }
  private var eventSink: EventChannel.EventSink? = null
  private var startRequested = false

  private var faceLandmarker: FaceLandmarker? = null
  private var hairSegmenter: ImageSegmenter? = null
  private var handLandmarker: HandLandmarker? = null
  private var nailVideoTimestamp = 0L
  private var useBackCameraNails = false
  @Volatile private var processing = false
  private var rgbaBitmap: Bitmap? = null
  /** Live hair-colour EMA buffer (1/4-res ARGB); cleared for photo/style paths. */
  private var lastHairColorMaskPixels: IntArray? = null

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

  // Live face: temporal smooth (view px) + VIDEO landmarker timestamps.
  private var smoothedOuterLip: Array<PointF>? = null
  private var smoothedInnerLip: Array<PointF>? = null
  private var smoothedFaceOval: Array<PointF>? = null
  private var smoothedLeftEye: Array<PointF>? = null
  private var smoothedRightEye: Array<PointF>? = null
  @Volatile private var faceVideoTimestampMs = 0L

  init {
    methodChannel.setMethodCallHandler(this)
    eventChannel.setStreamHandler(this)
    previewView.scaleType = PreviewView.ScaleType.FILL_CENTER
    // TextureView path: more consistent overlay alignment vs SurfaceView + GL on many OEMs.
    previewView.implementationMode = PreviewView.ImplementationMode.COMPATIBLE

    container.addView(previewView, FrameLayout.LayoutParams(-1, -1))
    container.addView(glOverlay, FrameLayout.LayoutParams(-1, -1))
    container.addView(makeupVectorOverlay, FrameLayout.LayoutParams(-1, -1))
    container.addView(hairMaskOverlay, FrameLayout.LayoutParams(-1, -1))
    container.addView(nailSegmentOverlay, FrameLayout.LayoutParams(-1, -1))  // TFLite mask (preferred)
    container.addView(nailMaskOverlay, FrameLayout.LayoutParams(-1, -1))     // Landmark fallback
    hairMaskOverlay.alpha = 1f
    nailMaskOverlay.visibility = View.GONE
    nailSegmentOverlay.visibility = View.GONE
    makeupVectorOverlay.visibility = View.GONE
  }

  /** [LipRendererFactory] may receive the [Activity] after this view is created; keep in sync. */
  fun syncActivity(a: Activity?) {
    activity = a
    if (startRequested && hasCameraPermission()) {
      startCameraIfReady()
    }
  }

  override fun getView() = container

  override fun dispose() {
    stopCamera()
    eventChannel.setStreamHandler(null)
    methodChannel.setMethodCallHandler(null)
    cameraExecutor.shutdown()
    hairExecutor.shutdown()
    try {
      if (!hairExecutor.awaitTermination(2, TimeUnit.SECONDS)) {
        hairExecutor.shutdownNow()
      }
    } catch (_: InterruptedException) {
      hairExecutor.shutdownNow()
    }
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
    lastHairColorMaskPixels = null
    nailRenderer.close()
  }

  /** Normalize AR category from Flutter (e.g. legacy "rouge" → blush vector path). */
  private fun canonicalArCategory(raw: String): String {
    val c = raw.trim().lowercase()
    if (c == "cmd_rouge" || c == "rouge") return "cmd_blush"
    return c
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "start" -> { startRequested = true; startCameraIfReady(); result.success(null) }
      "stop" -> { startRequested = false; stopCamera(); result.success(null) }
      "setEffect" -> {
        val args = call.arguments as? Map<*, *>
        val shade = (args?.get("shade") as? Number)?.toInt() ?: 0
        val intensity = (args?.get("intensity") as? Number)?.toFloat() ?: 0.7f
        val categoryRaw = args?.get("category") as? String ?: "cmd_lipstick"
        val category = canonicalArCategory(categoryRaw)
        val compare = when (val v = args?.get("isCompareMode")) {
          is Boolean -> v
          is Number -> v.toInt() != 0
          else -> false
        }
        val hairShape = args?.get("hairStyleShape") as? String
        if (hairShape != null) currentHairStyleShape = hairShape.lowercase()
        currentNailArtStyle = (args?.get("nailArtStyle") as? Number)?.toInt() ?: 0
        currentNailShape = (args?.get("nailShape") as? Number)?.toInt() ?: 0

        val wasNails = currentCategory == "cmd_nails"
        val wasHair = currentCategory == "cmd_haircolor" || currentCategory == "cmd_hairstyle"
        currentCategory = category
        useLayeredLook = false
        lookLayers = emptyList()
        isCompareMode = compare
        currentShadeColor = shade
        currentIntensity = intensity

        val isNails = category == "cmd_nails"
        val isHair = category == "cmd_haircolor" || category == "cmd_hairstyle"
        if (wasHair != isHair || wasNails != isNails) resetFaceSmoothing()

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
            makeupVectorOverlay.clear()
            makeupVectorOverlay.visibility = View.GONE
            nailSegmentOverlay.visibility = View.VISIBLE
            nailMaskOverlay.visibility = View.VISIBLE  // fallback if model not loaded
          } else {
            nailSegmentOverlay.clear()
            nailSegmentOverlay.visibility = View.GONE
            nailMaskOverlay.clear()
            nailMaskOverlay.visibility = View.GONE
            when {
              isHair -> {
                makeupVectorOverlay.clear()
                makeupVectorOverlay.visibility = View.GONE
                glOverlay.hideAllOverlays()
                hairMaskOverlay.visibility = View.VISIBLE
              }
              usesCanvasOverlay(category) -> {
                makeupVectorOverlay.visibility = View.VISIBLE
                glOverlay.hideAllOverlays()
              }
              else -> {
                makeupVectorOverlay.clear()
                makeupVectorOverlay.visibility = View.GONE
                glOverlay.showOverlays()
              }
            }
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
        val compare = when (val v = args["isCompareMode"]) {
          is Boolean -> v
          is Number -> v.toInt() != 0
          else -> false
        }
        val raw = args["layers"] as? List<*> ?: emptyList<Any>()
        val layers = mutableListOf<Triple<Int, Float, String>>()
        for (item in raw) {
          val m = item as? Map<*, *> ?: continue
          val shade = (m["shade"] as? Number)?.toInt() ?: continue
          val intensity = (m["intensity"] as? Number)?.toFloat() ?: 0.4f
          val category = canonicalArCategory((m["category"] as? String) ?: continue)
          if (category.lowercase() == "cmd_none") continue
          layers.add(Triple(shade, intensity, category))
        }
        val capped = if (layers.size > 10) layers.take(10) else layers
        lookLayers = capped
        useLayeredLook = capped.isNotEmpty()
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
        (when (val v = args?.get("isCompareMode")) {
          is Boolean -> v
          is Number -> v.toInt() != 0
          else -> null
        })?.let { isCompareMode = it }
        currentSplitPosition = split
        glOverlay.setCalibration(split, isCompareMode)
        android.os.Handler(android.os.Looper.getMainLooper()).post {
          makeupVectorOverlay.applyCompareCalibration(isCompareMode, split)
        }
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  override fun onListen(args: Any?, events: EventChannel.EventSink?) { eventSink = events; if (startRequested) startCameraIfReady() }
  override fun onCancel(args: Any?) { eventSink = null }

  fun onPermissionResult(granted: Boolean) {
    if (granted) {
      startCameraIfReady()
    } else {
      Log.w("LipRenderer", "CAMERA permission denied")
      eventSink?.success(
        mapOf(
          "type" to "error",
          "code" to "permission_denied",
          "message" to "Camera permission is required for live try-on.",
        ),
      )
    }
  }

  private fun startCameraIfReady() {
    if (!startRequested) return

    if (!hasCameraPermission()) {
      val act = activity
      if (act != null) {
        ActivityCompat.requestPermissions(
          act,
          arrayOf(Manifest.permission.CAMERA),
          CAMERA_PERMISSION_REQUEST,
        )
      } else {
        Log.w("LipRenderer", "Cannot request CAMERA: activity is null")
        eventSink?.success(
          mapOf(
            "type" to "error",
            "code" to "no_activity",
            "message" to "Camera is not ready yet. Close and reopen live try-on.",
          ),
        )
      }
      return
    }

    val lifecycleOwner = (activity as? LifecycleOwner) ?: run {
      Log.w("LipRenderer", "Activity is not a LifecycleOwner")
      eventSink?.success(
        mapOf(
          "type" to "error",
          "code" to "no_lifecycle",
          "message" to "Camera requires an active screen.",
        ),
      )
      return
    }

    val providerFuture = ProcessCameraProvider.getInstance(appContext)
    providerFuture.addListener({
      val provider = providerFuture.get()
      bindCamera(provider, lifecycleOwner)
    }, ContextCompat.getMainExecutor(appContext))
  }

  private fun bindCamera(provider: ProcessCameraProvider, lifecycleOwner: LifecycleOwner) {
    val targetRot = previewView.display?.rotation ?: Surface.ROTATION_0
    val preview = Preview.Builder()
      .setTargetRotation(targetRot)
      .build()
      .also { it.setSurfaceProvider(previewView.surfaceProvider) }
    analyzer = ImageAnalysis.Builder()
      .setTargetRotation(targetRot)
      .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
      .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
      .build()
      .also { it.setAnalyzer(cameraExecutor) { image -> processFrame(image) } }

    val selector =
      if (currentCategory == "cmd_nails") CameraSelector.DEFAULT_BACK_CAMERA
      else CameraSelector.DEFAULT_FRONT_CAMERA

    provider.unbindAll()
    resetFaceSmoothing()
    faceVideoTimestampMs = 0L
    provider.bindToLifecycle(lifecycleOwner, selector, preview, analyzer)
    cameraProvider = provider
    nailVideoTimestamp = 0L
    eventSink?.success(mapOf("type" to "ready"))
  }

  private fun stopCamera() {
    cameraProvider?.unbindAll()
    analyzer?.clearAnalyzer()
    cameraProvider = null
    resetFaceSmoothing()
    faceVideoTimestampMs = 0L
  }
  private fun hasCameraPermission() = ContextCompat.checkSelfPermission(appContext, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

  // ─── Route per-frame processing based on mode ─────────────────────────────
  private fun isHairSegmentationMode(): Boolean =
    currentCategory == "cmd_haircolor" || currentCategory == "cmd_hairstyle"

  private fun isNailMode(): Boolean = currentCategory == "cmd_nails"

  private fun processFrame(image: ImageProxy) {
    val isHair = isHairSegmentationMode()
    val isNails = isNailMode()

    if (!isHair) {
      if (processing) {
        image.close()
        return
      }
      processing = true
    }

    val width = image.width
    val height = image.height
    if (rgbaBitmap == null || rgbaBitmap?.width != width || rgbaBitmap?.height != height) {
      rgbaBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    }

    val plane = image.planes[0]
    rgbaBitmap?.copyPixelsFromBuffer(plane.buffer)

    if (isHair) {
      val rot = image.imageInfo.rotationDegrees
      val categoryAtEnqueue = currentCategory
      val snap = rgbaBitmap!!.copy(Bitmap.Config.ARGB_8888, false)
      image.close()
      scheduleLiveHairSegmentation(snap, rot, categoryAtEnqueue)
      return
    }

    val mpImage = BitmapImageBuilder(rgbaBitmap).build()
    when {
      isNails -> runHandNails(mpImage, image)
      else -> runFaceMesh(mpImage, image)
    }
  }

  /** Runs on [hairExecutor]; [frameCopy] is recycled here. */
  private fun scheduleLiveHairSegmentation(frameCopy: Bitmap, rotationDegrees: Int, categoryAtEnqueue: String) {
    hairExecutor.execute {
      try {
        if (currentCategory != categoryAtEnqueue) return@execute
        if (!ensureHairSegmenter()) return@execute
        val mpImage = BitmapImageBuilder(frameCopy).build()
        val result = try {
          hairSegmenter!!.segment(mpImage)
        } catch (t: Throwable) {
          Log.e("HairSegmenter", "Segmentation error", t)
          return@execute
        }
        if (currentCategory != categoryAtEnqueue) return@execute
        val coloredBitmap = if (currentCategory == "cmd_hairstyle") {
          buildHairStyleEffectBitmap(result, cameraTexture = frameCopy)
        } else {
          buildHairColorBitmap(result, cameraTexture = frameCopy)
        }
        val intensity = currentIntensity
        val mirrorX = !useBackCameraNails
        val oriented = coloredBitmap?.let { orientHairMaskLikePreview(it, rotationDegrees, mirrorX) }
        if (oriented != null) {
          android.os.Handler(android.os.Looper.getMainLooper()).post {
            hairMaskOverlay.drawHairMask(oriented)
            hairMaskOverlay.alpha = intensity
            glOverlay.hideAllOverlays()
            makeupVectorOverlay.clear()
            makeupVectorOverlay.visibility = View.GONE
          }
        }
      } finally {
        frameCopy.recycle()
      }
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

  /** Normalized landmark (same space as MediaPipe on [ImageAnalysis] buffer) → [PreviewView] px. */
  private fun mapNormListToPreview(
    norm: List<PointF>,
    iw: Int,
    ih: Int,
    rot: Int,
    vw: Float,
    vh: Float,
    mirrorX: Boolean,
  ): List<PointF> =
    norm.map { p -> mapNormToViewCover(p.x, p.y, iw, ih, rot, vw, vh, mirrorX) }

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

  private fun resetFaceSmoothing() {
    smoothedOuterLip = null
    smoothedInnerLip = null
    smoothedFaceOval = null
    smoothedLeftEye = null
    smoothedRightEye = null
  }

  /**
   * Adaptive EMA on view-space lip/face polys (same idea as iOS nail TIP smoothing):
   * still frames get heavy smoothing; fast head motion follows raw mesh more.
   *
   * @param blushMode when true ([cmd_blush]), slightly faster tracking on cheek polys than lipstick.
   */
  private fun emaSmoothViewPolygon(
    raw: List<PointF>,
    prev: Array<PointF>?,
    vw: Float,
    vh: Float,
    foundationMode: Boolean = false,
    blushMode: Boolean = false,
  ): Pair<List<PointF>, Array<PointF>> {
    val n = raw.size
    val denom = max(vw, vh).coerceAtLeast(1f)
    if (prev == null || prev.size != n) {
      val arr = Array(n) { i -> PointF(raw[i].x, raw[i].y) }
      return Pair(List(n) { i -> PointF(raw[i].x, raw[i].y) }, arr)
    }
    var sumD = 0f
    for (i in 0 until n) {
      sumD += hypot(raw[i].x - prev[i].x, raw[i].y - prev[i].y)
    }
    val meanD = sumD / n.toFloat().coerceAtLeast(1f)
    var normMotion = (meanD / denom).coerceIn(0f, 1f)
    if (foundationMode) {
      var rcx = 0f
      var rcy = 0f
      var pcx = 0f
      var pcy = 0f
      for (i in 0 until n) {
        rcx += raw[i].x
        rcy += raw[i].y
        pcx += prev[i].x
        pcy += prev[i].y
      }
      val inv = 1f / n.toFloat()
      rcx *= inv
      rcy *= inv
      pcx *= inv
      pcy *= inv
      val centroidMotion = hypot(rcx - pcx, rcy - pcy) / denom
      normMotion = max(normMotion, (centroidMotion * 2.4f).coerceIn(0f, 1f))
    }
    val a = when {
      foundationMode -> (0.40f + 0.54f * normMotion).coerceIn(0.28f, 0.97f)
      blushMode -> (0.30f + 0.63f * normMotion).coerceIn(0.17f, 0.92f)
      else -> (0.26f + 0.64f * normMotion).coerceIn(0.14f, 0.93f)
    }
    val out = Array(n) { i ->
      val r = raw[i]
      val p = prev[i]
      PointF(a * r.x + (1f - a) * p.x, a * r.y + (1f - a) * p.y)
    }
    return Pair(out.map { PointF(it.x, it.y) }, out)
  }

  private fun usesVectorMakeup(cat: String): Boolean =
    when (cat.trim().lowercase()) {
      "cmd_blush", "cmd_highlight", "cmd_eyeshadow", "cmd_eye", "cmd_mascara",
      "cmd_eyebrow", "cmd_eyeliner", "cmd_lipliner" -> true
      else -> false
    }

  /** Canvas overlay: vector makeup **or** full-face foundation (GL triangle fan is wrong on concave face). */
  private fun usesCanvasOverlay(cat: String): Boolean =
    usesVectorMakeup(cat) || isFoundationCategory(cat)

  // ─── Face landmarks → GL lip/makeup overlay ───────────────────────────────
  private fun runFaceMesh(mpImage: MPImage, image: ImageProxy) {
    if (!ensureLandmarker()) { processing = false; image.close(); return }

    val tsMs = (image.imageInfo.timestamp / 1_000_000L).coerceAtLeast(0L)
    faceVideoTimestampMs = if (tsMs > faceVideoTimestampMs) tsMs else faceVideoTimestampMs + 16L

    val result = try {
      faceLandmarker?.detectForVideo(mpImage, faceVideoTimestampMs)
    } catch (t: Throwable) {
      Log.e("LipRenderer", "detectForVideo", t)
      null
    }
    val landmarks = result?.faceLandmarks()?.firstOrNull()

    if (landmarks == null) {
      resetFaceSmoothing()
      android.os.Handler(android.os.Looper.getMainLooper()).post {
        makeupVectorOverlay.clear()
      }
    } else if (previewView.width >= 2 && previewView.height >= 2) {
      val outerLipIdx = MP_LIP_OUTER_IOS
      val innerLipIdx = MP_LIP_INNER_IOS
      // 109→151→338 only; avoid 9/337/108 (re-entrant path + evenOdd = forehead hole).
      val faceOvalIdx = intArrayOf(338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109, 151, 10)
      val leftEyeIdx  = intArrayOf(33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246)
      val rightEyeIdx = intArrayOf(362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398)

      val vw = previewView.width.toFloat().coerceAtLeast(1f)
      val vh = previewView.height.toFloat().coerceAtLeast(1f)
      val rot = image.imageInfo.rotationDegrees
      val iw = image.width
      val ih = image.height
      // Front camera: mirror overlay to match PreviewView selfie mirroring; back (nails) = false.
      val mirrorX = !useBackCameraNails

      val outerNorm = outerLipIdx.map { PointF(landmarks[it].x(), landmarks[it].y()) }
      val innerNorm = innerLipIdx.map { PointF(landmarks[it].x(), landmarks[it].y()) }
      val faceNorm = if (currentCategory == "cmd_face" ||
        currentCategory.contains("foundation", ignoreCase = true) ||
        currentCategory.contains("concealer", ignoreCase = true)
      ) {
        foundationFaceOvalPoints(landmarks, faceOvalIdx)
      } else {
        faceOvalIdx.map { PointF(landmarks[it].x(), landmarks[it].y()) }
      }
      val leftNorm = leftEyeIdx.map { PointF(landmarks[it].x(), landmarks[it].y()) }
      val rightNorm = rightEyeIdx.map { PointF(landmarks[it].x(), landmarks[it].y()) }

      val outerRaw = mapNormListToPreview(outerNorm, iw, ih, rot, vw, vh, mirrorX)
      val innerRaw = mapNormListToPreview(innerNorm, iw, ih, rot, vw, vh, mirrorX)
      val faceRaw = mapNormListToPreview(faceNorm, iw, ih, rot, vw, vh, mirrorX)
      val leftRaw = mapNormListToPreview(leftNorm, iw, ih, rot, vw, vh, mirrorX)
      val rightRaw = mapNormListToPreview(rightNorm, iw, ih, rot, vw, vh, mirrorX)

      val foundationSmooth = isFoundationCategory(currentCategory)
      val blushSmooth = currentCategory.trim().lowercase() == "cmd_blush"
      val (outerLip, oNext) = emaSmoothViewPolygon(outerRaw, smoothedOuterLip, vw, vh, foundationSmooth, blushSmooth)
      val (innerLip, iNext) = emaSmoothViewPolygon(innerRaw, smoothedInnerLip, vw, vh, foundationSmooth, blushSmooth)
      val (faceOval, fNext) = emaSmoothViewPolygon(faceRaw, smoothedFaceOval, vw, vh, foundationSmooth, blushSmooth)
      val (leftEye, leNext) = emaSmoothViewPolygon(leftRaw, smoothedLeftEye, vw, vh, foundationSmooth, blushSmooth)
      val (rightEye, reNext) = emaSmoothViewPolygon(rightRaw, smoothedRightEye, vw, vh, foundationSmooth, blushSmooth)
      smoothedOuterLip = oNext
      smoothedInnerLip = iNext
      smoothedFaceOval = fNext
      smoothedLeftEye = leNext
      smoothedRightEye = reNext

      val catKey = currentCategory.trim().lowercase()
      when {
        usesVectorMakeup(catKey) -> {
          val nLm = landmarks.size
          val lmPts = Array(nLm) { j ->
            mapNormToViewCover(
              landmarks[j].x(),
              landmarks[j].y(),
              iw, ih, rot, vw, vh, mirrorX,
            )
          }
          android.os.Handler(android.os.Looper.getMainLooper()).post {
            val c = currentCategory.trim().lowercase()
            if (!usesVectorMakeup(c)) return@post
            makeupVectorOverlay.visibility = View.VISIBLE
            makeupVectorOverlay.update(
              lmPts,
              currentCategory,
              currentShadeColor,
              currentIntensity,
              isCompareMode,
              currentSplitPosition,
            )
            glOverlay.hideAllOverlays()
          }
        }
        isFoundationCategory(currentCategory) -> {
          android.os.Handler(android.os.Looper.getMainLooper()).post {
            if (!isFoundationCategory(currentCategory)) return@post
            makeupVectorOverlay.updateFoundationPolys(
              faceOval,
              outerLip,
              innerLip,
              leftEye,
              rightEye,
              currentCategory,
              currentShadeColor,
              currentIntensity,
              isCompareMode,
              currentSplitPosition,
            )
            makeupVectorOverlay.visibility = View.VISIBLE
            glOverlay.hideAllOverlays()
          }
        }
        else -> {
          android.os.Handler(android.os.Looper.getMainLooper()).post {
            val c = currentCategory.trim().lowercase()
            if (!usesCanvasOverlay(c)) {
              makeupVectorOverlay.clear()
              makeupVectorOverlay.visibility = View.GONE
              glOverlay.showOverlays()
            }
          }
          glOverlay.setLandmarks(outerLip, innerLip, faceOval, leftEye, rightEye, vw, vh)
        }
      }
    }

    processing = false
    image.close()
  }

  // ─── Luminance-boosted HSL hair colour bitmap ─────────────────────────────
  //
  // Aligned with iOS `processHairMask` (plain hair, no style shape):
  //   • Mask: 3×3 average on confidence, smoothstep; live colour uses lo ≈ 0.24 to cut background bleed.
  //   • Saturation: blend 75% source + 25% target (accentBoost) so colour follows fibre variation.
  //   • Luminance: max(srcL, tgtL×0.75) then + v×0.04 toward crown.
  //   • Live preview: temporal EMA on ARGB buffer (favour new frame for motion); photo path clears buffer (sourceBmp != null).
  //   • View.alpha = intensity (global strength).
  private fun buildHairColorBitmap(
    result: ImageSegmenterResult,
    sourceBmp: Bitmap? = null,
    hairShadeColor: Int = currentShadeColor,
    /** Live path: sample this buffer for underlying hair colour while keeping EMA (do not pass as [sourceBmp]). */
    cameraTexture: Bitmap? = null,
  ): Bitmap? {
    val masks = result.confidenceMasks().orElse(null) ?: return null
    if (masks.isEmpty()) return null

    val hairMaskImg = selectHairConfidenceMask(masks)
    val maskW = hairMaskImg.width
    val maskH = hairMaskImg.height
    if (maskW <= 0 || maskH <= 0) return null

    val byteBuffer = ByteBufferExtractor.extract(hairMaskImg)
    byteBuffer.rewind()
    val floatBuffer = byteBuffer.asFloatBuffer()
    val floatData = FloatArray(floatBuffer.capacity())
    floatBuffer.get(floatData)

    val tRf = Color.red(hairShadeColor)   / 255f
    val tGf = Color.green(hairShadeColor) / 255f
    val tBf = Color.blue(hairShadeColor)  / 255f
    val (tgtH, tgtS, tgtL) = rgbToHSL(tRf, tGf, tBf)

    val srcBmp = cameraTexture ?: sourceBmp ?: rgbaBitmap
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
      val v = py.toFloat() / max(1f, procH.toFloat())

      // Sample confidence mask at 4× step
      val mx   = min(maskW - 1, px * scale)
      val my   = min(maskH - 1, py * scale)
      var conf = hairMaskConf3x3(floatData, maskW, maskH, mx, my).coerceIn(0f, 1f)

      val lo = 0.24f
      conf = if (conf < lo) 0f
             else { val t = (conf - lo) / (1f - lo); t * t * (3f - 2f * t) }

      val alpha = (conf * 255f).toInt().coerceIn(0, 255)
      if (alpha == 0) { pixels[i] = 0; continue }

      // Sample camera bitmap at corresponding position
      val srcX = (px * srcW / procW).coerceIn(0, srcW - 1)
      val srcY = (py * srcH / procH).coerceIn(0, srcH - 1)

      val srcPixel = srcBmp?.getPixel(srcX, srcY) ?: hairShadeColor
      val srcR = Color.red(srcPixel)   / 255f
      val srcG = Color.green(srcPixel) / 255f
      val srcB = Color.blue(srcPixel)  / 255f

      val (_, srcS, srcL) = rgbToHSL(srcR, srcG, srcB)

      // Match iOS processHairMask (plain hair): keep some natural saturation so dye
      // does not look like flat poster colour on dark hair.
      val accentBoost = 0.25f
      val effS = ((srcS * (1f - accentBoost)) + (tgtS * accentBoost)).coerceIn(0f, 1f)

      // Luminance floor (bleach-ish lift on dark fibres) + slight crown brightening (v).
      var resultL = max(srcL, tgtL * 0.75f)
      resultL = min(1f, resultL + v * 0.04f)

      val (outR, outG, outB) = hslToRGB(tgtH, effS, resultL)

      val aN  = alpha / 255f
      val pR  = (outR * aN * 255f).toInt().coerceIn(0, 255)
      val pG  = (outG * aN * 255f).toInt().coerceIn(0, 255)
      val pB  = (outB * aN * 255f).toInt().coerceIn(0, 255)
      pixels[i] = Color.argb(alpha, pR, pG, pB)
    }

    if (sourceBmp != null) {
      lastHairColorMaskPixels = null
    } else {
      val prev = lastHairColorMaskPixels
      if (prev != null && prev.size == pixels.size) {
        val nw = 0.88f
        val ow = 1f - nw
        for (i in pixels.indices) {
          val c = pixels[i]
          val p = prev[i]
          pixels[i] = Color.argb(
            (Color.alpha(c) * nw + Color.alpha(p) * ow).toInt().coerceIn(0, 255),
            (Color.red(c) * nw + Color.red(p) * ow).toInt().coerceIn(0, 255),
            (Color.green(c) * nw + Color.green(p) * ow).toInt().coerceIn(0, 255),
            (Color.blue(c) * nw + Color.blue(p) * ow).toInt().coerceIn(0, 255),
          )
        }
      }
      lastHairColorMaskPixels = pixels.copyOf()
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

  /** 3×3 box average on segmenter confidence (reduces blocky noise with mask scale=4). */
  private fun hairMaskConf3x3(floatData: FloatArray, maskW: Int, maskH: Int, mx: Int, my: Int): Float {
    var sum = 0f
    for (dy in -1..1) {
      for (dx in -1..1) {
        val x = (mx + dx).coerceIn(0, maskW - 1)
        val y = (my + dy).coerceIn(0, maskH - 1)
        sum += floatData[y * maskW + x]
      }
    }
    return sum * (1f / 9f)
  }

  /// Style Match: MediaPipe hair mask + accent tint with per-shape grading (constrained to hair pixels).
  private fun buildHairStyleEffectBitmap(
    result: ImageSegmenterResult,
    sourceBmp: Bitmap? = null,
    hairShadeColor: Int = currentShadeColor,
    cameraTexture: Bitmap? = null,
  ): Bitmap? {
    lastHairColorMaskPixels = null

    val masks = result.confidenceMasks().orElse(null) ?: return null
    if (masks.isEmpty()) return null

    val hairMaskImg = selectHairConfidenceMask(masks)
    val maskW = hairMaskImg.width
    val maskH = hairMaskImg.height
    if (maskW <= 0 || maskH <= 0) return null

    val byteBuffer = ByteBufferExtractor.extract(hairMaskImg)
    byteBuffer.rewind()
    val floatBuffer = byteBuffer.asFloatBuffer()
    val floatData = FloatArray(floatBuffer.capacity())
    floatBuffer.get(floatData)

    val tRf = Color.red(hairShadeColor) / 255f
    val tGf = Color.green(hairShadeColor) / 255f
    val tBf = Color.blue(hairShadeColor) / 255f
    val (tgtH0, tgtS0, tgtL0) = rgbToHSL(tRf, tGf, tBf)
    var tgtH = tgtH0
    var tgtS = tgtS0
    var tgtL = tgtL0

    val srcBmp = cameraTexture ?: sourceBmp ?: rgbaBitmap
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
      var conf = hairMaskConf3x3(floatData, maskW, maskH, mx, my).coerceIn(0f, 1f)

      val lo = 0.20f
      conf = if (conf < lo) 0f
      else {
        val t = (conf - lo) / (1f - lo)
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

      val srcPixel = srcBmp?.getPixel(srcX, srcY) ?: hairShadeColor
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
    val outerLipIdx = MP_LIP_OUTER_IOS
    val innerLipIdx = MP_LIP_INNER_IOS
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
    // iOS: `shade.withAlphaComponent(intensity)` for default lipstick.
    val alpha = (255 * intensity.coerceIn(0f, 1f)).toInt().coerceIn(0, 255)
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
    // iOS foundation: `max(0.20, min(0.65, intensity * 0.7))`
    val a = min(0.65f, max(0.20f, intensity.coerceIn(0f, 1f) * 0.7f))
    val alpha = (255 * a).toInt().coerceIn(51, 166)
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

  private fun drawPhotoCategory(
    canvas: Canvas,
    landmarks: List<NormalizedLandmark>,
    category: String,
    shade: Int,
    intensity: Float,
    w: Int,
    h: Int,
    photoArgb: Bitmap,
  ) {
    val c = category.lowercase()
    when {
      c == "cmd_haircolor" || c == "cmd_hairstyle" -> {
        if (!ensureHairSegmenter()) return
        val segBmp = downscalePhotoBitmap(photoArgb, 1024)
        try {
          val mpImg = BitmapImageBuilder(segBmp).build()
          val segResult = try {
            hairSegmenter!!.segment(mpImg)
          } catch (t: Throwable) {
            Log.e("HairSegmenter", "Photo segment", t)
            return
          }
          val colored = if (c == "cmd_hairstyle") {
            buildHairStyleEffectBitmap(segResult, segBmp, shade)
          } else {
            buildHairColorBitmap(segResult, segBmp, shade)
          } ?: return
          val p = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
            alpha = (255 * intensity.coerceIn(0f, 1f)).toInt().coerceIn(0, 255)
          }
          canvas.drawBitmap(colored, null, Rect(0, 0, w, h), p)
        } finally {
          if (segBmp !== photoArgb) segBmp.recycle()
        }
      }
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
        drawPhotoCategory(canvas, landmarks, layer.third, layer.first, layer.second, w, h, out)
      }
    } else {
      drawPhotoCategory(canvas, landmarks, currentCategory, currentShadeColor, currentIntensity, w, h, out)
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
        .setRunningMode(RunningMode.VIDEO)
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
  fun setCalibration(split: Float, compare: Boolean) = queueEvent {
    renderer.splitPosition = split
    renderer.isCompareMode = compare
  }
  /** [vw]/[vh] must match the space used in [mapNormListToPreview] (typically [PreviewView] size). */
  fun setLandmarks(o: List<PointF>, i: List<PointF>, f: List<PointF>, le: List<PointF>, re: List<PointF>, vw: Float, vh: Float) =
    queueEvent { renderer.updateGeometryViewPixels(o, i, f, le, re, vw, vh) }
  fun hideAllOverlays() = queueEvent { renderer.hideAll = true }
  fun showOverlays() = queueEvent { renderer.hideAll = false }
}

private class LipMaskRenderer : GLSurfaceView.Renderer {
  private var program = 0
  private var colorHandle = 0
  private var posHandle = 0
  private var clipCompareHandle = -1
  private var splitMinXHandle = -1

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
  private var viewportWidth = 0
  private var viewportHeight = 0
  @Volatile private var color = floatArrayOf(1f, 0f, 0f, 0.5f)
  @Volatile private var category = "cmd_lipstick"
  @Volatile var isCompareMode = false
  /// When true, [onDrawFrame] uses [effectLayers] instead of single [category] (may be empty = clear).
  @Volatile private var layeredLookEnabled = false
  @Volatile private var effectLayers: List<Triple<Int, Float, String>> = emptyList()

  /** Fragment alpha aligned with iOS `NativeLipRendererPlugin` per-category fills. */
  private fun resolveFillAlpha(category: String, intensity: Float): Float {
    val i = intensity.coerceIn(0f, 1f)
    val ct = category.lowercase()
    if (ct == "cmd_face" || ct.contains("foundation") || ct.contains("concealer"))
      return min(0.65f, max(0.20f, i * 0.7f))
    if (ct == "cmd_blush") {
      val t = i.toDouble().pow(0.52).toFloat()
      return max(0.08f, 0.30f * t)
    }
    if (ct == "cmd_highlight" || ct == "cmd_highlighter")
      return max(0.05f, min(0.34f, 0.13f * i))
    if (ct == "cmd_eyeshadow" || ct == "cmd_shadow")
      return max(0.14f, min(0.34f, i * 0.24f))
    // Default lipstick / liner / brow etc.: iOS uses `withAlphaComponent(intensity)`.
    return i
  }

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
    clipCompareHandle = GLES20.glGetUniformLocation(program, "uClipCompare")
    splitMinXHandle = GLES20.glGetUniformLocation(program, "uSplitMinX")
  }

  /** Compare mask in **fragment** space (matches iOS right-half “after”); avoids flaky `glScissor` on translucent surfaces. */
  private fun applyCompareClipUniforms() {
    if (clipCompareHandle < 0 || splitMinXHandle < 0) return
    val vw = viewportWidth
    if (isCompareMode && vw > 0) {
      GLES20.glUniform1f(clipCompareHandle, 1f)
      GLES20.glUniform1f(splitMinXHandle, splitPosition.coerceIn(0f, 1f) * vw)
    } else {
      GLES20.glUniform1f(clipCompareHandle, 0f)
      GLES20.glUniform1f(splitMinXHandle, 0f)
    }
  }

  override fun onSurfaceChanged(gl: GL10?, w: Int, h: Int) {
    GLES20.glViewport(0, 0, w, h)
    viewportWidth = w
    viewportHeight = h
  }

  override fun onDrawFrame(gl: GL10?) {
    GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_STENCIL_BUFFER_BIT)

    // Hair mode is handled by HairMaskOverlayView; nothing to draw here
    if (hideAll) return

    GLES20.glUseProgram(program)
    applyCompareClipUniforms()

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
        color[3] = resolveFillAlpha(cat, i)
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
    isCompareMode = comp
    hideAll = false
    if (layers.isEmpty()) {
      layeredLookEnabled = false
      effectLayers = emptyList()
      return
    }
    layeredLookEnabled = true
    effectLayers = layers
  }

  fun updateEffect(s: Int, i: Float, cat: String, comp: Boolean) {
    layeredLookEnabled = false
    effectLayers = emptyList()
    color[0] = Color.red(s) / 255f; color[1] = Color.green(s) / 255f; color[2] = Color.blue(s) / 255f
    color[3] = resolveFillAlpha(cat, i)
    category = cat
    isCompareMode = comp
    val c = cat.trim().lowercase()
    val vectorMakeup = when (c) {
      "cmd_blush", "cmd_highlight", "cmd_eyeshadow", "cmd_eye", "cmd_mascara",
      "cmd_eyebrow", "cmd_eyeliner", "cmd_lipliner" -> true
      else -> false
    }
    val foundationCanvas = c == "cmd_face" || c == "cmd_foundation" || c == "cmd_concealer" ||
      c.contains("foundation")
    hideAll = (cat == "cmd_haircolor" || cat == "cmd_hairstyle" || vectorMakeup || foundationCanvas)
  }

  fun updateGeometryViewPixels(o: List<PointF>, i: List<PointF>, f: List<PointF>, le: List<PointF>, re: List<PointF>, vw: Float, vh: Float) {
    outerLipBuf = buildFromViewPixels(o, vw, vh); outerLipCount = o.size
    innerLipBuf = buildFromViewPixels(i, vw, vh); innerLipCount = i.size
    faceOvalBuf = buildFromViewPixels(f, vw, vh); faceOvalCount = f.size
    leftEyeBuf  = buildFromViewPixels(le, vw, vh); leftEyeCount  = le.size
    rightEyeBuf = buildFromViewPixels(re, vw, vh); rightEyeCount = re.size
  }

  private fun draw(b: java.nio.FloatBuffer, c: Int) {
    GLES20.glEnableVertexAttribArray(posHandle)
    GLES20.glVertexAttribPointer(posHandle, 2, GLES20.GL_FLOAT, false, 0, b)
    GLES20.glDrawArrays(GLES20.GL_TRIANGLE_FAN, 0, c)
  }

  /** NDC from view pixels; rotation/mirror/cover already applied in [mapNormToViewCover]. */
  private fun buildFromViewPixels(pts: List<PointF>, vw: Float, vh: Float): java.nio.FloatBuffer {
    val vws = vw.coerceAtLeast(1f)
    val vhs = vh.coerceAtLeast(1f)
    val arr = FloatArray(pts.size * 2)
    for (idx in pts.indices) {
      val px = pts[idx].x
      val py = pts[idx].y
      arr[idx * 2] = (px / vws) * 2f - 1f
      arr[idx * 2 + 1] = 1f - (py / vhs) * 2f
    }
    return ByteBuffer.allocateDirect(arr.size * 4).order(java.nio.ByteOrder.nativeOrder()).asFloatBuffer().apply { put(arr); position(0) }
  }

  companion object {
    private const val VERT = "attribute vec2 aPos; void main() { gl_Position = vec4(aPos, 0.0, 1.0); }"
    private const val FRAG = """
      precision mediump float;
      uniform vec4 uColor;
      uniform float uClipCompare;
      uniform float uSplitMinX;
      void main() {
        if (uClipCompare > 0.5 && gl_FragCoord.x < uSplitMinX) discard;
        gl_FragColor = uColor;
      }
    """
  }
}
