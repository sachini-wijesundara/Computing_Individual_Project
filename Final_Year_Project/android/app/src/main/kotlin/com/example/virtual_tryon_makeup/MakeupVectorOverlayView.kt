package com.example.virtual_tryon_makeup

import android.content.Context
import android.graphics.BlendMode
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.os.Build
import android.util.AttributeSet
import android.view.View
import androidx.core.graphics.ColorUtils
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

/**
 * Canvas paths for live try-on categories that iOS draws with [CAShapeLayer] vectors
 * (blush, highlight, eyes, brows, mascara, liner). The GL lip stencil is incorrect for these.
 */
class MakeupVectorOverlayView @JvmOverloads constructor(
  context: Context,
  attrs: AttributeSet? = null,
) : View(context, attrs) {

  private val path = Path()
  private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
  private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.STROKE
    strokeJoin = Paint.Join.ROUND
    strokeCap = Paint.Cap.ROUND
  }

  private var pts: Array<PointF> = emptyArray()
  /** Raw landmark polys for foundation (same loops as iOS [NativeLipRendererPlugin.drawLips]). */
  private var foundationPolys: FoundationPolys? = null
  private var category = ""
  private var shade = Color.RED
  private var intensity = 0.5f
  private var compare = false
  private var split = 0.5f
  private var hasDraw = false

  private data class FoundationPolys(
    val face: List<PointF>,
    val outerLip: List<PointF>,
    val innerLip: List<PointF>,
    val leftEye: List<PointF>,
    val rightEye: List<PointF>,
  )

  private fun isFoundationCategory(): Boolean {
    val c = category.lowercase()
    return c == "cmd_face" || c == "cmd_foundation" || c == "cmd_concealer" ||
      c.contains("foundation")
  }

  private fun isBlushCategory(): Boolean {
    val c = category.trim().lowercase()
    return c == "cmd_blush"
  }

  fun clear() {
    path.reset()
    foundationPolys = null
    if (layerType == View.LAYER_TYPE_SOFTWARE) {
      setLayerType(View.LAYER_TYPE_NONE, null)
    }
    hasDraw = false
    invalidate()
  }

  /** When only split/compare changes (e.g. calibration drag), rebuild without new landmarks. */
  fun applyCompareCalibration(isCompare: Boolean, splitPos: Float) {
    compare = isCompare
    split = splitPos.coerceIn(0.05f, 0.95f)
    if (pts.isNotEmpty() || foundationPolys != null) {
      rebuildPath()
      hasDraw = hasRenderableGeometry()
      invalidate()
    }
  }

  /**
   * Foundation / full-face tint: same **geometry** as iOS (face oval, outer lip, eyes) and the same
   * **raster path as Android photo try-on** — fill face then [PorterDuff.Mode.DST_OUT] holes
   * (see [NativeLipRendererPlatformView.drawFoundationPhotoLayer]).
   */
  fun updateFoundationPolys(
    face: List<PointF>,
    outerLip: List<PointF>,
    innerLip: List<PointF>,
    leftEye: List<PointF>,
    rightEye: List<PointF>,
    cat: String,
    shadeArgb: Int,
    inten: Float,
    isCompare: Boolean,
    splitPos: Float,
  ) {
    pts = emptyArray()
    foundationPolys = FoundationPolys(face, outerLip, innerLip, leftEye, rightEye)
    category = cat.trim().lowercase()
    shade = shadeArgb
    intensity = inten.coerceIn(0.05f, 1f)
    compare = isCompare
    split = splitPos.coerceIn(0.05f, 0.95f)
    rebuildPath()
    hasDraw = hasRenderableGeometry()
    // DST_OUT + fill is more reliable in software; matches common clipPath workaround.
    setLayerType(View.LAYER_TYPE_SOFTWARE, null)
    invalidate()
  }

  fun update(
    landmarkPts: Array<PointF>,
    cat: String,
    shadeArgb: Int,
    inten: Float,
    isCompare: Boolean,
    splitPos: Float,
  ) {
    pts = landmarkPts
    category = cat.trim().lowercase()
    shade = shadeArgb
    intensity = inten.coerceIn(0.05f, 1f)
    compare = isCompare
    split = splitPos.coerceIn(0.05f, 0.95f)
    foundationPolys = null
    if (layerType == View.LAYER_TYPE_SOFTWARE) {
      setLayerType(View.LAYER_TYPE_NONE, null)
    }
    rebuildPath()
    hasDraw = hasRenderableGeometry()
    invalidate()
  }

  private fun p(i: Int): PointF =
    if (i in pts.indices) pts[i] else PointF(0f, 0f)

  private fun pathHasGeometry(): Boolean {
    val r = RectF()
    path.computeBounds(r, true)
    return r.width() >= 1f || r.height() >= 1f
  }

  private fun hasRenderableGeometry(): Boolean {
    if (foundationPolys != null && isFoundationCategory()) {
      return foundationPolys!!.face.size >= 3
    }
    return pathHasGeometry()
  }

  private fun addPolygon(indices: IntArray, close: Boolean = true) {
    if (indices.isEmpty()) return
    path.moveTo(p(indices[0]).x, p(indices[0]).y)
    for (k in 1 until indices.size) {
      path.lineTo(p(indices[k]).x, p(indices[k]).y)
    }
    if (close) path.close()
  }

  private fun smoothCheek(indices: IntArray) {
    if (indices.size < 4) {
      addPolygon(indices, close = true)
      return
    }
    val n = indices.size
    val dupClose = indices[0] == indices[n - 1]
    val ptsLocal = Array(n) { i -> PointF(p(indices[i]).x, p(indices[i]).y) }
    repeat(7) {
      if (dupClose) ptsLocal[n - 1].set(ptsLocal[0])
      val snap = Array(n) { j -> PointF(ptsLocal[j].x, ptsLocal[j].y) }
      for (i in 1 until n - 1) {
        ptsLocal[i].x = snap[i].x * 0.42f + (snap[i - 1].x + snap[i + 1].x) * 0.29f
        ptsLocal[i].y = snap[i].y * 0.42f + (snap[i - 1].y + snap[i + 1].y) * 0.29f
      }
      if (dupClose) ptsLocal[n - 1].set(ptsLocal[0])
    }
    path.moveTo(ptsLocal[0].x, ptsLocal[0].y)
    for (i in 1 until n) path.lineTo(ptsLocal[i].x, ptsLocal[i].y)
    path.close()
  }

  private fun addRibbonAlongPolyline(indices: IntArray, halfWidth: Float) {
    if (indices.size < 2 || halfWidth <= 0.5f) return
    val lid = indices.map { p(it) }
    val n = lid.size
    val left = Array(n) { PointF() }
    val right = Array(n) { PointF() }
    for (i in 0 until n) {
      val prev = lid[max(0, i - 1)]
      val next = lid[min(n - 1, i + 1)]
      var dx = next.x - prev.x
      var dy = next.y - prev.y
      val len = max(0.001f, hypot(dx, dy))
      dx /= len
      dy /= len
      var nx = -dy
      var ny = dx
      if (ny > 0) {
        nx = -nx
        ny = -ny
      }
      left[i].set(lid[i].x + nx * halfWidth, lid[i].y + ny * halfWidth)
      right[i].set(lid[i].x - nx * halfWidth, lid[i].y - ny * halfWidth)
    }
    path.moveTo(left[0].x, left[0].y)
    for (i in 1 until n) path.lineTo(left[i].x, left[i].y)
    for (i in n - 1 downTo 0) path.lineTo(right[i].x, right[i].y)
    path.close()
  }

  private fun addShadowBand(lidIndices: IntArray, verticalBias: Float) {
    if (lidIndices.size < 3) return
    val lid = lidIndices.map { p(it) }
    val minX = lid.minOf { it.x }
    val maxX = lid.maxOf { it.x }
    val eyeWidth = max(1f, maxX - minX)
    val bandHeight = max(12f, min(26f, eyeWidth * 0.25f))
    val upper = ArrayList<PointF>(lid.size)
    for (i in lid.indices) {
      val cur = lid[i]
      val prev = lid[max(0, i - 1)]
      val next = lid[min(lid.size - 1, i + 1)]
      var dx = next.x - prev.x
      var dy = next.y - prev.y
      val len = max(0.001f, sqrt(dx * dx + dy * dy))
      dx /= len
      dy /= len
      var nx = -dy
      var ny = dx
      if (ny > 0) {
        nx = -nx
        ny = -ny
      }
      val t = i.toFloat() / max(1, lid.size - 1)
      val centerBoost = 0.70f + (0.35f * (1f - abs(t * 2f - 1f)))
      val off = bandHeight * centerBoost
      upper.add(PointF(cur.x + nx * off, cur.y + ny * off + verticalBias))
    }
    path.moveTo(upper[0].x, upper[0].y)
    for (i in 1 until upper.size) path.lineTo(upper[i].x, upper[i].y)
    for (i in lid.indices.reversed()) path.lineTo(lid[i].x, lid[i].y)
    path.close()
  }

  private fun addMascaraCoat(lashIndices: IntArray, isLeftEye: Boolean) {
    if (lashIndices.size < 3) return
    addPolygon(lashIndices, close = false)
    for (i in 1 until lashIndices.size - 1) {
      val base = p(lashIndices[i])
      val prev = p(lashIndices[i - 1])
      val next = p(lashIndices[i + 1])
      var dx = next.x - prev.x
      var dy = next.y - prev.y
      val len = max(0.001f, hypot(dx, dy))
      dx /= len
      dy /= len
      var nx = -dy
      var ny = dx
      if (ny > 0) {
        nx = -nx
        ny = -ny
      }
      val t = i.toFloat() / max(1, lashIndices.size - 2)
      val centerFactor = 1f - abs(t * 2f - 1f)
      val lashLength = 3.6f + (2.8f * centerFactor)
      val fan = (t - 0.5f) * (if (isLeftEye) -2f else 2f)
      val cx = base.x + nx * lashLength * 0.52f + fan
      val cy = base.y + ny * lashLength * 0.52f
      val tx = base.x + nx * lashLength + fan * 1.05f
      val ty = base.y + ny * lashLength
      path.moveTo(base.x, base.y)
      path.quadTo(cx, cy, tx, ty)
    }
  }

  private fun addBrowClosed(upper: IntArray, lower: IntArray) {
    val seq = IntArray(upper.size + lower.size)
    upper.copyInto(seq, 0)
    for (i in lower.indices) {
      seq[upper.size + i] = lower[lower.size - 1 - i]
    }
    addPolygon(seq, close = true)
  }

  private fun pathFromLoop(loop: List<PointF>): Path? {
    if (loop.size < 3) return null
    val p = Path()
    p.moveTo(loop[0].x, loop[0].y)
    for (i in 1 until loop.size) {
      p.lineTo(loop[i].x, loop[i].y)
    }
    p.close()
    return p
  }

  /**
   * Same pipeline as [NativeLipRendererPlatformView.drawFoundationPhotoLayer]: fill face,
   * then [PorterDuff.Mode.DST_OUT] for eyes + outer lip. Avoids Canvas evenOdd + multiply bugs
   * that showed as a small centre blob; iOS uses one shape layer evenOdd, which CoreAnimation
   * rasterizes differently — this path matches the working Android **photo** implementation.
   */
  private fun drawFoundationLikePhoto(canvas: Canvas) {
    val fp = foundationPolys ?: return
    val face = pathFromLoop(fp.face) ?: return
    val i = intensity.coerceIn(0f, 1f)
    val aFloat = max(0.20f, min(0.65f, i * 0.7f))
    val alpha = (255 * aFloat).toInt().coerceIn(51, 166)
    fillPaint.xfermode = null
    fillPaint.maskFilter = null
    fillPaint.color = ColorUtils.setAlphaComponent(shade, alpha)
    canvas.drawPath(face, fillPaint)
    fillPaint.xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_OUT)
    pathFromLoop(fp.leftEye)?.let { canvas.drawPath(it, fillPaint) }
    pathFromLoop(fp.rightEye)?.let { canvas.drawPath(it, fillPaint) }
    pathFromLoop(fp.outerLip)?.let { canvas.drawPath(it, fillPaint) }
    fillPaint.xfermode = null
  }

  private fun rebuildPath() {
    path.reset()
    val fp = foundationPolys
    if (fp != null && isFoundationCategory()) {
      // Foundation is drawn in [drawFoundationLikePhoto] from polys (photo-style DST_OUT), not [path].
      return
    }
    if (pts.isEmpty()) return
    when {
      isBlushCategory() -> {
        val left = intArrayOf(116, 117, 118, 100, 101, 119, 120, 121, 147, 213, 192, 214, 207, 205, 116)
        val right = intArrayOf(345, 346, 347, 329, 330, 348, 349, 350, 376, 433, 416, 434, 427, 425, 345)
        path.fillType = Path.FillType.WINDING
        smoothCheek(left)
        smoothCheek(right)
      }
      category == "cmd_highlight" -> {
        val leftH = intArrayOf(116, 117, 118, 100, 101, 119, 120, 121, 147, 116)
        val rightH = intArrayOf(345, 346, 347, 329, 330, 348, 349, 350, 376, 345)
        val noseBridge = intArrayOf(168, 6, 197, 195, 5, 4, 1)
        val cupid = intArrayOf(0, 267, 269, 270, 409, 291, 0)
        path.fillType = Path.FillType.WINDING
        smoothCheek(leftH)
        smoothCheek(rightH)
        val eyeMidY = (p(33).y + p(263).y) * 0.5f
        val chinY = p(152).y
        val faceLen = max(abs(chinY - eyeMidY), 40f)
        val noseHalfW = max(3.2f, min(8.5f, faceLen * 0.052f))
        addRibbonAlongPolyline(noseBridge, noseHalfW)
        smoothCheek(cupid)
      }
      category == "cmd_eyeshadow" || category == "cmd_eye" -> {
        val leftUpper = intArrayOf(33, 246, 161, 160, 159, 158, 157, 173, 133)
        val rightUpper = intArrayOf(263, 466, 388, 387, 386, 385, 384, 398, 362)
        path.fillType = Path.FillType.WINDING
        addShadowBand(leftUpper, -2f)
        addShadowBand(rightUpper, -2f)
      }
      category == "cmd_mascara" -> {
        val leftUpper = intArrayOf(33, 246, 161, 160, 159, 158, 157, 173, 133)
        val rightUpper = intArrayOf(362, 398, 384, 385, 386, 387, 388, 466, 263)
        path.fillType = Path.FillType.WINDING
        addMascaraCoat(leftUpper, isLeftEye = true)
        addMascaraCoat(rightUpper, isLeftEye = false)
      }
      category == "cmd_eyebrow" -> {
        val leftU = intArrayOf(70, 63, 105, 66, 107, 55)
        val leftL = intArrayOf(46, 53, 52, 65, 55)
        val rightU = intArrayOf(300, 293, 334, 296, 336, 285)
        val rightL = intArrayOf(276, 283, 282, 295, 285)
        path.fillType = Path.FillType.WINDING
        addBrowClosed(leftU, leftL)
        addBrowClosed(rightU, rightL)
      }
      category == "cmd_eyeliner" -> {
        val leftTop = intArrayOf(33, 246, 161, 160, 159, 158, 157, 173, 133)
        val leftBot = intArrayOf(33, 7, 163, 144, 145, 153, 154, 155, 133)
        val rightTop = intArrayOf(362, 398, 384, 385, 386, 387, 388, 466, 263)
        val rightBot = intArrayOf(362, 382, 381, 380, 374, 373, 390, 249, 263)
        addPolygon(leftTop, close = false)
        addPolygon(leftBot, close = false)
        addPolygon(rightTop, close = false)
        addPolygon(rightBot, close = false)
      }
      category == "cmd_lipliner" -> {
        val outer = intArrayOf(61, 185, 40, 39, 37, 0, 267, 269, 270, 409, 291, 375, 321, 405, 314, 17, 84, 181, 91, 146)
        addPolygon(outer, close = true)
      }
      else -> {}
    }
  }

  override fun onDraw(canvas: Canvas) {
    super.onDraw(canvas)
    if (!hasDraw) return

    val save = canvas.save()
    if (compare) {
      val w = width.toFloat().coerceAtLeast(1f)
      val sp = split.coerceIn(0.05f, 0.95f)
      canvas.clipRect(sp * w, 0f, w, height.toFloat())
    }

    fillPaint.style = Paint.Style.FILL
    strokePaint.style = Paint.Style.STROKE

    if (isFoundationCategory() && foundationPolys != null) {
      drawFoundationLikePhoto(canvas)
      canvas.restoreToCount(save)
      return
    }

    val r = RectF()
    path.computeBounds(r, true)
    if (r.width() < 0.5f && r.height() < 0.5f) {
      canvas.restoreToCount(save)
      return
    }

    when {
      isBlushCategory() -> {
        val t = intensity.toDouble().pow(0.52).toFloat()
        fillPaint.xfermode = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
          fillPaint.blendMode = BlendMode.SRC_OVER
        }
        // Live camera: this view draws onto a transparent layer; the compositor blends it over the
        // preview later. BlendMode.COLOR / multiply-in-layer used *destination luminance* from an
        // empty buffer → bright circular "pills". Use SRC_OVER + soft blur + capped alpha instead.
        val a = (255 * max(0.08f, 0.26f * t)).toInt().coerceIn(24, 155)
        fillPaint.color = ColorUtils.setAlphaComponent(shade, a)
        fillPaint.maskFilter = BlurMaskFilter(38f, BlurMaskFilter.Blur.NORMAL)
        canvas.drawPath(path, fillPaint)
        fillPaint.maskFilter = null
      }
      category == "cmd_highlight" -> {
        val hiT = intensity.toDouble().pow(0.48).toFloat()
        val a = (255 * max(0.05f, min(0.34f, 0.13f * hiT))).toInt().coerceIn(12, 200)
        fillPaint.color = ColorUtils.setAlphaComponent(shade, a)
        fillPaint.maskFilter = BlurMaskFilter(38f, BlurMaskFilter.Blur.NORMAL)
        fillPaint.xfermode = PorterDuffXfermode(PorterDuff.Mode.OVERLAY)
        canvas.drawPath(path, fillPaint)
        fillPaint.maskFilter = null
        fillPaint.xfermode = null
      }
      category == "cmd_eyeshadow" || category == "cmd_eye" -> {
        val a = (255 * max(0.14f, min(0.34f, intensity * 0.24f))).toInt().coerceIn(35, 220)
        fillPaint.color = ColorUtils.setAlphaComponent(shade, a)
        fillPaint.maskFilter = BlurMaskFilter(8f, BlurMaskFilter.Blur.NORMAL)
        canvas.drawPath(path, fillPaint)
        fillPaint.maskFilter = null
      }
      category == "cmd_mascara" -> {
        val rr = (Color.red(shade) * 0.22f).toInt().coerceIn(0, 255)
        val gg = (Color.green(shade) * 0.22f).toInt().coerceIn(0, 255)
        val bb = (Color.blue(shade) * 0.22f).toInt().coerceIn(0, 255)
        val a = (255 * max(0.45f, intensity * 0.92f)).toInt().coerceIn(100, 255)
        strokePaint.color = Color.argb(a, rr, gg, bb)
        strokePaint.strokeWidth = max(0.7f, min(1.1f, 0.8f + intensity * 0.2f))
        strokePaint.maskFilter = BlurMaskFilter(0.8f, BlurMaskFilter.Blur.NORMAL)
        canvas.drawPath(path, strokePaint)
        strokePaint.maskFilter = null
      }
      category == "cmd_eyebrow" -> {
        val a = (255 * max(0.16f, min(0.38f, intensity * 0.30f))).toInt().coerceIn(40, 220)
        fillPaint.color = ColorUtils.setAlphaComponent(shade, a)
        fillPaint.maskFilter = BlurMaskFilter(1f, BlurMaskFilter.Blur.NORMAL)
        canvas.drawPath(path, fillPaint)
        fillPaint.maskFilter = null
      }
      category == "cmd_eyeliner" -> {
        strokePaint.color = ColorUtils.setAlphaComponent(shade, (255 * intensity).toInt().coerceIn(60, 255))
        strokePaint.strokeWidth = 2.5f
        canvas.drawPath(path, strokePaint)
      }
      category == "cmd_lipliner" -> {
        strokePaint.color = ColorUtils.setAlphaComponent(shade, (255 * intensity).toInt().coerceIn(60, 255))
        strokePaint.strokeWidth = 3.5f
        canvas.drawPath(path, strokePaint)
      }
      else -> {}
    }
    canvas.restoreToCount(save)
  }
}
