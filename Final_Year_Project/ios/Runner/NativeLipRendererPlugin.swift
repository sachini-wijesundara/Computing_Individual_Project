import Flutter
import UIKit
import AVFoundation
import MediaPipeTasksVision
import TensorFlowLite
import VideoToolbox

private let viewType = "native_lip_renderer/view"
private let channelPrefix = "native_lip_renderer"
private let handStaticChannel = "la_vogue_vista/hand_landmarker"

// MARK: - HSL Helpers

fileprivate func rgbToHSL(_ r: Float, _ g: Float, _ b: Float) -> (h: Float, s: Float, l: Float) {
    let maxC  = max(r, g, b)
    let minC  = min(r, g, b)
    let delta = maxC - minC
    let l     = (maxC + minC) / 2.0
    guard delta > 0.001 else { return (0, 0, l) }
    let s = delta / (1.0 - abs(2.0 * l - 1.0))
    var h: Float
    if maxC == r {
      h = ((g - b) / delta).truncatingRemainder(dividingBy: 6.0)
      if h < 0 { h += 6.0 }
    } else if maxC == g {
      h = (b - r) / delta + 2.0
    } else {
      h = (r - g) / delta + 4.0
    }
    return (h / 6.0, s, l)
}

fileprivate func hslToRGB(_ h: Float, _ s: Float, _ l: Float) -> (r: Float, g: Float, b: Float) {
    guard s > 0.001 else { return (l, l, l) }
    let c   = (1.0 - abs(2.0 * l - 1.0)) * s
    let x   = c * (1.0 - abs((h * 6.0).truncatingRemainder(dividingBy: 2.0) - 1.0))
    let m   = l - c / 2.0
    let seg = Int(h * 6.0) % 6
    let (r1, g1, b1): (Float, Float, Float)
    switch seg {
    case 0: (r1, g1, b1) = (c, x, 0)
    case 1: (r1, g1, b1) = (x, c, 0)
    case 2: (r1, g1, b1) = (0, c, x)
    case 3: (r1, g1, b1) = (0, x, c)
    case 4: (r1, g1, b1) = (x, 0, c)
    default:(r1, g1, b1) = (c, 0, x)
    }
    return (max(0, min(1, r1+m)), max(0, min(1, g1+m)), max(0, min(1, b1+m)))
}

/// Bilinear sample of BGRA8888 (premultiplied or straight); returns 0..1 RGB.
fileprivate func sampleBGRABilinear(
  _ cam: UnsafePointer<UInt8>,
  bytesPerRow: Int,
  bufW: Int,
  bufH: Int,
  u: Float,
  v: Float
) -> (r: Float, g: Float, b: Float) {
  guard bufW > 0, bufH > 0 else { return (0, 0, 0) }
  let fx = u * Float(bufW - 1)
  let fy = v * Float(bufH - 1)
  let x0 = Int(floor(fx)), y0 = Int(floor(fy))
  let tx = fx - Float(x0)
  let ty = fy - Float(y0)
  let x1 = min(x0 + 1, bufW - 1)
  let y1 = min(y0 + 1, bufH - 1)
  let x0c = max(0, min(bufW - 1, x0))
  let y0c = max(0, min(bufH - 1, y0))
  func pix(_ x: Int, _ y: Int) -> (Float, Float, Float) {
    let o = y * bytesPerRow + x * 4
    return (Float(cam[o + 2]), Float(cam[o + 1]), Float(cam[o + 0]))
  }
  let c00 = pix(x0c, y0c)
  let c10 = pix(x1, y0c)
  let c01 = pix(x0c, y1)
  let c11 = pix(x1, y1)
  let w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty), w01 = (1 - tx) * ty, w11 = tx * ty
  let r = (c00.0 * w00 + c10.0 * w10 + c01.0 * w01 + c11.0 * w11) / 255.0
  let g = (c00.1 * w00 + c10.1 * w10 + c01.1 * w01 + c11.1 * w11) / 255.0
  let b = (c00.2 * w00 + c10.2 * w10 + c01.2 * w01 + c11.2 * w11) / 255.0
  return (max(0, min(1, r)), max(0, min(1, g)), max(0, min(1, b)))
}

/// Shared fingertip extraction for photo `detectTips` and live nail overlay.
fileprivate func iosHandTipsFromResult(_ result: HandLandmarkerResult?) -> [[String: Double]] {
  guard let result = result else { return [] }
  let lmList = result.landmarks
  if lmList.isEmpty { return [] }
  var best = lmList[0]
  var bestArea: CGFloat = 0
  for hand in lmList {
    guard hand.count >= 21 else { continue }
    var minX: CGFloat = 1
    var maxX: CGFloat = 0
    var minY: CGFloat = 1
    var maxY: CGFloat = 0
    for p in hand {
      minX = min(minX, CGFloat(p.x))
      maxX = max(maxX, CGFloat(p.x))
      minY = min(minY, CGFloat(p.y))
      maxY = max(maxY, CGFloat(p.y))
    }
    let area = (maxX - minX) * (maxY - minY)
    if area > bestArea {
      bestArea = area
      best = hand
    }
  }
  guard best.count >= 21 else { return [] }
  let tipIdx = [4, 8, 12, 16, 20]
  let pipIdx = [3, 6, 10, 14, 18]
  var out: [[String: Double]] = []
  for i in 0..<tipIdx.count {
    let t = best[tipIdx[i]]
    let p = best[pipIdx[i]]
    let dx = Double(t.x - p.x)
    let dy = Double(t.y - p.y)
    var dist = sqrt(dx * dx + dy * dy)
    if dist < 1e-4 { dist = 1e-4 }
    let ang = atan2(dy, dx)
    let nudge = 0.18
    let nx = min(0.98, max(0.02, Double(t.x) + dx * nudge))
    let ny = min(0.98, max(0.02, Double(t.y) + dy * nudge))
    out.append(["nx": nx, "ny": ny, "r": dist, "angle": ang])
  }
  return out
}

public class NativeLipRendererPlugin: NSObject, FlutterPlugin {
  private static var imageHandLandmarker: HandLandmarker?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let factory = NativeLipRendererViewFactory(messenger: registrar.messenger())
    registrar.register(factory, withId: viewType)

    let messenger = registrar.messenger()
    FlutterMethodChannel(name: handStaticChannel, binaryMessenger: messenger).setMethodCallHandler { call, result in
      guard call.method == "detectTips" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "arg", message: "path required", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          if NativeLipRendererPlugin.imageHandLandmarker == nil {
            guard let modelPath = Bundle.main.path(forResource: "hand_landmarker", ofType: "task") else {
              DispatchQueue.main.async {
                result(FlutterError(code: "model", message: "hand_landmarker.task missing", details: nil))
              }
              return
            }
            let options = HandLandmarkerOptions()
            options.baseOptions.modelAssetPath = modelPath
            options.runningMode = .image
            options.numHands = 2
            options.minHandDetectionConfidence = 0.35
            options.minHandPresenceConfidence = 0.45
            options.minTrackingConfidence = 0.45
            NativeLipRendererPlugin.imageHandLandmarker = try HandLandmarker(options: options)
          }
          guard let uiImage = UIImage(contentsOfFile: path),
                let mpImage = try? MPImage(uiImage: uiImage),
                let hl = NativeLipRendererPlugin.imageHandLandmarker else {
            DispatchQueue.main.async { result([]) }
            return
          }
          let hResult = try hl.detect(image: mpImage)
          let tips = iosHandTipsFromResult(hResult)
          DispatchQueue.main.async { result(tips) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "hand", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }
}

private class NativeLipRendererViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    return NativeLipRendererView(
      frame: frame,
      viewId: viewId,
      messenger: messenger
    )
  }

  public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

private class PreviewContainerView: UIView {
    var onLayout: ((CGRect) -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(bounds)
    }
}

/// Helper class to run the custom TFLite nail segmentation model.
private class NailPolishRenderer {
    private let MODEL_NAME = "nail_segmentation"
    private let SIZE: Int = 224
    var interpreter: Interpreter?
    
    // EXTREMELY CRITICAL: Sharing CIContext prevents 60fps out-of-memory CoreDevice terminations.
    private let sharedCIContext = CIContext(options: [.cacheIntermediates: false])

    init() {
        setupInterpreter()
    }

    private func setupInterpreter() {
        guard let modelPath = Bundle.main.path(forResource: MODEL_NAME, ofType: "tflite") else {
            print("❌ iOS: \(MODEL_NAME).tflite not found in bundle")
            return
        }
        do {
            var options = Interpreter.Options()
            options.threadCount = 2
            interpreter = try Interpreter(modelPath: modelPath, options: options)
            try interpreter?.allocateTensors()
            print("✅ iOS: Nail segmenter model loaded")
        } catch {
            print("❌ iOS: Failed to load nail segmenter: \(error)")
        }
    }

    private var hasRunDiagnostic = false

    /// Keeps live output stable when confidence oscillates between frames.
    private var prevFingerProbMaps: [[Float]?] = Array(repeating: nil, count: 5)
    /// Per-finger observed nail aspect (height/width) from segmentation.
    private var fingerObservedAspect: [CGFloat?] = Array(repeating: nil, count: 5)
    /// Centroid of thresholded mask in ROI, normalized to ≈[-1,1] from image center (hybrid position nudge).
    private var fingerPlateOffset: [CGPoint?] = Array(repeating: nil, count: 5)
    /// Mask width in ROI / 224 — scales lateral hybrid correction when the plate is wide in the crop.
    private var fingerPlateSpanNorm: [CGFloat?] = Array(repeating: nil, count: 5)
    /// 0..1 confidence for how many fingers produced a valid segmentation mask this frame.
    private(set) var lastMaskReliability: CGFloat = 0

    func observedAspect(for fingerIndex: Int) -> CGFloat? {
        guard fingerIndex >= 0 && fingerIndex < fingerObservedAspect.count else { return nil }
        return fingerObservedAspect[fingerIndex]
    }

    func plateOffset(for fingerIndex: Int) -> CGPoint? {
        guard fingerIndex >= 0 && fingerIndex < fingerPlateOffset.count else { return nil }
        return fingerPlateOffset[fingerIndex]
    }

    func plateSpanNorm(for fingerIndex: Int) -> CGFloat? {
        guard fingerIndex >= 0 && fingerIndex < fingerPlateSpanNorm.count else { return nil }
        return fingerPlateSpanNorm[fingerIndex]
    }

    /// Normalized buffer coords → view; matches `.resizeAspectFill` using **actual** buffer dimensions.
    static func aspectFillNormToView(
        nx: CGFloat, ny: CGFloat,
        bufferWidth bufW: CGFloat, bufferHeight bufH: CGFloat,
        viewWidth viewW: CGFloat, viewHeight viewH: CGFloat
    ) -> CGPoint {
        guard bufW > 1, bufH > 1, viewW > 1, viewH > 1 else { return .zero }
        let scale = max(viewW / bufW, viewH / bufH)
        let dispW = bufW * scale
        let dispH = bufH * scale
        let xOff = (viewW - dispW) / 2
        let yOff = (viewH - dispH) / 2
        return CGPoint(x: nx * dispW + xOff, y: ny * dispH + yOff)
    }
    
    /// Runs segmentation on detected finger ROIs and returns a full-frame mask.
    func renderNailMask(
        pixelBuffer: CVPixelBuffer,
        handLandmarks: HandLandmarkerResult?,
        containerBounds: CGRect,
        intensity: CGFloat,
        polishColor: UIColor,
        artStyle: Int,
        nailShape: Int
    ) -> UIImage? {
        guard let interpreter = interpreter,
              let allHands = handLandmarks?.landmarks,
              !allHands.isEmpty else { return nil }
        guard containerBounds.width > 2, containerBounds.height > 2 else { return nil }

        // Prefer the largest/closest hand to stabilize nails under multi-hand frames.
        var landmarks = allHands[0]
        var bestArea: CGFloat = 0
        for hand in allHands {
            guard hand.count >= 21 else { continue }
            var minX: CGFloat = 1
            var maxX: CGFloat = 0
            var minY: CGFloat = 1
            var maxY: CGFloat = 0
            for p in hand {
                minX = min(minX, CGFloat(p.x))
                maxX = max(maxX, CGFloat(p.x))
                minY = min(minY, CGFloat(p.y))
                maxY = max(maxY, CGFloat(p.y))
            }
            let area = (maxX - minX) * (maxY - minY)
            if area > bestArea {
                bestArea = area
                landmarks = hand
            }
        }
        guard landmarks.count >= 21 else { return nil }
              
        if !hasRunDiagnostic {
            hasRunDiagnostic = true
            print("🧪 AUTO-RUNNING TFLITE SANITY CHECK 🧪")
            do {
                var floats = [Float](repeating: 1.0, count: 224 * 224 * 3)
                let inputData = floats.withUnsafeBufferPointer { Data(buffer: $0) }
                try interpreter.copy(inputData, toInputAt: 0)
                try interpreter.invoke()
                let outputTensor = try interpreter.output(at: 0)
                let outFloats = outputTensor.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                let maxVal = outFloats.max() ?? -1.0
                let minVal = outFloats.min() ?? -1.0
                print("🧪 SANITY OUTPUT MIN/MAX: \(minVal) to \(maxVal)")
            } catch { print("❌ SANITY CRASH: \(error)") }
        }
        let bufW = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let bufH = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        // v20: Full-view bitmap for compositing masks (requires non-zero size; caller must use main-thread layout).
        UIGraphicsBeginImageContextWithOptions(containerBounds.size, false, UIScreen.main.scale)
        defer { UIGraphicsEndImageContext() }
        
        let viewW = containerBounds.width
        let viewH = containerBounds.height
        let uiScale = max(viewW / bufW, viewH / bufH)
        
        let tipIdx = [4, 8, 12, 16, 20]
        let dipIdx = [3, 7, 11, 15, 19]
        var segmentedFingers = 0

        for i in 0..<tipIdx.count {
            autoreleasepool {
                guard landmarks.count > tipIdx[i], landmarks.count > dipIdx[i] else { return }
                let t = landmarks[tipIdx[i]]
                let p = landmarks[dipIdx[i]]
                
                // Raw landmarks. Math restored to un-flipped coordinate system.
                let tx = CGFloat(t.x)
                let ty = CGFloat(t.y)
                let px = CGFloat(p.x)
                let py = CGFloat(p.y)
                
                let dxNorm = tx - px
                let dyNorm = ty - py
                let rNorm = hypot(dxNorm, dyNorm)
                // Shift slightly toward the free edge (consistent with Android).
                let nudge: CGFloat = 0.18
                
                let nx = tx + dxNorm * nudge
                let ny = ty + dyNorm * nudge
                
                // 1. Where does this crop live inside the raw Camera PixelBuffer?
                let pCenterX = nx * bufW
                let pCenterY = ny * bufH
                
                let minDim = min(bufW, bufH)
                // Bigger ROI makes the nail plate fully visible to the segmenter.
                let halfSide = rNorm * minDim * 1.55
                let clampedHalfSide = max(22.0, min(128.0, halfSide))
                let pW = clampedHalfSide * 2
                let pH = clampedHalfSide * 2
                
                let pX0 = pCenterX - clampedHalfSide
                let pY0 = pCenterY - clampedHalfSide
                let cropRect = CGRect(x: pX0, y: pY0, width: pW, height: pH)
                if cropRect.width < 10 || cropRect.height < 10 { return }
                
                let uiCenter = Self.aspectFillNormToView(
                    nx: nx, ny: ny,
                    bufferWidth: bufW, bufferHeight: bufH,
                    viewWidth: viewW, viewHeight: viewH
                )
                
                // 3. Extract the crop from the buffer
                guard let roiImage = cropPixelBuffer(pixelBuffer, to: cropRect) else { return }
                
                // 4. Prepare TFLite input image (Standard resize to 224x224, no rotation)
                UIGraphicsBeginImageContextWithOptions(CGSize(width: SIZE, height: SIZE), false, 1.0)
                roiImage.draw(in: CGRect(x: 0, y: 0, width: CGFloat(SIZE), height: CGFloat(SIZE)))
                let tfliteInputImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                
                // 5. Run AI Inference
                guard let inputData = tfliteInputImage?.toTFLiteData() else { return }
                
                do {
                    try interpreter.copy(inputData, toInputAt: 0)
                    try interpreter.invoke()
                    let outputTensor = try interpreter.output(at: 0)
                    let maskFloats = outputTensor.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                        if let mainCtx = UIGraphicsGetCurrentContext() {
                        // 2. High-Frequency AI Confidence Logging
                        let maxConf = maskFloats.max() ?? 0.0
                        if i == 0 { print("DEBUG: [v31] Nail AI Max Confidence: \(maxConf)") }
                        
                        // 3. Render custom U-Net mask linked to primary mapped center.
                        // Passing tfliteInputImage as reference for luminance-preserving color blending.
                        if let nailMask = createMaskImage(
                            floats: maskFloats,
                            color: polishColor,
                            alpha: intensity,
                            style: artStyle,
                            referenceImage: tfliteInputImage,
                            fingerIndex: i
                        ) {
                            segmentedFingers += 1
                            mainCtx.saveGState()
                            mainCtx.translateBy(x: uiCenter.x, y: uiCenter.y)
                            let drawW = pW * uiScale
                            let drawH = pH * uiScale
                            nailMask.draw(in: CGRect(x: -drawW/2, y: -drawH/2, width: drawW, height: drawH))
                            mainCtx.restoreGState()
                        }
                    }
                } catch {
                    print("❌ iOS: Inference Error: \(error)")
                }
            }
        }
        lastMaskReliability = CGFloat(segmentedFingers) / CGFloat(max(1, tipIdx.count))
        // Reject empty frames only; requiring 2+ fingers hid valid single-finger masks and starved hybrid fit.
        guard segmentedFingers >= 1 else { return nil }
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    private func cropPixelBuffer(_ buffer: CVPixelBuffer, to rect: CGRect) -> UIImage? {
        var cgImageOut: CGImage?
        VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &cgImageOut)
        guard let fullCG = cgImageOut else { return nil }
        
        let buffW = CGFloat(fullCG.width)
        let buffH = CGFloat(fullCG.height)
        let safeRect = rect.intersection(CGRect(x: 0, y: 0, width: buffW, height: buffH))
        if safeRect.isEmpty { return nil }
        
        guard let croppedCG = fullCG.cropping(to: safeRect) else { return nil }
        return UIImage(cgImage: croppedCG)
    }

    private func createMaskImage(floats: [Float], color: UIColor, alpha: CGFloat, style: Int, referenceImage: UIImage?, fingerIndex: Int) -> UIImage? {
        let count = SIZE * SIZE
        var pixels = [UInt32](repeating: 0, count: count)
        
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        let (tgtH, tgtS, tgtL) = rgbToHSL(Float(r), Float(g), Float(b))
        
        // Extract reference pixels for texture preservation
        var refPixels: [UInt8]?
        if let ref = referenceImage, let cgRef = ref.cgImage {
             let w = cgRef.width
             let h = cgRef.height
             let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
             if let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo) {
                 context.draw(cgRef, in: CGRect(x:0, y:0, width: w, height: h))
                 if let data = context.data {
                     refPixels = Array(UnsafeBufferPointer(start: data.bindMemory(to: UInt8.self, capacity: w * h * 4), count: w * h * 4))
                 }
             }
        }

        @inline(__always) func sigmoid(_ x: Float) -> Float {
            // Numerically-stable sigmoid.
            if x >= 0 {
                let z = exp(-x)
                return 1.0 / (1.0 + z)
            } else {
                let z = exp(x)
                return z / (1.0 + z)
            }
        }
        @inline(__always) func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
            let t = max(0.0, min(1.0, (x - edge0) / max(1e-6, (edge1 - edge0))))
            return t * t * (3.0 - 2.0 * t)
        }

        // Some models output logits, others output probabilities. Detect by range.
        let minRaw = floats.min() ?? 0
        let maxRaw = floats.max() ?? 0
        let looksLikeLogits = minRaw < -0.2 || maxRaw > 1.2
        var probs = [Float](repeating: 0, count: count)
        probs.withUnsafeMutableBufferPointer { dst in
            for i in 0..<count {
                let raw = floats[i]
                dst[i] = looksLikeLogits ? sigmoid(raw) : raw
            }
        }

        // 3x3 denoise smoothing: suppress isolated speckles before thresholding.
        var smooth = probs
        for y in 1..<(SIZE - 1) {
            for x in 1..<(SIZE - 1) {
                let i = y * SIZE + x
                let sum =
                    probs[i - SIZE - 1] + probs[i - SIZE] + probs[i - SIZE + 1] +
                    probs[i - 1]        + probs[i]        + probs[i + 1] +
                    probs[i + SIZE - 1] + probs[i + SIZE] + probs[i + SIZE + 1]
                smooth[i] = sum / 9.0
            }
        }

        // Temporal EMA for each finger's ROI keeps polish locked while moving.
        if fingerIndex >= 0 && fingerIndex < prevFingerProbMaps.count {
            if let prev = prevFingerProbMaps[fingerIndex], prev.count == count {
                let hist: Float = 0.62
                for i in 0..<count {
                    smooth[i] = prev[i] * hist + smooth[i] * (1.0 - hist)
                }
            }
            prevFingerProbMaps[fingerIndex] = smooth
        }

        let maxProb = smooth.max() ?? 0

        // Dynamic threshold tuned for iPhone live input:
        // Too high = only a few pixels survive (speckle). Keep the floor low.
        let confThreshold = max(0.34, min(0.64, maxProb * 0.66))

        // Keep only components that are anatomically plausible for a nail:
        // near centerline, mostly in upper 80% of ROI, and sufficiently large.
        var keep = [Bool](repeating: false, count: count)
        var visited = [UInt8](repeating: 0, count: count)
        let centerX = Float(SIZE) * 0.5
        // Slightly looser CC filter: small/pinky nails and angled crops were rejected → missing fingers.
        let maxCenterDX = Float(SIZE) * 0.50
        let maxCentroidY = Float(SIZE) * 0.88
        let minPixels = max(64, count / 720)
        var queue = [Int](repeating: 0, count: count)

        func isFg(_ idx: Int) -> Bool {
            return smooth[idx] >= confThreshold
        }

        for i in 0..<count {
            if visited[i] != 0 || !isFg(i) { continue }
            var qHead = 0
            var qTail = 0
            queue[qTail] = i
            qTail += 1
            visited[i] = 1

            var compIndices: [Int] = []
            compIndices.reserveCapacity(256)
            var sumX: Float = 0
            var sumY: Float = 0

            while qHead < qTail {
                let cur = queue[qHead]
                qHead += 1
                compIndices.append(cur)

                let cx = cur % SIZE
                let cy = cur / SIZE
                sumX += Float(cx)
                sumY += Float(cy)

                let y0 = max(0, cy - 1)
                let y1 = min(SIZE - 1, cy + 1)
                let x0 = max(0, cx - 1)
                let x1 = min(SIZE - 1, cx + 1)
                for ny in y0...y1 {
                    for nx in x0...x1 {
                        let ni = ny * SIZE + nx
                        if visited[ni] != 0 || !isFg(ni) { continue }
                        visited[ni] = 1
                        queue[qTail] = ni
                        qTail += 1
                    }
                }
            }

            if compIndices.count < minPixels { continue }
            let n = Float(compIndices.count)
            let cx = sumX / n
            let cy = sumY / n
            if abs(cx - centerX) > maxCenterDX || cy > maxCentroidY { continue }
            for idx in compIndices {
                keep[idx] = true
            }
        }

        // Measure component envelope to infer real nail proportions for this finger.
        var minX = SIZE
        var maxX = 0
        var minY = SIZE
        var maxY = 0
        var hasKeep = false
        for i in 0..<count where keep[i] {
            let y = i / SIZE
            let x = i % SIZE
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
            hasKeep = true
        }
        if fingerIndex >= 0 && fingerIndex < fingerObservedAspect.count {
            if hasKeep {
                let w = max(1, maxX - minX + 1)
                let h = max(1, maxY - minY + 1)
                let aspect = CGFloat(h) / CGFloat(w)
                let clamped = min(2.6, max(1.0, aspect))
                if let prev = fingerObservedAspect[fingerIndex] {
                    // Smooth observed shape so style doesn't jump with motion blur.
                    fingerObservedAspect[fingerIndex] = prev * 0.72 + clamped * 0.28
                } else {
                    fingerObservedAspect[fingerIndex] = clamped
                }
                var tcx = 0
                var tcy = 0
                var tcnt = 0
                for i in 0..<count where keep[i] {
                    tcx += i % SIZE
                    tcy += i / SIZE
                    tcnt += 1
                }
                if tcnt > 0 {
                    let mx = (CGFloat(tcx) / CGFloat(tcnt) - CGFloat(SIZE) * 0.5) / (CGFloat(SIZE) * 0.5)
                    let my = (CGFloat(tcy) / CGFloat(tcnt) - CGFloat(SIZE) * 0.5) / (CGFloat(SIZE) * 0.5)
                    let raw = CGPoint(x: mx.clamped(to: -1.2...1.2), y: my.clamped(to: -1.2...1.2))
                    if let pprev = fingerPlateOffset[fingerIndex] {
                        fingerPlateOffset[fingerIndex] = CGPoint(
                            x: pprev.x * 0.62 + raw.x * 0.38,
                            y: pprev.y * 0.62 + raw.y * 0.38
                        )
                    } else {
                        fingerPlateOffset[fingerIndex] = raw
                    }
                }
                let spanXN = CGFloat(max(1, maxX - minX + 1)) / CGFloat(SIZE)
                if fingerIndex < fingerPlateSpanNorm.count {
                    if let ps = fingerPlateSpanNorm[fingerIndex] {
                        fingerPlateSpanNorm[fingerIndex] = ps * 0.65 + spanXN * 0.35
                    } else {
                        fingerPlateSpanNorm[fingerIndex] = spanXN
                    }
                }
            } else {
                fingerObservedAspect[fingerIndex] = nil
                fingerPlateOffset[fingerIndex] = nil
                fingerPlateSpanNorm[fingerIndex] = nil
            }
        }

        var painted = 0

        for i in 0..<count {
            if !keep[i] { continue }
            let prob = smooth[i]

            // Feather edges rather than hard-cut pixels.
            let w = smoothstep(confThreshold, min(0.98, confThreshold + 0.22), prob)
            if w <= 0 { continue }

            // Use squared weight to suppress isolated single-pixel noise.
            let w2 = w * w
            var maskA = UInt32(CGFloat(w2) * alpha * 245.0)
            
            var finalR = UInt8(r * 255)
            var finalG = UInt8(g * 255)
            var finalB = UInt8(b * 255)

            // Texture Preservation: Apply HSL blending if reference pixels are available
            if let rp = refPixels, i*4 + 2 < rp.count {
                let srcB = Float(rp[i*4 + 0]) / 255.0
                let srcG = Float(rp[i*4 + 1]) / 255.0
                let srcR = Float(rp[i*4 + 2]) / 255.0
                
                let (_, srcS, srcL) = rgbToHSL(srcR, srcG, srcB)
                
                // Keep the structural highlights of the nail but apply the polish color
                // resultL = original nail luminance boosted to ensure polish color pops
                let resultL = max(srcL, tgtL * 0.72)
                let (outR, outG, outB) = hslToRGB(tgtH, tgtS, resultL)
                
                finalR = UInt8(outR * 255)
                finalG = UInt8(outG * 255)
                finalB = UInt8(outB * 255)
            }
            
            // Apply Art Styles
            if style == 1 { // French tip
                let row = i / SIZE
                let col = i % SIZE
                let colOffset = CGFloat(col - SIZE / 2)
                let smileCurve = (colOffset * colOffset) / CGFloat(SIZE * 2)
                
                if CGFloat(row) < (CGFloat(SIZE) * 0.28 + smileCurve) {
                    pixels[i] = (maskA << 24) | (248 << 16) | (250 << 8) | 255 // White tip
                    continue
                }
            } else if style == 2 { // Ombré
                let row = i / SIZE
                let grad = 1.0 - (CGFloat(row) / CGFloat(SIZE))
                maskA = UInt32(CGFloat(maskA) * grad)
            }
            
            pixels[i] = (maskA << 24) | (UInt32(finalR) << 16) | (UInt32(finalG) << 8) | UInt32(finalB)
            painted += 1
        }

        if painted < (count / 300) { return nil }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        guard let ctx = CGContext(data: &pixels, width: SIZE, height: SIZE, bitsPerComponent: 8, bytesPerRow: SIZE * 4, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else { return nil }
        guard let cg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cg)
    }


}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

extension UIImage {
    func resized(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        draw(in: CGRect(origin: .zero, size: size))
        let res = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return res
    }
    
    func toTFLiteData() -> Data? {
        guard let cgImage = self.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        
        // Use explicit Apple Native hardware layout (BGRA) to avoid Endian-scrambled color channels!
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo) else { return nil }
        
        // Flip to Top-Down memory layout
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        guard let raw = context.data else { return nil }
        
        let pixels = raw.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var floats = [Float](repeating: 0, count: width * height * 3)
        
        for i in 0..<(width * height) {
            // Memory is physically B, G, R, A because of byteOrder32Little + premultipliedFirst = ARGB integer storing.
            // Feed RGB (matches Android pipeline and most TF/TFLite model conventions).
            floats[i * 3 + 0] = Float(pixels[i * 4 + 2]) / 255.0 // R
            floats[i * 3 + 1] = Float(pixels[i * 4 + 1]) / 255.0 // G
            floats[i * 3 + 2] = Float(pixels[i * 4 + 0]) / 255.0 // B
        }
        
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

private class NativeLipRendererView: NSObject, FlutterPlatformView, FlutterStreamHandler, AVCaptureVideoDataOutputSampleBufferDelegate {
  private let container: PreviewContainerView
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?

  private var captureSession: AVCaptureSession?
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var faceLandmarker: FaceLandmarker?
  private var hairSegmenter: ImageSegmenter?
  /// Live hair **colour** uses `.image` mode (no VIDEO temporal smoothing → less motion lag). Wig keeps [hairSegmenter] (`.video`).
  private var hairColorImageSegmenter: ImageSegmenter?
  private var isProcessingHair = false
  /// Previous hair-mask RGBA (1/4-res, premultiplied); EMA reduces edge flicker on live preview.
  private var lastHairMaskRgba: [UInt8]?
  private let hairQueue = DispatchQueue(label: "hair_processing", qos: .userInteractive)
  /// Live hair colour: coalesce to **latest** `CMSampleBuffer` (retained) so MediaPipe sees the same
  /// framing as wig mode (`MPImage(sampleBuffer:)`) and we keep pixel data valid for `hairQueue`.
  private let hairCoalesceLock = NSLock()
  private var latestHairSampleBuffer: CMSampleBuffer?
  private var hairColorPipeRunning = false
  private var hairColorLastSegmentTsMs: Int = 0
  /// Latest main-thread hair UI token: stale `async` blocks bail out (avoids `DispatchWorkItem.cancel` races that can flicker).
  private let hairUiSerialLock = NSLock()
  private var hairUiApplySerial: Int = 0
  /// Serializes photo decode + face detect + PNG render so rapid `setLook` taps cannot overlap (jetsam).
  private let photoRenderQueue = DispatchQueue(label: "com.lavoguevista.native_lip_renderer.photo_pipeline")
  private let nailSegQueue = DispatchQueue(label: "nail_seg_processing", qos: .userInitiated)
  private var isProcessingNailSeg = false
  // Wig mode: run heavy segmenter only every N frames; landmark runs every frame
  private var wigFrameCounter  = 0
  private let wigSegmentEvery  = 15   // ~1 mask refresh per second at 15fps
  private var wigMaskActive    = false // true while hairMaskLayer has a shadow cast

  private let lipOverlayLayer = CAShapeLayer()
  /// When Flutter sends `setLook`, composite multiple categories (foundation + lips, etc.).
  private let makeupStackParent = CALayer()
  private var makeupSlotLayers: [CAShapeLayer] = []
  private struct MakeupLookEntry {
    var category: String
    var shade: UIColor
    var intensity: CGFloat
  }
  private var makeupLookStack: [MakeupLookEntry] = []
  private var usesMakeupLookStack = false
  private let hairSideLayer   = CAShapeLayer()   // side-screen hair panels (unused but kept)
  private let hairMaskLayer   = CALayer()         // pixel-accurate hair colour
  private let hairImageLayer  = CALayer()         // wig composite overlay
  private let nailOverlayLayer   = CAShapeLayer() // Main opaque nail colour
  private let nailCuticleLayer   = CAShapeLayer() // Dark shadow at cuticle (depth)
  private let nailHighlightLayer = CAShapeLayer() // Specular gloss near free edge
  private let nailDebugLayer     = CAShapeLayer() // Landmark dots + axes (debug)
  private let nailSegmentLayer   = CALayer()      // TFLite mask
  /// Loaded on first use only. Current nail modes use `forceSimpleNailMode` (landmarks only),
  /// so this avoids allocating the ~224² nail TFLite interpreter for every platform view.
  private lazy var nailRenderer = NailPolishRenderer()
  // Reliability-first mode for deadline: use stable landmark rendering each frame.
  // (Hybrid segmentation path can be re-enabled after submission tuning.)
  private let useNailSegmentationLive = false
  private var nailFrameCounter: Int = 0
  /// Segmentation throttle: lower = fresher hybrid fit (more CPU). Landmarks still every frame.
  private let nailSegmentEvery: Int = 6
  private var lastNailMaskImage: UIImage?
  private var lastNailMaskReliability: CGFloat = 0
  private var handLandmarker: HandLandmarker?
  private var currentNailArtStyle: Int = 0
  private var currentNailShape: Int = 0
  private var currentShade: UIColor = .red
  private var currentIntensity: CGFloat = 0.4
  private var currentSplitPosition: CGFloat = 0.5
  private var isCompareMode: Bool = false
  private var currentCategory: String = "Lip Sticks"
  private var currentHairStyleShape: String = "long"
  private var currentImageAsset: String? = nil
  private var showNailDebug: Bool = false

  // ── Photo try-on (offline render) ─────────────────────────────────────────
  private var photoUIImage: UIImage?
  private var photoFaceLandmarker: FaceLandmarker?

  // ── Live nail stabilization ────────────────────────────────────────────────
  // Smooth the raw DIP and TIP landmark positions directly — this mirrors the
  // lipstick approach where we work with actual landmark screen coordinates
  // rather than derived geometry.  Smoothing the source points (not a computed
  // center+angle) means the cuticle stays anchored to DIP and the free edge
  // stays near TIP with zero drift amplification.
  private struct NailFrame {
    var tip:   CGPoint = .zero   // TIP landmark in screen space
    var dip:   CGPoint = .zero   // DIP landmark in screen space
    var pip:   CGPoint = .zero   // PIP landmark in screen space
    var valid: Bool    = false
  }
  private struct NailGeomState {
    var center: CGPoint = .zero
    var angle: CGFloat = 0
    var width: CGFloat = 0
    var length: CGFloat = 0
    var valid: Bool = false
  }
  private var prevNailFrame: [NailFrame] = Array(repeating: NailFrame(), count: 5)
  private var prevNailGeom: [NailGeomState] = Array(repeating: NailGeomState(), count: 5)
  private var nailMissFrames: [Int] = Array(repeating: 0, count: 5)
  private var nailHideFrames: [Int] = Array(repeating: 0, count: 5)
  private var lastDrawnNailsCount: Int = 0
  private var nailLostFrames: Int = 0
  private var lastTrackedHandCenterNorm: CGPoint? = nil
  /// Latest camera buffer size (from `CMSampleBuffer`); avoids wrong overlays when hardware reports 1280×720 vs 720×1280.
  private var lastCaptureBufferWidth: CGFloat = 0
  private var lastCaptureBufferHeight: CGFloat = 0
  // Deadline-safe rendering mode: direct landmark nails only (most stable fit).
  private let forceSimpleNailMode = true
  /// Snapshot from `layoutSubviews` (main thread only). Never read `UIView.bounds` from the camera queue.
  private var lastLayoutBounds: CGRect = .zero
  /// Front camera preview is mirrored; segmentation uses the unmirrored buffer — flip hair layers to match.
  private var hairFlipToMatchMirroredPreview: Bool = false
  
  // Smoothing state for 3D Wig Tracking
  private var lastWigPosition: CGPoint?
  private var lastWigBounds:    CGRect?
  private var lastWigTransform: CATransform3D?
  private let smoothingFactor:  CGFloat = 0.35 // 0.0 = no move, 1.0 = instant move

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
    container = PreviewContainerView(frame: frame)
    container.backgroundColor = .black
    container.isOpaque = true
    container.clipsToBounds = true

    methodChannel = FlutterMethodChannel(
      name: "\(channelPrefix)/\(viewId)",
      binaryMessenger: messenger
    )
    eventChannel = FlutterEventChannel(
      name: "\(channelPrefix)/\(viewId)/events",
      binaryMessenger: messenger
    )

    super.init()

    container.onLayout = { [weak self] bounds in
        self?.lastLayoutBounds = bounds
        self?.previewLayer?.frame = bounds
        self?.lipOverlayLayer.frame = bounds
        self?.makeupStackParent.frame = bounds
        if self?.usesMakeupLookStack == true, !(self?.makeupLookStack.isEmpty ?? true) {
          self?.layoutMakeupSlotLayersForStack()
        } else {
          for sl in self?.makeupSlotLayers ?? [] {
            sl.frame = CGRect(origin: .zero, size: bounds.size)
          }
        }
        self?.hairSideLayer.frame = bounds
        self?.hairMaskLayer.frame = bounds
        self?.hairImageLayer.frame = bounds
        self?.applyHairOverlayFlipForPreview(bounds: bounds)
        self?.nailOverlayLayer.frame   = bounds
        self?.nailCuticleLayer.frame   = bounds
        self?.nailHighlightLayer.frame = bounds
        self?.nailSegmentLayer.frame   = bounds
    }

    setupLipLayer()
    methodChannel.setMethodCallHandler(handle)
    eventChannel.setStreamHandler(self)
    // Do not load Face / Hair / Hand models here — parallel init spikes memory (~3GB+ jetsam).
    // Video FaceLandmarker: `startCamera()`. Hair segmenter: first hair frame. Hand: nail mode in `startCamera()`.
    // Photo-only flows use `ensurePhotoFaceLandmarker()` and never allocate the video landmarker.
  }

  func view() -> UIView {
    return container
  }

  private func setupLipLayer() {
    lipOverlayLayer.fillRule = .evenOdd
    lipOverlayLayer.allowsEdgeAntialiasing = true
    lipOverlayLayer.opacity = 0.0
    container.layer.addSublayer(lipOverlayLayer)

    makeupStackParent.name = "makeupStackParent"
    makeupStackParent.masksToBounds = false
    for _ in 0..<10 {
      let sl = CAShapeLayer()
      sl.allowsEdgeAntialiasing = true
      sl.opacity = 0
      sl.fillRule = .evenOdd
      makeupStackParent.addSublayer(sl)
      makeupSlotLayers.append(sl)
    }
    container.layer.insertSublayer(makeupStackParent, below: lipOverlayLayer)

    hairSideLayer.fillRule = .nonZero
    hairSideLayer.opacity  = 0.0
    container.layer.addSublayer(hairSideLayer)

    // Hair mask layer — contains pixels that are ALREADY colour-processed
    // (luminance-boosted HSL transfer sampled from the live camera frame).
    // Plain srcOver compositing: no blend filter needed.
    // Layer opacity = intensity slider, same as lipstick fillColor alpha.
    hairMaskLayer.frame = container.bounds
    hairMaskLayer.opacity = 0.0
    hairMaskLayer.contentsGravity = .resizeAspectFill
    hairMaskLayer.minificationFilter = .trilinear
    hairMaskLayer.magnificationFilter = .trilinear
    hairMaskLayer.compositingFilter = nil
    hairMaskLayer.actions = [
      "contents": NSNull(),
      "opacity": NSNull(),
      "bounds": NSNull(),
      "position": NSNull(),
    ]
    container.layer.addSublayer(hairMaskLayer)
    
    hairImageLayer.frame = container.bounds
    hairImageLayer.opacity = 0.0
    hairImageLayer.contentsGravity = .resize  // fill our computed bounds exactly — no letterboxing
    container.layer.addSublayer(hairImageLayer)

    nailOverlayLayer.frame = container.bounds
    nailOverlayLayer.fillColor = UIColor.clear.cgColor
    // Subtle dark rim around each nail for depth/edge definition
    nailOverlayLayer.strokeColor = UIColor.black.withAlphaComponent(0.18).cgColor
    nailOverlayLayer.lineWidth = 1.0
    nailOverlayLayer.opacity = 0
    nailOverlayLayer.zPosition = 500
    // Normal SRC_OVER with tuned alpha: always visible on any background.
    // Multiply looked good on plain skin but turned near-black on coloured backgrounds.
    nailOverlayLayer.compositingFilter = nil
    container.layer.addSublayer(nailOverlayLayer)

    // ── Cuticle shadow (sits just above the base colour) ─────────────────────
    // A small dark semi-transparent oval drawn over the cuticle end of each
    // nail creates the depth illusion that makes polish look 3-D and lacquered.
    nailCuticleLayer.frame = container.bounds
    nailCuticleLayer.fillColor = UIColor.black.withAlphaComponent(0.22).cgColor
    nailCuticleLayer.strokeColor = UIColor.clear.cgColor
    nailCuticleLayer.opacity = 0
    nailCuticleLayer.zPosition = 500.5
    nailCuticleLayer.compositingFilter = nil
    container.layer.addSublayer(nailCuticleLayer)

    // ── Specular highlight (topmost nail layer) ───────────────────────────────
    nailHighlightLayer.frame = container.bounds
    nailHighlightLayer.fillColor = UIColor.white.withAlphaComponent(0.48).cgColor
    nailHighlightLayer.strokeColor = UIColor.clear.cgColor
    nailHighlightLayer.opacity = 0
    nailHighlightLayer.zPosition = 501
    // Screen blend: white highlight brightens the nail colour naturally.
    nailHighlightLayer.compositingFilter = "screenBlendMode"
    container.layer.addSublayer(nailHighlightLayer)

    nailDebugLayer.frame = container.bounds
    nailDebugLayer.fillColor = UIColor.clear.cgColor
    nailDebugLayer.strokeColor = UIColor.white.withAlphaComponent(0.85).cgColor
    nailDebugLayer.lineWidth = 1.0
    nailDebugLayer.opacity = 0
    nailDebugLayer.zPosition = 510
    container.layer.addSublayer(nailDebugLayer)

    nailSegmentLayer.frame = container.bounds
    nailSegmentLayer.opacity = 0
    nailSegmentLayer.contentsGravity = .resize // v20: Direct UI-Space geometry projection
    nailSegmentLayer.contentsScale = UIScreen.main.scale // Fix: Match Retina density
    nailSegmentLayer.zPosition = 505 // Above fallback
    container.layer.addSublayer(nailSegmentLayer)
  }

  private func setupFaceLandmarker() {
    guard let modelPath = Bundle.main.path(forResource: "face_landmarker", ofType: "task") else {
        print("❌ iOS: face_landmarker.task not found in bundle")
        return
    }

    let options = FaceLandmarkerOptions()
    options.baseOptions.modelAssetPath = modelPath
    options.runningMode = .video
    options.numFaces = 1
    options.minFaceDetectionConfidence = 0.3

    do {
        faceLandmarker = try FaceLandmarker(options: options)
    } catch {
        print("❌ iOS: Failed to initialize FaceLandmarker: \(error)")
    }
  }

  private func ensurePhotoFaceLandmarker() -> FaceLandmarker? {
    if let lm = photoFaceLandmarker { return lm }
    guard let modelPath = Bundle.main.path(forResource: "face_landmarker", ofType: "task") else {
      print("❌ iOS: face_landmarker.task not found in bundle (photo)")
      return nil
    }
    let options = FaceLandmarkerOptions()
    options.baseOptions.modelAssetPath = modelPath
    options.runningMode = .image
    options.numFaces = 1
    options.minFaceDetectionConfidence = 0.3
    do {
      let lm = try FaceLandmarker(options: options)
      photoFaceLandmarker = lm
      return lm
    } catch {
      print("❌ iOS: Failed to initialize FaceLandmarker (photo): \(error)")
      return nil
    }
  }

  private func setupHandLandmarker() {
    guard let modelPath = Bundle.main.path(forResource: "hand_landmarker", ofType: "task") else {
      print("⚠️ iOS: hand_landmarker.task not found")
      return
    }
    let options = HandLandmarkerOptions()
    options.baseOptions.modelAssetPath = modelPath
    // Live stream mode gives MediaPipe temporal context and more stable finger presence.
    options.runningMode = .video
    // Keep two candidates so a briefly dominant secondary hand can be reacquired quickly.
    options.numHands = 2
    // Tuned for live try-on stability (reduces jitter + false positives when moving).
    // Matches Android defaults in this repo.
    // Very permissive thresholds so all 5 fingers are tracked reliably
    // even during fast movement or partial occlusion.
    options.minHandDetectionConfidence = 0.10
    options.minHandPresenceConfidence = 0.10
    options.minTrackingConfidence = 0.15
    do {
      handLandmarker = try HandLandmarker(options: options)
    } catch {
      print("❌ iOS: HandLandmarker init failed: \(error)")
    }
  }

  private func setupHairSegmenter() {
    if hairSegmenter != nil, hairColorImageSegmenter != nil { return }
    guard let modelPath = Bundle.main.path(forResource: "hair_segmenter", ofType: "tflite") else {
        print("DEBUG: hair_segmenter.tflite NOT FOUND in bundle")
        print("⚠️ iOS: hair_segmenter.tflite not found — hair segmentation unavailable")
        return
    }
    print("DEBUG: Found hair_segmenter.tflite at \(modelPath)")

    if hairSegmenter == nil {
      let vOpts = ImageSegmenterOptions()
      vOpts.baseOptions.modelAssetPath = modelPath
      vOpts.runningMode = .video
      vOpts.shouldOutputConfidenceMasks = true
      vOpts.shouldOutputCategoryMask = false
      do {
        hairSegmenter = try ImageSegmenter(options: vOpts)
        print("DEBUG: ImageSegmenter (video) initialized for hair style / fallback")
      } catch {
        print("DEBUG: ImageSegmenter (video) failed: \(error)")
      }
    }

    if hairColorImageSegmenter == nil {
      let iOpts = ImageSegmenterOptions()
      iOpts.baseOptions.modelAssetPath = modelPath
      iOpts.runningMode = .image
      iOpts.shouldOutputConfidenceMasks = true
      iOpts.shouldOutputCategoryMask = false
      do {
        hairColorImageSegmenter = try ImageSegmenter(options: iOpts)
        print("DEBUG: ImageSegmenter (image) initialized for live hair colour")
      } catch {
        print("DEBUG: ImageSegmenter (image) failed — live colour will use video segmenter: \(error)")
      }
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      startCamera()
      result(nil)
    case "stop":
      stopCamera()
      result(nil)
    case "setEffect":
        if let args = call.arguments as? [String: Any] {
            self.usesMakeupLookStack = false
            self.makeupLookStack = []
            let oldNail = self.currentCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "cmd_nails"
            let shadeNum = args["shade"] as? NSNumber
            let intensityNum = args["intensity"] as? NSNumber

            if let shadeNum, let intensityNum {
                self.currentShade = UIColor(argb: shadeNum.int64Value)
                self.currentIntensity = CGFloat(intensityNum.doubleValue)
            }
            if let cat = args["category"] as? String {
                self.currentCategory = cat
            }
            if let na = args["nailArtStyle"] as? NSNumber {
                self.currentNailArtStyle = na.intValue
            }
            if let ns = args["nailShape"] as? NSNumber {
                self.currentNailShape = ns.intValue
            }
            if let shape = args["hairStyleShape"] as? String {
                self.currentHairStyleShape = shape.lowercased()
            }
            if let compare = args["isCompareMode"] as? Bool {
                self.isCompareMode = compare
            }
            if let filePath = args["imageFilePath"] as? String {
                self.currentImageAsset = filePath // just using the same variable conceptually
                if let image = UIImage(contentsOfFile: filePath) {
                    self.hairImageLayer.contents = image.cgImage
                }
            } else {
                self.currentImageAsset = nil
                self.hairImageLayer.contents = nil
            }
            // Basic fill setup, will override in drawLips if needed
            self.lipOverlayLayer.fillColor = self.currentShade.withAlphaComponent(self.currentIntensity).cgColor
            self.lipOverlayLayer.shadowOpacity = 0 // reset shadow

            let newNail = self.currentCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "cmd_nails"
            if oldNail != newNail {
                if self.captureSession != nil {
                    self.stopCamera()
                    self.startCamera()
                }
            }
            if newNail {
                // Clear rolling-average so previous session's positions are not reused.
                self.prevNailFrame = Array(repeating: NailFrame(), count: 5)
                self.prevNailGeom = Array(repeating: NailGeomState(), count: 5)
                self.nailMissFrames = Array(repeating: 0, count: 5)
                self.nailHideFrames = Array(repeating: 0, count: 5)
                self.lipOverlayLayer.opacity = 0
                self.hairMaskLayer.opacity = 0
                self.nailOverlayLayer.opacity  = 1
                self.nailCuticleLayer.opacity   = 1
                self.nailHighlightLayer.opacity = 1
                self.nailSegmentLayer.opacity = 0
                self.nailSegmentLayer.contents = nil
            } else {
                self.nailOverlayLayer.path    = nil
                self.nailOverlayLayer.opacity  = 0
                self.nailCuticleLayer.path    = nil
                self.nailCuticleLayer.opacity   = 0
                self.nailHighlightLayer.path  = nil
                self.nailHighlightLayer.opacity = 0
                self.nailSegmentLayer.opacity = 0
                self.nailSegmentLayer.contents = nil
            }
            // Hair / wig modes must not keep lip or stacked-makeup vectors (first frames used
            // default "Lip Sticks" and could paint a full-screen path → black preview).
            let cLow = self.currentCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if cLow == "cmd_haircolor" || cLow == "cmd_hairstyle" {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.lipOverlayLayer.path = nil
                self.lipOverlayLayer.opacity = 0
                for sl in self.makeupSlotLayers {
                  sl.path = nil
                  sl.opacity = 0
                }
                self.makeupStackParent.mask = nil
                CATransaction.commit()
            }
            // Live hair: soft-light composites tint with the camera preview (more “in the hair” than srcOver alone).
            self.hairMaskLayer.compositingFilter = (cLow == "cmd_haircolor") ? "softLightBlendMode" : nil
        }
        result(nil)
    case "setLook":
        if let args = call.arguments as? [String: Any] {
            self.usesMakeupLookStack = true
            if let compare = args["isCompareMode"] as? Bool {
                self.isCompareMode = compare
            }
            if let raw = args["layers"] as? [[String: Any]] {
                var stack: [MakeupLookEntry] = []
                for dict in raw {
                    guard let cat = dict["category"] as? String,
                          let sn = dict["shade"] as? NSNumber,
                          let ins = dict["intensity"] as? NSNumber else { continue }
                    let c = cat.trimmingCharacters(in: .whitespacesAndNewlines)
                    if c.lowercased() == "cmd_none" { continue }
                    stack.append(MakeupLookEntry(
                        category: c,
                        shade: UIColor(argb: sn.int64Value),
                        intensity: CGFloat(ins.doubleValue)
                    ))
                }
                self.makeupLookStack = stack.count > 10 ? Array(stack.prefix(10)) : stack
            } else {
                self.makeupLookStack = []
            }
        }
        result(nil)
    case "setPhoto":
        if let args = call.arguments as? [String: Any],
           let filePath = args["imageFilePath"] as? String,
           let img = UIImage(contentsOfFile: filePath) {
            let norm = self.normalizedUIImage(img)
            self.photoUIImage = self.downscaleForPhotoTryOn(norm)
        } else {
            self.photoUIImage = nil
        }
        result(nil)
    case "renderPhoto":
        photoRenderQueue.async { [weak self] in
            autoreleasepool {
                guard let self else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "photo", message: "renderer released", details: nil))
                    }
                    return
                }
                guard let base = self.photoUIImage else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "photo", message: "No photo set. Call setPhoto first.", details: nil))
                    }
                    return
                }
                guard let mp = try? MPImage(uiImage: base),
                      let lm = self.ensurePhotoFaceLandmarker() else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "photo", message: "Failed to prepare photo landmarker.", details: nil))
                    }
                    return
                }
                do {
                    let lmResult = try lm.detect(image: mp)
                    guard let png = self.renderMakeupOnPhoto(baseImage: base, result: lmResult) else {
                        DispatchQueue.main.async {
                            result(FlutterError(code: "photo", message: "Render failed.", details: nil))
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        result(FlutterStandardTypedData(bytes: png))
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "photo", message: error.localizedDescription, details: nil))
                    }
                }
            }
        }
    case "setDebug":
        if let args = call.arguments as? [String: Any],
           let show = args["showLandmarks"] as? Bool {
          self.showNailDebug = show
        }
        result(nil)
    case "setCalibration":
        if let args = call.arguments as? [String: Any],
           let splitPosition = args["splitPosition"] as? Double {
            self.currentSplitPosition = CGFloat(splitPosition)
        }
        result(nil)
    case "testTFLite":
        print("🧪 RUNNING TFLITE SANITY CHECK ON IOS DEVICE 🧪")
        if let interpreter = self.nailRenderer.interpreter {
            do {
                // Create a 224x224x3 block of pure float 1.0 (White Image)
                var floats = [Float](repeating: 1.0, count: 224 * 224 * 3)
                let inputData = floats.withUnsafeBufferPointer { Data(buffer: $0) }
                try interpreter.copy(inputData, toInputAt: 0)
                try interpreter.invoke()
                let outputTensor = try interpreter.output(at: 0)
                let outFloats = outputTensor.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                
                print("🧪 TFLITE OUTPUT SIZE: \(outFloats.count)")
                if outFloats.count > 0 {
                    print("🧪 TFLITE OUTPUT SAMPLE: [\(outFloats[0]), \(outFloats[100]), \(outFloats[5000]), \(outFloats[25000])]")
                    let maxVal = outFloats.max() ?? -1.0
                    let minVal = outFloats.min() ?? -1.0
                    print("🧪 TFLITE OUTPUT MIN/MAX: \(minVal) to \(maxVal)")
                    result(true)
                } else {
                    result(false)
                }
            } catch {
                print("❌ TFLITE CRITICAL FAILURE: \(error)")
                result(false)
            }
        } else {
            print("❌ TFLITE INTERPRETER NIL")
            result(false)
        }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func isNailCategory() -> Bool {
    currentCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "cmd_nails"
  }

  private func startCamera() {
    if isNailCategory(), handLandmarker == nil {
      setupHandLandmarker()
    }
    // Hair colour uses ImageSegmenter only; loading FaceLandmarker here spikes memory and can
    // contribute to jetsam + a stuck black preview layer on some devices.
    let cat = currentCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if cat != "cmd_haircolor" {
      if faceLandmarker == nil {
        setupFaceLandmarker()
      }
    }

    let session = AVCaptureSession()
    // Smaller frames for live hair colour → MediaPipe + mask finish sooner → less tint lag when moving.
    if cat == "cmd_haircolor" {
      if session.canSetSessionPreset(.vga640x480) {
        session.sessionPreset = .vga640x480
      } else if session.canSetSessionPreset(.medium) {
        session.sessionPreset = .medium
      } else {
        session.sessionPreset = .hd1280x720
      }
    } else {
      session.sessionPreset = .hd1280x720
    }

    let position: AVCaptureDevice.Position = isNailCategory() ? .back : .front
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
          let input = try? AVCaptureDeviceInput(device: device) else {
            sendError(code: "camera", message: "Failed to access camera")
            return
          }

    // Improve close-hand tracking stability for nail mode.
    if isNailCategory() {
      do {
        try device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) {
          device.focusMode = .continuousAutoFocus
        }
        if device.isAutoFocusRangeRestrictionSupported {
          device.autoFocusRangeRestriction = .near
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
          device.exposureMode = .continuousAutoExposure
        }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
          device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        device.unlockForConfiguration()
      } catch {
        print("⚠️ iOS: Unable to tune nail camera focus/exposure: \(error)")
      }
    }

    // Live hair: modest FPS cap so each segmentation + mask pass can finish before the next frame piles up
    // (reduces “tint dragging behind” the face when moving).
    if cat == "cmd_haircolor" {
      do {
        try device.lockForConfiguration()
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 18)
        device.unlockForConfiguration()
      } catch {
        print("⚠️ iOS: hair colour FPS cap: \(error)")
      }
    }

    if session.canAddInput(input) {
        session.addInput(input)
    }

    let output = AVCaptureVideoDataOutput()
    output.alwaysDiscardsLateVideoFrames = true
    output.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)]
    output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_queue", qos: .userInteractive))
    if session.canAddOutput(output) {
        session.addOutput(output)
    }
    
    if let connection = output.connection(with: .video) {
        if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
        // Do **not** set `isVideoMirrored` on the video-data output connection: on recent iOS,
        // `automaticallyAdjustsVideoMirroring` may stay YES for this connection type, which
        // throws if you call `setVideoMirrored:`. ML uses the natural buffer; hair overlay flip
        // (`hairFlipToMatchMirroredPreview`) matches the mirrored preview instead.
        if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
    }

    hairFlipToMatchMirroredPreview = (position == .front)

    let preview = AVCaptureVideoPreviewLayer(session: session)
    preview.frame = container.bounds
    preview.videoGravity = .resizeAspectFill
    if let previewConn = preview.connection {
        if previewConn.isVideoOrientationSupported { previewConn.videoOrientation = .portrait }
        if previewConn.isVideoStabilizationSupported {
        previewConn.preferredVideoStabilizationMode = .off
        }
    }
    container.layer.insertSublayer(preview, at: 0)

    self.captureSession = session
    self.previewLayer = preview

    // startRunning must run on the main thread; starting from a background QoS queue
    // commonly yields a black preview layer (especially after memory pressure / hair ML init).
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      session.startRunning()
      self.applyPreviewVideoMirroring(forCameraPosition: position)
      self.container.setNeedsLayout()
      self.container.layoutIfNeeded()
      self.previewLayer?.frame = self.container.bounds
      self.applyHairOverlayFlipForPreview(bounds: self.container.bounds)
      self.sendEvent(["type": "ready"])
      // Flutter PlatformView often lays out after the first frame; a second main-queue pass
      // fixes a persistent black preview when bounds were still .zero during startRunning().
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.applyPreviewVideoMirroring(forCameraPosition: position)
        self.previewLayer?.frame = self.container.bounds
        self.applyHairOverlayFlipForPreview(bounds: self.container.bounds)
      }
    }
  }

  /// Horizontally flip hair bitmap layers so they align with the **mirrored** front-camera preview
  /// (`CMSampleBuffer` / MediaPipe use the unmirrored buffer by default).
  private func applyHairOverlayFlipForPreview(bounds: CGRect) {
    guard hairFlipToMatchMirroredPreview, bounds.width > 2, bounds.height > 2 else {
      hairMaskLayer.setAffineTransform(.identity)
      hairImageLayer.setAffineTransform(.identity)
      return
    }
    hairMaskLayer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
    hairImageLayer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
  }

  /// Preview mirroring must run with `automaticallyAdjustsVideoMirroring == false` and is safest **after** `startRunning()`.
  private func applyPreviewVideoMirroring(forCameraPosition position: AVCaptureDevice.Position) {
    guard let conn = previewLayer?.connection else { return }
    guard conn.isVideoMirroringSupported else { return }
    conn.automaticallyAdjustsVideoMirroring = false
    conn.isVideoMirrored = (position == .front)
  }

  private func stopCamera() {
    lastHairMaskRgba = nil
    hairFlipToMatchMirroredPreview = false
    hairMaskLayer.setAffineTransform(.identity)
    hairMaskLayer.compositingFilter = nil
    hairImageLayer.setAffineTransform(.identity)
    hairUiSerialLock.lock()
    hairUiApplySerial = 0
    hairUiSerialLock.unlock()
    hairCoalesceLock.lock()
    latestHairSampleBuffer = nil
    hairColorPipeRunning = false
    hairColorLastSegmentTsMs = 0
    hairCoalesceLock.unlock()
    captureSession?.stopRunning()
    previewLayer?.removeFromSuperlayer()
    captureSession = nil
    previewLayer = nil
  }

  /// Drain the single-slot hair queue under one lock so we always process the **freshest** frame
  /// (avoids spinning on `continue` when a new sample arrives every frame while ML is slower than FPS).
  private func dequeueCoalescedLatestHairSampleBuffer() -> CMSampleBuffer? {
    hairCoalesceLock.lock()
    defer { hairCoalesceLock.unlock() }
    guard var sb = latestHairSampleBuffer else { return nil }
    latestHairSampleBuffer = nil
    while let newer = latestHairSampleBuffer {
      sb = newer
      latestHairSampleBuffer = nil
    }
    return sb
  }

  /// Enqueue latest camera sample; a serial worker on `hairQueue` keeps only the freshest buffer.
  private func enqueueLiveHairColorSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    hairCoalesceLock.lock()
    latestHairSampleBuffer = sampleBuffer
    let shouldStart = !hairColorPipeRunning
    hairColorPipeRunning = true
    hairCoalesceLock.unlock()
    if shouldStart {
      hairQueue.async { [weak self] in
        self?.drainLiveHairColorFrames()
      }
    }
  }

  private func drainLiveHairColorFrames() {
    while true {
      guard let sb = dequeueCoalescedLatestHairSampleBuffer() else {
        hairCoalesceLock.lock()
        hairColorPipeRunning = false
        hairCoalesceLock.unlock()
        return
      }

      let capTs: Int = {
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        let sec = CMTimeGetSeconds(pts)
        if sec.isFinite, sec > 0 { return Int(sec * 1000.0) }
        return Int(Date().timeIntervalSince1970 * 1000.0)
      }()

      let cat = currentCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard cat == "cmd_haircolor" else {
        hairCoalesceLock.lock()
        latestHairSampleBuffer = nil
        hairColorPipeRunning = false
        hairCoalesceLock.unlock()
        return
      }

      guard hairSegmenter != nil || hairColorImageSegmenter != nil else {
        hairCoalesceLock.lock()
        latestHairSampleBuffer = nil
        hairColorPipeRunning = false
        hairCoalesceLock.unlock()
        return
      }

      guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }

      let mpImage: MPImage
      do {
        mpImage = try MPImage(sampleBuffer: sb)
      } catch {
        continue
      }

      let segResult: ImageSegmenterResult
      do {
        if let ims = hairColorImageSegmenter {
          segResult = try ims.segment(image: mpImage)
        } else if let vs = hairSegmenter {
          hairColorLastSegmentTsMs = max(hairColorLastSegmentTsMs + 1, capTs)
          segResult = try vs.segment(
            videoFrame: mpImage,
            timestampInMilliseconds: hairColorLastSegmentTsMs)
        } else {
          continue
        }
      } catch {
        continue
      }

      let shade = currentShade
      let intensity = Float(currentIntensity)
      let cgImg = processHairMask(
        segResult,
        pixelBuffer: pb,
        shade: shade,
        styleShape: nil,
        liveColourTemporalBlend: false,
        liveColourAlphaTemporalSmooth: false,
        processingScale: 10)

      let imgRef = cgImg
      let opacityRef = intensity
      hairUiSerialLock.lock()
      hairUiApplySerial += 1
      let token = hairUiApplySerial
      hairUiSerialLock.unlock()
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.hairUiSerialLock.lock()
        let latest = self.hairUiApplySerial
        self.hairUiSerialLock.unlock()
        guard token == latest else { return }
        let stillHair = self.currentCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "cmd_haircolor"
        guard stillHair else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let img = imgRef {
          self.hairMaskLayer.compositingFilter = "softLightBlendMode"
          self.hairMaskLayer.contents = img
          self.hairMaskLayer.opacity = opacityRef
        }
        self.hairImageLayer.opacity = 0
        self.lipOverlayLayer.opacity = 0
        CATransaction.commit()
        CATransaction.flush()
      }

      hairCoalesceLock.lock()
      if latestHairSampleBuffer == nil {
        hairColorPipeRunning = false
        hairCoalesceLock.unlock()
        return
      }
      hairCoalesceLock.unlock()
    }
  }

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    let catLower = currentCategory.trimmingCharacters(in: .whitespaces).lowercased()
    let isHairColorMode   = catLower == "cmd_haircolor"
    let isHairStyleMode   = catLower == "cmd_hairstyle"

    if isHairColorMode {
      autoreleasepool {
        setupHairSegmenter()
        guard hairSegmenter != nil || hairColorImageSegmenter != nil,
              CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
        if let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
          lastCaptureBufferWidth = CGFloat(CVPixelBufferGetWidth(pb))
          lastCaptureBufferHeight = CGFloat(CVPixelBufferGetHeight(pb))
        }
        enqueueLiveHairColorSampleBuffer(sampleBuffer)
      }
      return
    }

    autoreleasepool {
      do {
        let image       = try MPImage(sampleBuffer: sampleBuffer)
        let timestampMs = Int(Date().timeIntervalSince1970 * 1000)

        // ── HAIR STYLE (WIG) MODE ────────────────────────────────────────────
        if isHairStyleMode {
          if faceLandmarker == nil { setupFaceLandmarker() }
          if hairSegmenter == nil { setupHairSegmenter() }
          // A) FaceLandmarker EVERY frame → smooth wig tracking
          if let landmarker = faceLandmarker {
            let lmResult = try landmarker.detect(videoFrame: image, timestampInMilliseconds: timestampMs)
            DispatchQueue.main.async { [weak self] in
              self?.lipOverlayLayer.opacity = 0
              self?.drawLips(lmResult)
            }
          }
          // B) HairSegmenter every wigSegmentEvery frames → slow background shadow mask
          wigFrameCounter += 1
          guard wigFrameCounter >= wigSegmentEvery else { return }
          wigFrameCounter = 0
          guard !isProcessingHair, let segmenter = hairSegmenter else { return }
          guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
          isProcessingHair = true
          let segResult = try segmenter.segment(videoFrame: image, timestampInMilliseconds: timestampMs)
          let shade    = self.currentShade
          let styleShape = self.currentHairStyleShape
          hairQueue.async { [weak self] in
            guard let self = self else { return }
            let cgImg = self.processHairMask(segResult, pixelBuffer: pixelBuffer, shade: shade, styleShape: styleShape)
            DispatchQueue.main.async {
              CATransaction.begin(); CATransaction.setDisableActions(true)
              if let img = cgImg {
                self.hairMaskLayer.compositingFilter = nil
                self.hairMaskLayer.contents = img
                self.hairMaskLayer.opacity  = Float(self.currentIntensity)
              }
              self.hairImageLayer.opacity = 0
              CATransaction.commit()
              self.isProcessingHair = false
            }
          }

        // ── NAIL TRY-ON (MediaPipe hands + Custom TFLite Segmenter) ──────────
        } else if catLower == "cmd_nails" {
          if let hl = handLandmarker {
            let lmResult = try hl.detect(videoFrame: image, timestampInMilliseconds: timestampMs)
            if let pbDims = CMSampleBufferGetImageBuffer(sampleBuffer) {
              lastCaptureBufferWidth = CGFloat(CVPixelBufferGetWidth(pbDims))
              lastCaptureBufferHeight = CGFloat(CVPixelBufferGetHeight(pbDims))
            }
            if useNailSegmentationLive, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
              // Segmentation is heavier; run it in background so landmark tracking stays responsive.
              nailFrameCounter &+= 1
              let shouldRunSeg = (nailFrameCounter % max(1, nailSegmentEvery)) == 0
              if shouldRunSeg && !self.isProcessingNailSeg {
                let segBounds = self.lastLayoutBounds
                if segBounds.width > 2, segBounds.height > 2 {
                  self.isProcessingNailSeg = true
                  let segIntensity = self.currentIntensity
                  let segShade = self.currentShade
                  let segArt = self.currentNailArtStyle
                  let segShape = self.currentNailShape
                  self.nailSegQueue.async { [weak self] in
                    guard let self = self else { return }
                    let segMask = self.nailRenderer.renderNailMask(
                  pixelBuffer: pixelBuffer,
                  handLandmarks: lmResult,
                      containerBounds: segBounds,
                      intensity: segIntensity,
                      polishColor: segShade,
                      artStyle: segArt,
                      nailShape: segShape
                    )
                    let reliability = self.nailRenderer.lastMaskReliability
                    DispatchQueue.main.async {
                      self.lastNailMaskReliability = reliability
                      self.lastNailMaskImage = segMask
                      self.isProcessingNailSeg = false
                    }
                  }
                }
              }

              DispatchQueue.main.async { [weak self] in
                  guard let self = self else { return }
                  CATransaction.begin()
                  CATransaction.setDisableActions(true)
                  self.hairMaskLayer.opacity = 0
                  self.lipOverlayLayer.opacity = 0

                  // Segmentation-assisted geometry mode:
                  // draw geometry first; if geometry is weak, use segmentation as visible fallback.
                  self.nailOverlayLayer.opacity = 1
                      self.drawNailOverlays(result: lmResult)
                  if self.lastDrawnNailsCount <= 1,
                     self.lastNailMaskReliability >= 0.08,
                     let segMask = self.lastNailMaskImage?.cgImage {
                    self.nailSegmentLayer.contents = segMask
                    self.nailSegmentLayer.opacity = Float(min(1.0, max(0.48, self.currentIntensity * 0.96)))
                  } else {
                      self.nailSegmentLayer.opacity = 0
                    self.nailSegmentLayer.contents = nil
                  }
                  CATransaction.commit()
              }
            } else {
              // Stable live mode: landmark nails only.
              DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.hairMaskLayer.opacity = 0
                self.lipOverlayLayer.opacity = 0
                self.nailSegmentLayer.opacity = 0
                self.nailSegmentLayer.contents = nil
                self.nailOverlayLayer.opacity = 1
                self.drawNailOverlays(result: lmResult)
                CATransaction.commit()
              }
            }
          } else {
            DispatchQueue.main.async { [weak self] in
              self?.lipOverlayLayer.opacity = 0
              self?.hairMaskLayer.opacity = 0
              self?.nailSegmentLayer.opacity = 0
            }
          }

        // ── ALL MAKEUP MODES ─────────────────────────────────────────────────
        } else {
          if let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
            lastCaptureBufferWidth = CGFloat(CVPixelBufferGetWidth(pb))
            lastCaptureBufferHeight = CGFloat(CVPixelBufferGetHeight(pb))
          }
          if let landmarker = faceLandmarker {
            let lmResult = try landmarker.detect(videoFrame: image, timestampInMilliseconds: timestampMs)
            DispatchQueue.main.async { [weak self] in
              self?.hairMaskLayer.opacity = 0
              self?.drawLips(lmResult)
            }
          }
        }
      } catch {
        isProcessingHair = false
      }
    }
  }

  /// Normalized landmark [0,1]² in **pixel-buffer / MPImage** space → view coords.
  /// Do not use `AVCaptureVideoPreviewLayer.layerPointConverted` here: on some OS/device
  /// combinations it returns non-finite or inconsistent points so every finger fails
  /// on-screen checks and nothing draws. Buffer aspect-fill matches MediaPipe input.
  private func landmarkNormToView(nx: CGFloat, ny: CGFloat) -> CGPoint {
    let px = min(0.999, max(0.001, nx))
    let py = min(0.999, max(0.001, ny))
    let manual = mapHandNormToPreview(nx: px, ny: py)
    // Prefer preview-layer mapping first (true camera->screen conversion).
    if let previewLayer = previewLayer {
      let p = previewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: px, y: py))
      if p.x.isFinite, p.y.isFinite, p.x > -200, p.y > -200,
         p.x < container.bounds.width + 200, p.y < container.bounds.height + 200 {
        // If preview-layer conversion diverges too much from aspect-fill mapping,
        // prefer manual mapping (prevents off-hand drifting on some iOS builds).
        let d = hypot(p.x - manual.x, p.y - manual.y)
        let maxAllowed = max(28, min(container.bounds.width, container.bounds.height) * 0.22)
        if d <= maxAllowed {
          return p
        }
      }
    }
    // Fallback to manual aspect-fill mapping.
    return manual
  }

  /// Aspect-fill fallback when preview is not ready; uses last known buffer size (not hardcoded 720×1280).
  private func mapHandNormToPreview(nx: CGFloat, ny: CGFloat) -> CGPoint {
    let viewW = container.bounds.width
    let viewH = container.bounds.height
    if viewW < 2 || viewH < 2 { return .zero }
    let bw = lastCaptureBufferWidth > 8 ? lastCaptureBufferWidth : 720
    let bh = lastCaptureBufferHeight > 8 ? lastCaptureBufferHeight : 1280
    // MediaPipe runs on the unmirrored buffer; front preview is mirrored — match previewLayer.
    let mx = hairFlipToMatchMirroredPreview ? (1 - nx) : nx
    return NailPolishRenderer.aspectFillNormToView(nx: mx, ny: ny, bufferWidth: bw, bufferHeight: bh, viewWidth: viewW, viewHeight: viewH)
  }

  private func drawNailOverlays(result: HandLandmarkerResult?) {
    let bounds = container.bounds
    let vw = bounds.width
    let vh = bounds.height
    guard vw > 2, vh > 2 else { return }

    guard let result = result else {
      nailLostFrames += 1
      if nailLostFrames > 24 {
        nailOverlayLayer.path  = nil
        nailCuticleLayer.path  = nil
        nailHighlightLayer.path = nil
        nailDebugLayer.path    = nil
        lastDrawnNailsCount = 0
      }
      return
    }

    let lmList = result.landmarks
    guard !lmList.isEmpty else {
      nailLostFrames += 1
      if nailLostFrames > 24 {
        nailOverlayLayer.path  = nil
        nailCuticleLayer.path  = nil
        nailHighlightLayer.path = nil
        nailDebugLayer.path    = nil
        lastDrawnNailsCount = 0
      }
      return
    }

    var best = lmList[0]
    var bestScore: CGFloat = -1
    var bestCenterNorm = CGPoint(x: 0.5, y: 0.5)
    for hand in lmList {
      guard hand.count >= 21 else { continue }
      var minX: CGFloat = 1
      var maxX: CGFloat = 0
      var minY: CGFloat = 1
      var maxY: CGFloat = 0
      var sumX: CGFloat = 0
      var sumY: CGFloat = 0
      for p in hand {
        let x = CGFloat(p.x)
        let y = CGFloat(p.y)
        minX = min(minX, x)
        maxX = max(maxX, x)
        minY = min(minY, y)
        maxY = max(maxY, y)
        sumX += x
        sumY += y
      }
      let area = (maxX - minX) * (maxY - minY)
      let center = CGPoint(x: sumX / CGFloat(hand.count), y: sumY / CGFloat(hand.count))
      // Prefer the largest hand, but bias toward continuity with the previously tracked hand.
      var score = area
      if let prev = lastTrackedHandCenterNorm {
        let d = hypot(center.x - prev.x, center.y - prev.y) // normalized distance
        score += max(0, 0.42 - d) * 0.9
      }
      if score > bestScore {
        bestScore = score
        best = hand
        bestCenterNorm = center
      }
    }

    guard best.count >= 21 else {
      nailLostFrames += 1
      if nailLostFrames > 24 {
        nailOverlayLayer.path = nil
        nailHighlightLayer.path = nil
        nailDebugLayer.path = nil
        lastDrawnNailsCount = 0
        lastTrackedHandCenterNorm = nil
      }
      return
    }
    nailLostFrames = 0
    lastTrackedHandCenterNorm = bestCenterNorm

    // --- Robust mapping (production approach) ---
    // Use the preview layer's displayed video rect (aspectFill) and apply ONE rotation
    // based on the connection orientation. This avoids double-rotation/flips.
    func clamp01(_ v: CGFloat) -> CGFloat { min(0.999, max(0.001, v)) }
    func rawNorm(_ idx: Int) -> CGPoint? {
      guard best.count > idx else { return nil }
      return CGPoint(x: clamp01(CGFloat(best[idx].x)), y: clamp01(CGFloat(best[idx].y)))
    }

    func normToView(_ p: CGPoint) -> CGPoint {
      landmarkNormToView(nx: p.x, ny: p.y)
    }

    func lp(_ idx: Int) -> CGPoint? {
      guard let r = rawNorm(idx) else { return nil }
      return normToView(r)
    }
    func distPx(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    // Debug overlay: all 21 landmark dots + finger axis lines (dip→tip).
    // TIP landmarks (4,8,12,16,20) drawn as large 9pt circles; others as 4pt.
    if showNailDebug {
      let dbg = UIBezierPath()
      let tipIndices: Set<Int> = [4, 8, 12, 16, 20]
      let dipIndices: Set<Int> = [3, 7, 11, 15, 19]
      for i in 0..<min(21, best.count) {
        let p = CGPoint(x: CGFloat(best[i].x), y: CGFloat(best[i].y))
        let v = normToView(p)
        let r: CGFloat = tipIndices.contains(i) ? 5.5 : (dipIndices.contains(i) ? 4 : 2.5)
        dbg.append(UIBezierPath(ovalIn: CGRect(x: v.x - r, y: v.y - r, width: r*2, height: r*2)))
      }
      let axes: [(Int, Int)] = [(3,4),(7,8),(11,12),(15,16),(19,20)]
      for (a,b) in axes {
        if let pa = lp(a), let pb = lp(b) {
          dbg.move(to: pa)
          dbg.addLine(to: pb)
        }
      }
      nailDebugLayer.opacity = 1
      nailDebugLayer.path = dbg.cgPath
    } else {
      nailDebugLayer.opacity = 0
      nailDebugLayer.path = nil
    }

    // ------------------------------------------------------------------------
    // SIMPLE NAIL MODE (deadline-safe):
    // Render each nail directly from TIP->DIP with conservative sizing.
    // This avoids drift from complex geometric/hybrid corrections.
    // ------------------------------------------------------------------------
    if forceSimpleNailMode {
      let simplePath = UIBezierPath()
      let cuticlePath = UIBezierPath()
      let highlightPath = UIBezierPath()
      let handWidthSimple: CGFloat = {
        guard let a = lp(5), let b = lp(17) else { return 80 }
        return max(40, distPx(a, b))
      }()

      let fingerIdx: [(tip: Int, dip: Int, widthMul: CGFloat, lenMul: CGFloat)] = [
        (4, 3, 0.62, 0.96),   // thumb
        (8, 7, 0.52, 1.04),   // index
        (12, 11, 0.54, 1.06), // middle
        (16, 15, 0.52, 1.04), // ring
        (20, 19, 0.48, 1.00), // pinky
      ]

      var drawn = 0
      var refWidth: CGFloat = 18
      for (i, f) in fingerIdx.enumerated() {
        let maxMissHold = 10
        var tip: CGPoint
        var dip: CGPoint
        let wrist = lp(0)

        if let t = lp(f.tip), let d = lp(f.dip) {
          let onSc: (CGPoint) -> Bool = { p in
            p.x > -50 && p.y > -50 && p.x < vw + 50 && p.y < vh + 50
          }
          guard onSc(t), onSc(d) else { continue }
          tip = t
          dip = d
          prevNailFrame[i] = NailFrame(tip: t, dip: d, pip: d, valid: true)
          nailMissFrames[i] = 0
        } else if prevNailFrame[i].valid, nailMissFrames[i] < maxMissHold {
          nailMissFrames[i] += 1
          tip = prevNailFrame[i].tip
          dip = prevNailFrame[i].dip
        } else {
          prevNailFrame[i].valid = false
          nailMissFrames[i] = 0
          continue
        }

        let seg = max(1.0, distPx(tip, dip))
        if seg < 1.8 { continue }
        // Reject obviously folded fingers that produce unstable tip/dip axes.
        if let wrist {
          let ax0 = tip.x - dip.x
          let ay0 = tip.y - dip.y
          let wx = tip.x - wrist.x
          let wy = tip.y - wrist.y
          let outward = ax0 * wx + ay0 * wy
          if outward < -max(14, handWidthSimple * 0.22) { continue }
        }
        let ax = (tip.x - dip.x) / seg
        let ay = (tip.y - dip.y) / seg
        var len = seg * f.lenMul
        var wid = seg * f.widthMul
        // Clamp to avoid giant floating nails.
        len = min(42.0, max(12.0, len))
        wid = min(22.0, max(7.0, wid))

        let center = CGPoint(
          x: tip.x - ax * (len * 0.44),
          y: tip.y - ay * (len * 0.44)
        )
        var angle = atan2(ay, ax) + .pi / 2.0
        var stableCenter = center
        var stableLen = len
        var stableWid = wid

        // Reject sudden per-finger jumps and keep last stable geometry briefly.
        if prevNailGeom[i].valid {
          let prev = prevNailGeom[i]
          let jump = distPx(stableCenter, prev.center)
          let jumpLimit = max(28, handWidthSimple * 0.75)
          let deltaA = abs(atan2(sin(angle - prev.angle), cos(angle - prev.angle)))
          if jump > jumpLimit || deltaA > (.pi * 0.42) {
            stableCenter = prev.center
            angle = prev.angle
            stableLen = prev.length
            stableWid = prev.width
          }
        }
        prevNailGeom[i] = NailGeomState(
          center: stableCenter,
          angle: angle,
          width: stableWid,
          length: stableLen,
          valid: true
        )
        let yTop = -stableLen / 2.0

        let nail = UIBezierPath(ovalIn: CGRect(x: -stableWid / 2.0, y: yTop, width: stableWid, height: stableLen))
        let tr = CGAffineTransform(translationX: stableCenter.x, y: stableCenter.y)
          .concatenating(CGAffineTransform(rotationAngle: angle))
        nail.apply(tr)
        simplePath.append(nail)

        let cs = UIBezierPath(ovalIn: CGRect(x: -stableWid * 0.28, y: stableLen * 0.36, width: stableWid * 0.56, height: stableLen * 0.14))
        cs.apply(tr)
        cuticlePath.append(cs)

        let hl = UIBezierPath(ovalIn: CGRect(x: -stableWid * 0.12, y: yTop + stableLen * 0.06, width: stableWid * 0.24, height: stableLen * 0.50))
        hl.apply(tr)
        highlightPath.append(hl)

        drawn += 1
        if i == 2 { refWidth = stableWid }
      }

      CATransaction.begin()
      CATransaction.setDisableActions(true)
      let polishAlpha = min(1.0, max(0.82, 0.82 + currentIntensity * 0.18))
      nailOverlayLayer.fillRule = .nonZero
      nailOverlayLayer.fillColor = currentShade.withAlphaComponent(polishAlpha).cgColor
      nailOverlayLayer.strokeColor = UIColor.black.withAlphaComponent(0.20).cgColor
      nailOverlayLayer.lineWidth = max(0.55, refWidth * 0.028)
      nailOverlayLayer.path = simplePath.cgPath

      nailCuticleLayer.fillColor = UIColor.black.withAlphaComponent(Double(currentIntensity) * 0.16).cgColor
      nailCuticleLayer.path = cuticlePath.cgPath

      nailHighlightLayer.fillColor = UIColor.white.withAlphaComponent(Double(currentIntensity) * 0.66).cgColor
      nailHighlightLayer.opacity = Float(min(1, max(0, currentIntensity)))
      nailHighlightLayer.path = highlightPath.cgPath
      CATransaction.commit()

      lastDrawnNailsCount = drawn
      return
    }

    // ── Finger landmark indices (MediaPipe Hands) ────────────────────────────
    // thumb:  4=tip  3=dip(ip) 2=pip(mcp)
    // index:  8=tip  7=dip     6=pip
    // middle: 12=tip 11=dip    10=pip
    // ring:   16=tip 15=dip    14=pip
    // pinky:  20=tip 19=dip    18=pip
    // pip added so axis is computed over 2 phalanges → stable for flat-hand poses
    // widMul tuned from live misalignment shots: more width on outer fingers + thumb.
    let fingers: [(tip: Int, dip: Int, pip: Int, widMul: CGFloat)] = [
      (4,  3,  2,  0.82),  // thumb
      (8,  7,  6,  0.88),  // index
      (12, 11, 10, 0.90),  // middle — widest
      (16, 15, 14, 0.88),  // ring
      (20, 19, 18, 0.78),  // pinky
    ]

    // ── Hand width: index-MCP → pinky-MCP (stable in all poses) ─────────────
    let handWidth: CGFloat = {
      guard let a = lp(5), let b = lp(17) else { return 80 }
      return max(40, distPx(a, b))
    }()
    // ── Draw each finger — lipstick-style: work in screen-space coords ────────
    // KEY PRINCIPLE (same as drawLips): smooth the SOURCE LANDMARKS (DIP, TIP)
    // directly, then analytically derive center+angle from them so the cuticle
    // is always locked to the DIP landmark and the free edge always reaches past
    // the TIP landmark.  No "X % of the way from DIP to TIP" guessing.
    let path          = UIBezierPath()
    let cuticlePath   = UIBezierPath()
    let highlightPath = UIBezierPath()
    var refWidth: CGFloat = 22
    var drawnCount = 0

    for (idx, f) in fingers.enumerated() {
      // Hold longer to suppress blink during short landmark dropouts.
      let maxMissHold = 5
      var rawTip: CGPoint
      var rawDip: CGPoint
      var rawPip: CGPoint
      if let t = lp(f.tip), let d = lp(f.dip), let p = lp(f.pip) {
        rawTip = t
        rawDip = d
        rawPip = p
      } else if prevNailFrame[idx].valid && nailMissFrames[idx] < maxMissHold {
        // Keep last locked position briefly when landmarks flicker.
        nailMissFrames[idx] += 1
        rawTip = prevNailFrame[idx].tip
        rawDip = prevNailFrame[idx].dip
        rawPip = prevNailFrame[idx].pip
      } else {
        prevNailFrame[idx].valid = false
        nailMissFrames[idx] = 0
        continue
      }

      // On-screen sanity check
      let onSc: (CGPoint) -> Bool = { p in
        p.x > -60 && p.y > -60 && p.x < vw + 60 && p.y < vh + 60
      }
      guard onSc(rawTip), onSc(rawDip) else {
        prevNailFrame[idx].valid = false
        prevNailGeom[idx].valid = false
        continue
      }

      // ── Adaptive EMA smoothing on TIP/DIP/PIP
      // Faster response on quick movement, stronger smoothing while steady.
      let tip: CGPoint
      let dip: CGPoint
      let pip: CGPoint
      let alpha: CGFloat
      if prevNailFrame[idx].valid {
        let motion = max(distPx(rawTip, prevNailFrame[idx].tip), distPx(rawDip, prevNailFrame[idx].dip))
        let normMotion = min(1.0, motion / max(1.0, handWidth * 0.18))
        // Slightly snappier EMA so polish follows the hand with less visible lag.
        alpha = 0.68 + (0.92 - 0.68) * normMotion
        tip = CGPoint(x: alpha * rawTip.x + (1 - alpha) * prevNailFrame[idx].tip.x,
                      y: alpha * rawTip.y + (1 - alpha) * prevNailFrame[idx].tip.y)
        dip = CGPoint(x: alpha * rawDip.x + (1 - alpha) * prevNailFrame[idx].dip.x,
                      y: alpha * rawDip.y + (1 - alpha) * prevNailFrame[idx].dip.y)
        pip = CGPoint(x: alpha * rawPip.x + (1 - alpha) * prevNailFrame[idx].pip.x,
                      y: alpha * rawPip.y + (1 - alpha) * prevNailFrame[idx].pip.y)
      } else {
        alpha = 0.90
        tip = rawTip
        dip = rawDip
        pip = rawPip
      }
      // IMPORTANT: store the smoothed landmark positions so the next frame
      // uses stable history (otherwise we average against raw jitter).
      prevNailFrame[idx] = NailFrame(tip: tip, dip: dip, pip: pip, valid: true)

      // ── Decide nail axis robustly (avoid cuticle drift) ────────────────
      // DIP→TIP provides the best anatomical direction (and keeps cuticle locked
      // to DIP when used). However, for flat/camera-facing poses, DIP→TIP
      // foreshortens and becomes unstable. In that case we fall back to the
      // longer PIP→TIP vector, and also scale length using an approximate
      // DIP→TIP ≈ 0.5 * PIP→TIP relationship.
      // Simplified, lipstick-style robust axis: use direct DIP→TIP, fallback to PIP→TIP only if tiny.
      let tipForGeom = tip
      let dipTipDist = max(1, distPx(dip, tipForGeom))
      let pipDipDist = max(1, distPx(pip, dip))
      let pipTipDist = max(1, distPx(pip, tipForGeom))

      let minAxisLen = max(1.2, handWidth * 0.008)
      if dipTipDist < minAxisLen || pipDipDist < minAxisLen * 0.25 { continue }

      let axisX: CGFloat
      let axisY: CGFloat
      if dipTipDist >= max(6, handWidth * 0.040) {
        axisX = (tipForGeom.x - dip.x) / dipTipDist
        axisY = (tipForGeom.y - dip.y) / dipTipDist
      } else {
        axisX = (tipForGeom.x - pip.x) / pipTipDist
        axisY = (tipForGeom.y - pip.y) / pipTipDist
      }

      // ── Step 3: deterministic per-finger fit (stable baseline) ─────────────
      let proxSeg = max(1.0, pipDipDist)
      let distSeg = max(1.0, dipTipDist)
      let widthShapeMul: CGFloat = {
        switch currentNailShape {
        case 2: return 0.50 // square
        case 3: return 0.44 // stiletto
        case 1: return 0.48 // almond
        default: return 0.50 // natural — screenshots: plate read narrow vs real nail
        }
      }()
      var nailWidRaw = proxSeg * widthShapeMul * f.widMul
      // Hybrid fit: segmentation aspect softly nudges width/length toward user's nail shape.
      if let obsAspect = nailRenderer.observedAspect(for: idx) {
        let safeObs = min(2.20, max(1.10, obsAspect))
        let widthScale = min(1.02, max(0.72, 1.52 / safeObs))
        nailWidRaw *= widthScale
      }
      let fitWidthMul: CGFloat = {
        switch idx {
        case 0: return 0.90 // thumb
        case 4: return 0.94 // pinky
        default: return 0.92
        }
      }()
      var nailWidClamped = min(52, max(handWidth * 0.042, nailWidRaw * fitWidthMul))

      let lenShapeMul: CGFloat = {
        switch currentNailShape {
        case 2: return 0.78 // square
        case 3: return 0.92 // stiletto
        case 1: return 0.86 // almond
        default: return 0.84 // natural — screenshots: polish sat too tip-ward; longer plate
        }
      }()
      var nailLen = distSeg * lenShapeMul
      if let obsAspect = nailRenderer.observedAspect(for: idx) {
        let safeObs = min(2.20, max(1.10, obsAspect))
        let lenScale = min(1.06, max(0.74, safeObs / 1.55))
        nailLen *= lenScale
      }
      let fitLenMul: CGFloat = {
        switch idx {
        case 0: return 0.93 // thumb
        case 4: return 0.96 // pinky
        default: return 0.93
        }
      }()
      nailLen *= fitLenMul
      nailLen = min(proxSeg * 1.12, max(proxSeg * 0.76, nailLen))

      // Ellipse long axis: blend DIP→TIP with PIP→DIP so width aligns with visible plate, not just bone.
      let drawAxisX: CGFloat
      let drawAxisY: CGFloat
      if idx == 0 {
        if let pipT = lp(2) {
          let tlen = max(1.0, distPx(pipT, dip))
          let px = (dip.x - pipT.x) / tlen
          let py = (dip.y - pipT.y) / tlen
          let b: CGFloat = 0.70
          var bx = axisX * b + px * (1 - b)
          var by = axisY * b + py * (1 - b)
          let bn = hypot(bx, by)
          if bn > 0.001 { bx /= bn; by /= bn }
          drawAxisX = bx
          drawAxisY = by
        } else {
          drawAxisX = axisX
          drawAxisY = axisY
        }
      } else {
        let px = (dip.x - pip.x) / pipDipDist
        let py = (dip.y - pip.y) / pipDipDist
        let b: CGFloat = 0.80
        var bx = axisX * b + px * (1 - b)
        var by = axisY * b + py * (1 - b)
        let bn = hypot(bx, by)
        if bn > 0.001 { bx /= bn; by /= bn }
        drawAxisX = bx
        drawAxisY = by
      }

      // Tip-side anchor: slightly more tip-ward so polish sits on the plate (flat-hand / dorsal views).
      let tipAnchor: CGFloat = (idx == 0) ? 0.42 : 0.43
      var center = CGPoint(
        x: tipForGeom.x - axisX * (nailLen * tipAnchor),
        y: tipForGeom.y - axisY * (nailLen * tipAnchor)
      )
      // Dorsal-side shift: nail plate sits off the bone axis; use palm→DIP vs perpendicular to bone.
      let nPerpX = -axisY
      let nPerpY = axisX
      // Deadline-safe alignment: keep nail centered on bone axis (no dorsal/hybrid nudges).
      var angle = atan2(drawAxisY, drawAxisX) + .pi / 2.0
      var drawWid = nailWidClamped
      var drawLen = nailLen

      // Temporal geometry smoothing to remove blink/jitter.
      if prevNailGeom[idx].valid {
        let motion = distPx(center, prevNailGeom[idx].center)
        let t = min(1.0, motion / max(1.0, handWidth * 0.16))
        let gAlpha: CGFloat = 0.44 + (0.76 - 0.44) * t
        center = CGPoint(
          x: gAlpha * center.x + (1 - gAlpha) * prevNailGeom[idx].center.x,
          y: gAlpha * center.y + (1 - gAlpha) * prevNailGeom[idx].center.y
        )
        let delta = atan2(sin(angle - prevNailGeom[idx].angle), cos(angle - prevNailGeom[idx].angle))
        angle = prevNailGeom[idx].angle + delta * gAlpha
        drawWid = gAlpha * drawWid + (1 - gAlpha) * prevNailGeom[idx].width
        drawLen = gAlpha * drawLen + (1 - gAlpha) * prevNailGeom[idx].length
      }
      prevNailGeom[idx] = NailGeomState(center: center, angle: angle, width: drawWid, length: drawLen, valid: true)

      if drawLen < 8 || drawWid < 5 {
        if prevNailGeom[idx].valid {
          center = prevNailGeom[idx].center
          angle = prevNailGeom[idx].angle
          drawWid = prevNailGeom[idx].width
          drawLen = prevNailGeom[idx].length
        } else {
          continue
        }
      }

      // ── Nail shape: fixed to detected nail plate ─────────────────────────
      // Local space uses the same convention across shapes:
      //   free edge  at yTop = -nailLen/2
      //   cuticle end at yBottom = +nailLen/2
      let yTop = -drawLen / 2
      let yBottom = drawLen / 2
      let halfW = drawWid / 2

      func nailBodyPath(shape: Int) -> UIBezierPath {
        switch shape {
        case 2: // square
          let corner = drawWid * 0.10
          return UIBezierPath(roundedRect: CGRect(x: -halfW, y: yTop, width: drawWid, height: drawLen), cornerRadius: corner)
        case 3: // stiletto
          // Sharp-ish point with curved edges.
          let leftBase  = CGPoint(x: -halfW, y: yBottom)
          let rightBase = CGPoint(x:  halfW, y: yBottom)
          let tipPoint  = CGPoint(x: 0, y: yTop)
          let leftCtl  = CGPoint(x: -halfW * 0.55, y: yTop + drawLen * 0.45)
          let rightCtl = CGPoint(x:  halfW * 0.55, y: yTop + drawLen * 0.45)
          let p = UIBezierPath()
          p.move(to: leftBase)
          p.addQuadCurve(to: tipPoint, controlPoint: leftCtl)
          p.addQuadCurve(to: rightBase, controlPoint: rightCtl)
          p.close()
          return p
        case 1: // almond (tapered oval)
          let topScale: CGFloat = 0.68
          let topHalf = halfW * topScale
          let leftTip = CGPoint(x: -topHalf, y: yTop)
          let rightTip = CGPoint(x: topHalf, y: yTop)
          let leftBase  = CGPoint(x: -halfW, y: yBottom)
          let rightBase = CGPoint(x:  halfW, y: yBottom)
          let p = UIBezierPath()
          p.move(to: leftTip)
          // Curved tip toward the center
          p.addCurve(to: rightTip,
                     controlPoint1: CGPoint(x: -topHalf * 0.2, y: yTop - drawLen * 0.05),
                     controlPoint2: CGPoint(x:  topHalf * 0.2, y: yTop - drawLen * 0.05))
          p.addLine(to: rightBase)
          // Curved sides back to left base
          p.addCurve(to: leftBase,
                     controlPoint1: CGPoint(x: halfW * 1.05, y: yTop + drawLen * 0.75),
                     controlPoint2: CGPoint(x: -halfW * 0.15, y: yTop + drawLen * 0.95))
          p.close()
          return p
        default: // natural
          // Natural nails are best approximated by a soft oval.
          return UIBezierPath(ovalIn: CGRect(x: -halfW, y: yTop, width: drawWid, height: drawLen))
        }
      }

      let nail = nailBodyPath(shape: currentNailShape)
      // concatenating applies its argument first → translate.concat(rotate) = R·p + c (correct).
      let tr = CGAffineTransform(translationX: center.x, y: center.y)
        .concatenating(CGAffineTransform(rotationAngle: angle))
      nail.apply(tr)
      path.append(nail)
      drawnCount += 1

      // Shape-aware cuticle shadow + highlight (kept inside the nail region).
      let csWmul: CGFloat = (currentNailShape == 3) ? 0.62 : (currentNailShape == 1 ? 0.68 : (currentNailShape == 2 ? 0.76 : 0.72))
      let csW = drawWid * csWmul
      let csH = drawLen * 0.12
      let cs  = UIBezierPath(ovalIn: CGRect(x: -csW / 2,
                                             y: drawLen / 2 - csH,
                                             width: csW, height: csH))
      cs.apply(tr)
      cuticlePath.append(cs)

      let hWmul: CGFloat = (currentNailShape == 3) ? 0.22 : (currentNailShape == 1 ? 0.24 : (currentNailShape == 2 ? 0.30 : 0.28))
      let hW = drawWid * hWmul
      let hH = drawLen * 0.55
      let hX = -hW / 2
      let hY = yTop + drawLen * 0.05
      let h  = UIBezierPath(ovalIn: CGRect(x: hX, y: hY, width: hW, height: hH))
      h.apply(tr)
      highlightPath.append(h)

      // This finger rendered successfully; clear temporary miss hold.
      nailMissFrames[idx] = 0

      if idx == 2 { refWidth = drawWid }
    }

    // Guaranteed fallback: if advanced fit failed this frame, draw simple nails from TIP->DIP anchors.
    // This keeps color visible on fingers instead of disappearing.
    if drawnCount == 0 {
      for (idx, f) in fingers.enumerated() {
        guard let t = lp(f.tip), let d = lp(f.dip) else { continue }
        let seg = max(1.0, distPx(t, d))
        if seg < 2.0 { continue }
        let ax = (t.x - d.x) / seg
        let ay = (t.y - d.y) / seg
        let len = max(handWidth * 0.060, min(handWidth * 0.145, seg * 1.05))
        let wid = max(handWidth * 0.030, min(handWidth * 0.070, seg * (idx == 0 ? 0.55 : 0.48)))
        let center = CGPoint(
          x: t.x - ax * (len * 0.44),
          y: t.y - ay * (len * 0.44)
        )
        let angle = atan2(ay, ax) + .pi / 2.0
        let yTop = -len / 2.0
        let nail = UIBezierPath(ovalIn: CGRect(x: -wid / 2.0, y: yTop, width: wid, height: len))
        let tr = CGAffineTransform(translationX: center.x, y: center.y)
          .concatenating(CGAffineTransform(rotationAngle: angle))
        nail.apply(tr)
        path.append(nail)
        drawnCount += 1

        let cs = UIBezierPath(ovalIn: CGRect(x: -wid * 0.30, y: len * 0.38, width: wid * 0.60, height: len * 0.12))
        cs.apply(tr)
        cuticlePath.append(cs)

        let h = UIBezierPath(ovalIn: CGRect(x: -wid * 0.13, y: yTop + len * 0.06, width: wid * 0.26, height: len * 0.50))
        h.apply(tr)
        highlightPath.append(h)
      }
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    // ── Main nail polish colour ───────────────────────────────────────────────
    // Keep nails visually opaque so the natural nail does not bleed through.
    // Slider now controls "finish strength" rather than raw transparency.
    let polishAlpha = min(1.0, max(0.82, 0.82 + currentIntensity * 0.18))
    nailOverlayLayer.fillRule    = .nonZero
    nailOverlayLayer.fillColor   = currentShade.withAlphaComponent(polishAlpha).cgColor
    // Thin dark rim separates polish from skin — mimics the nail edge shadow.
    nailOverlayLayer.strokeColor = UIColor.black.withAlphaComponent(0.22).cgColor
    nailOverlayLayer.lineWidth   = max(0.55, refWidth * 0.030)
    nailOverlayLayer.path        = path.cgPath

    // ── Cuticle depth shadow ──────────────────────────────────────────────────
    nailCuticleLayer.fillColor = UIColor.black.withAlphaComponent(
      Double(currentIntensity) * 0.18).cgColor
    nailCuticleLayer.path      = cuticlePath.cgPath

    // ── Specular lacquer streak (screen blend) ────────────────────────────────
    nailHighlightLayer.fillColor = UIColor.white.withAlphaComponent(
      Double(currentIntensity) * 0.72).cgColor
    nailHighlightLayer.opacity   = Float(min(1, max(0, currentIntensity)))
    nailHighlightLayer.path      = highlightPath.cgPath

    CATransaction.commit()
    lastDrawnNailsCount = drawnCount
  }
  // ── Luminance-boosted HSL hair colour processor (1/4 resolution for speed) ─
  //
  // Processing the full mask (~920 k pixels) takes ~180 ms → mask lags 5-6
  // camera frames behind, making it drift onto the face when the phone moves.
  //
  // Solution: work at 1/4 resolution (~57 k pixels) → ~12 ms processing.
  // The hairMaskLayer scales the smaller image to fill the screen with bilinear
  // smoothing so quality is not noticeably reduced.
  //
  // Colour math: luminance-boosted HSL transfer (same as before) ensures dark
  // hair shows the target colour clearly.
  private func mpSmoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)
  }

  /// Pick the confidence map that behaves like "hair" (localized) vs "background" (often high almost everywhere).
  private func selectHairConfidenceMask(from masks: [Mask]) -> Mask {
    guard masks.count > 1 else { return masks[0] }
    func globalHighFraction(_ m: Mask) -> Float {
      let w = m.width, h = m.height
      let fp = m.float32Data
      guard w > 0, h > 0 else { return 1 }
      var hi = 0, tot = 0
      let step = max(1, min(w, h) / 80)
      for y in Swift.stride(from: 0, to: h, by: step) {
        for x in Swift.stride(from: 0, to: w, by: step) {
          tot += 1
          if fp[y * w + x] > 0.4 { hi += 1 }
        }
      }
      return Float(hi) / Float(max(1, tot))
    }
    func meanTopBand(_ m: Mask) -> Float {
      let w = m.width, h = m.height
      let fp = m.float32Data
      guard w > 0, h > 0 else { return 0 }
      let yMax = max(1, h / 8)
      var sum: Float = 0
      var n = 0
      let step = max(1, min(w, h) / 96)
      for y in Swift.stride(from: 0, to: yMax, by: step) {
        for x in Swift.stride(from: 0, to: w, by: step) {
          sum += fp[y * w + x]
          n += 1
        }
      }
      return n > 0 ? sum / Float(n) : 0
    }
    let m0 = masks[0], m1 = masks[1]
    let g0 = globalHighFraction(m0), g1 = globalHighFraction(m1)
    if abs(g0 - g1) > 0.08 {
      return g0 <= g1 ? m0 : m1
    }
    let t0 = meanTopBand(m0), t1 = meanTopBand(m1)
    return t0 >= t1 ? m0 : m1
  }

  private func processHairMask(_ result: ImageSegmenterResult,
                                pixelBuffer: CVPixelBuffer,
                                shade: UIColor,
                                styleShape: String? = nil,
                                liveColourTemporalBlend: Bool = true,
                                liveColourAlphaTemporalSmooth: Bool = false,
                                processingScale: Int = 4) -> CGImage? {
    guard let maskList = result.confidenceMasks, !maskList.isEmpty else { return nil }

    let hairMask = selectHairConfidenceMask(from: maskList)
    let maskW = hairMask.width
    let maskH = hairMask.height
    guard maskW > 0 && maskH > 0 else { return nil }

    let hairPixels = hairMask.float32Data

    var tR: CGFloat = 0, tG: CGFloat = 0, tB: CGFloat = 0, tA: CGFloat = 0
    shade.resolvedColor(with: UITraitCollection.current)
         .getRed(&tR, green: &tG, blue: &tB, alpha: &tA)
    let (tgtH0, tgtS0, tgtL0) = rgbToHSL(Float(tR), Float(tG), Float(tB))

    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    let bufW        = CVPixelBufferGetWidth(pixelBuffer)
    let bufH        = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    guard let base  = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
    let cam         = base.assumingMemoryBound(to: UInt8.self)

    let scale  = max(2, min(10, processingScale))
    let procW  = max(1, maskW / scale)
    let procH  = max(1, maskH / scale)
    let count  = procW * procH
    var rgba   = [UInt8](repeating: 0, count: count * 4)

    let shape = styleShape?.lowercased() ?? ""
    let isStyle = !shape.isEmpty

    for i in 0..<count {
      let px = i % procW
      let py = i / procW

      let mx   = min(maskW - 1, px * scale)
      let my   = min(maskH - 1, py * scale)
      // 3×3 box average on confidence reduces blocky mask noise when downsampled (scale=4).
      var conf: Float = 0
      for dy in -1...1 {
        for dx in -1...1 {
          let sx = min(maskW - 1, max(0, mx + dx))
          let sy = min(maskH - 1, max(0, my + dy))
          conf += hairPixels[sy * maskW + sx]
        }
      }
      conf *= (1.0 / 9.0)

      // Live: higher `lo` + brow guard below → tighter hair vs skin accuracy; style unchanged.
      let lo = isStyle ? Float(0.20) : Float(0.30)
      let hi = isStyle ? Float(0.52) : Float(0.60)
      if conf <= lo {
        conf = 0
      } else if conf >= hi {
        conf = 1
      } else {
        let t = (conf - lo) / (hi - lo)
        conf = t * t * (3.0 - 2.0 * t)
      }

      // Live: soften uncertain model mass in a typical **forehead / brow / glasses-line** band (reduces skin bleed).
      let vForGeom = Float(py) / Float(max(1, procH))
      if !isStyle {
        let browBand = mpSmoothstep(0.17, 0.33, vForGeom) * (1 - mpSmoothstep(0.37, 0.57, vForGeom))
        let unc = 1 - conf
        conf *= max(0, 1 - 0.55 * browBand * unc * unc)
      }

      let u = Float(px) / Float(max(1, procW))
      let v = vForGeom

      var lenMul: Float = 1
      if isStyle {
        switch shape {
        case "pixie", "textured_pixie":
          lenMul = mpSmoothstep(0.58, 0.22, v)
        case "buzz", "buzz_cut":
          lenMul = mpSmoothstep(0.52, 0.18, v)
        case "bob", "blunt_bob", "french_bob":
          lenMul = mpSmoothstep(0.68, 0.36, v)
        case "bangs", "curtain_bangs":
          lenMul = mpSmoothstep(0.65, 0.35, v)
        case "bun", "slick_bun", "braid", "braid_crown":
          lenMul = mpSmoothstep(0.48, 0.15, v) * 0.92 + 0.08
        default:
          lenMul = 1
        }
      }

      let alpha = UInt8(min(255, conf * 255 * lenMul))
      guard alpha > 0 else { continue }

      // Cell-centre UV → bilinear sample: keeps strand highlights/shadows (nearest-neighbour looked flat/blocky).
      let uBuf = (Float(px) + 0.5) / Float(max(1, procW))
      let vBuf = (Float(py) + 0.5) / Float(max(1, procH))
      let (srcR, srcG, srcB) = sampleBGRABilinear(cam, bytesPerRow: bytesPerRow, bufW: bufW, bufH: bufH, u: uBuf, v: vBuf)

      let (_, srcS, srcL) = rgbToHSL(srcR, srcG, srcB)

      var effH = tgtH0
      var effS = tgtS0
      var resultL: Float = 0.0
      
      if shape == "shadow" {
        rgba[i*4 + 0] = UInt8(min(255, srcR * 0.20 * 255))
        rgba[i*4 + 1] = UInt8(min(255, srcG * 0.20 * 255))
        rgba[i*4 + 2] = UInt8(min(255, srcB * 0.20 * 255))
        rgba[i*4 + 3] = alpha
        continue
      }

      if isStyle {
        // Wig / style path: stronger lift + art-directed shapes.
        let lumFloor: Float = 0.62
        let baseL = max(srcL, tgtL0 * lumFloor)
        resultL = min(1, baseL * 0.78 + srcL * 0.22)
        let accentBoost: Float = 0.20
        effS = min(1, srcS * (1 - accentBoost) + effS * accentBoost)

        switch shape {
        case "waves", "beachy_waves", "layer_lob", "side_swept":
          let wave = sin(u * .pi * 10.0 + Float(py) * 0.065) * 0.07
          resultL = min(1, resultL + wave)
          effS = min(1, effS * 1.06)
        case "curly", "big_curls":
          let c = sin(u * .pi * 14.0) * sin(v * .pi * 9.0) * 0.11
          resultL = min(1, resultL + c)
          effS = min(1, effS * 1.14)
        case "sleek_straight", "straight":
          effS = min(1, effS * 0.94)
        case "wolf", "wolf_cut", "shaggy_mullet":
          effS = min(1, effS * 1.1)
          resultL = max(0, resultL - (1 - v) * 0.06)
        case "braid", "braid_crown", "bun", "slick_bun":
          resultL = min(1, resultL + (1 - v) * 0.05)
        default:
          resultL = min(1, resultL + v * 0.04)
        }
      } else {
        // Live hair colour: keep camera **luminance texture** while shifting chroma toward the shade.
        let k = Float(alpha) / 255.0
        effH = tgtH0
        // Slightly less aggressive saturation than before → less “neon poster” on dark / curly hair.
        effS = min(1, tgtS0 * (0.30 + 0.40 * k) + srcS * (0.70 - 0.28 * k))
        effS *= (0.88 + 0.10 * k)
        let liftBand = max(srcL, min(1, tgtL0 * (0.36 + 0.26 * srcL)))
        resultL = min(1, srcL * (0.72 - 0.24 * k) + liftBand * (0.28 + 0.20 * k))
        resultL = min(1, resultL + v * 0.014)
      }

      let (outR, outG, outB) = hslToRGB(effH, effS, resultL)

      // Live only: blend tint back toward the **camera** at uncertain edges and in specular highlights
      // so the result follows real lighting and doesn’t read as a flat red sheet.
      var fr = outR, fg = outG, fb = outB
      if !isStyle {
        let k = Float(alpha) / 255.0
        let edgeW = (1 - k) * 0.40
        let hiW = mpSmoothstep(0.48, 0.82, srcL) * (0.34 + 0.14 * k)
        // Low chroma (skin / grey hair) → trust camera more so colour doesn’t “stick” to cheeks or frames.
        let lowSat = max(0, 1 - min(1, srcS / 0.17))
        let w = min(0.72, edgeW + hiW + lowSat * 0.30 * (0.35 + 0.65 * (1 - k)))
        fr = outR * (1 - w) + srcR * w
        fg = outG * (1 - w) + srcG * w
        fb = outB * (1 - w) + srcB * w
      }

      let aN = Float(alpha) / 255.0
      rgba[i*4 + 0] = UInt8(min(255, fr * aN * 255))
      rgba[i*4 + 1] = UInt8(min(255, fg * aN * 255))
      rgba[i*4 + 2] = UInt8(min(255, fb * aN * 255))
      rgba[i*4 + 3] = alpha
    }

    // Live hair-colour: optional full EMA (wig path) or alpha-only EMA (live: less edge blink, no RGB lag).
    if !isStyle, liveColourTemporalBlend {
      let n = rgba.count
      if let prev = lastHairMaskRgba, prev.count == n {
        let nw: Float = 0.86
        let ow: Float = 1.0 - nw
        for j in 0..<n {
          let blended = Float(rgba[j]) * nw + Float(prev[j]) * ow
          rgba[j] = UInt8(min(255, max(0, Int(blended.rounded(.towardZero)))))
        }
      }
      lastHairMaskRgba = rgba
    } else if !isStyle, liveColourAlphaTemporalSmooth {
      let n = rgba.count
      if let prev = lastHairMaskRgba, prev.count == n {
        // Stronger temporal filter on **alpha** (edge stability); light filter on premul RGB (avoids premul/alpha mismatch flicker).
        let nwA: Float = 0.70
        let owA: Float = 1.0 - nwA
        let nwC: Float = 0.93
        let owC: Float = 1.0 - nwC
        for base in Swift.stride(from: 0, to: n, by: 4) {
          for c in 0..<3 {
            let blended = Float(rgba[base + c]) * nwC + Float(prev[base + c]) * owC
            rgba[base + c] = UInt8(min(255, max(0, Int(blended.rounded(.towardZero)))))
          }
          let j = base + 3
          let blendedA = Float(rgba[j]) * nwA + Float(prev[j]) * owA
          rgba[j] = UInt8(min(255, max(0, Int(blendedA.rounded(.towardZero)))))
        }
      }
      lastHairMaskRgba = rgba
    } else {
      lastHairMaskRgba = nil
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let provider   = CGDataProvider(data: Data(rgba) as CFData)
    return CGImage(
      width: procW, height: procH,
      bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: procW * 4,
      space: colorSpace,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }

  // ── HSL helpers removed from here ─────────────────────────────────────────────


  private func drawLips(_ result: FaceLandmarkerResult) {
    guard let landmarks = result.faceLandmarks.first else {
        lipOverlayLayer.opacity = 0
        for sl in makeupSlotLayers {
            sl.opacity = 0
            sl.path = nil
        }
        hairSideLayer.opacity   = 0
        hairImageLayer.opacity  = 0
        return
    }

    lipOverlayLayer.lineJoin = .miter
    lipOverlayLayer.lineCap = .butt
    lipOverlayLayer.compositingFilter = nil

    func point(for index: Int) -> CGPoint {
        let lm = landmarks[index]
        return landmarkNormToView(nx: CGFloat(lm.x), ny: CGFloat(lm.y))
    }

    func addPolygon(indices: [Int], to path: UIBezierPath, close: Bool = true) {
        if indices.isEmpty { return }
        path.move(to: point(for: indices[0]))
        for i in 1..<indices.count {
            path.addLine(to: point(for: indices[i]))
        }
        if close { path.close() }
    }

    /// Softens cheekbone polys (blush / highlighter) so mesh vertices don’t read as straight “cuts”.
    func addSmoothedCheekPolygon(indices: [Int], to path: UIBezierPath) {
        guard indices.count >= 4 else {
            addPolygon(indices: indices, to: path, close: true)
            return
        }
        var pts = indices.map { point(for: $0) }
        let n = pts.count
        let dupClose = indices.first == indices.last
        guard n > 3 else {
            addPolygon(indices: indices, to: path, close: true)
            return
        }
        for _ in 0..<7 {
            if dupClose { pts[n - 1] = pts[0] }
            let snap = pts
            for i in 1...(n - 2) {
                pts[i] = CGPoint(
                    x: snap[i].x * 0.42 + (snap[i - 1].x + snap[i + 1].x) * 0.29,
                    y: snap[i].y * 0.42 + (snap[i - 1].y + snap[i + 1].y) * 0.29
                )
            }
            if dupClose { pts[n - 1] = pts[0] }
        }
        path.move(to: pts[0])
        for i in 1..<n {
            path.addLine(to: pts[i])
        }
        path.close()
    }

    /// Filled strip along an open polyline (e.g. nose bridge) so highlight isn’t a razor-thin stroke.
    func addRibbonAlongPolyline(indices: [Int], halfWidth: CGFloat, to p: UIBezierPath) {
        guard indices.count >= 2, halfWidth > 0.5 else { return }
        let pts = indices.map { point(for: $0) }
        let n = pts.count
        var left = [CGPoint](repeating: .zero, count: n)
        var right = [CGPoint](repeating: .zero, count: n)
        for i in 0..<n {
            let prev = pts[max(0, i - 1)]
            let next = pts[min(n - 1, i + 1)]
            var dx = next.x - prev.x
            var dy = next.y - prev.y
            let len = max(0.001, hypot(dx, dy))
            dx /= len
            dy /= len
            let ox = -dy * halfWidth
            let oy = dx * halfWidth
            left[i] = CGPoint(x: pts[i].x + ox, y: pts[i].y + oy)
            right[i] = CGPoint(x: pts[i].x - ox, y: pts[i].y - oy)
        }
        p.move(to: left[0])
        for i in 1..<n { p.addLine(to: left[i]) }
        for i in (0..<n).reversed() { p.addLine(to: right[i]) }
        p.close()
    }

    let fillMakeupPathForCurrentCategory: (UIBezierPath) -> Bool = { [self] path in
    lipOverlayLayer.shadowOpacity = 0
    lipOverlayLayer.shadowRadius = 0
    lipOverlayLayer.lineWidth = 0
    lipOverlayLayer.strokeColor = UIColor.clear.cgColor
    lipOverlayLayer.fillColor = self.currentShade.withAlphaComponent(self.currentIntensity).cgColor
    
    // ── STRICT EXPLICIT CATEGORY ROUTING ──
    let category = currentCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let isLipLiner = category == "cmd_lipliner"
    let isBlush = category == "cmd_blush"
    let isFace = category == "cmd_face"
    let isHighlight = category == "cmd_highlight"
    let isConcealer = category == "cmd_concealer"
    let isShadow = category == "cmd_eyeshadow"
    let isMascara = category == "cmd_mascara"
    let isEyeliner = category == "cmd_eyeliner"
    let isEyebrow = category == "cmd_eyebrow"
    let isHairColor = category == "cmd_haircolor"
    let isHairStyle = category == "cmd_hairstyle"
    
    // Fallback for generic "Eye Makeup" that lacks the specific keywords
    let isGenericEye = category == "cmd_eye"

    if isHairStyle {
        lipOverlayLayer.opacity = 0
        
        if self.hairImageLayer.contents != nil {
            self.hairImageLayer.opacity = 1.0
            // Subtly blend the shadow mask to avoid the 'dark halo' outside the wig
            self.hairMaskLayer.opacity = 0.4
            
            // ── STABLE EYE ANCHORING ─────────────────────────────────────────
            // Eyes are the most reliably detected features.
            let leftEye  = point(for: 33)
            let rightEye = point(for: 263)
            let eyeMid   = CGPoint(x: (leftEye.x + rightEye.x) / 2.0, 
                                   y: (leftEye.y + rightEye.y) / 2.0)
            
            // ── SCALING ──────────────────────────────────────────────────────
            // 3.8x颊骨宽度 ensures the face-hole in our assets fits accurately.
            let cheekL = point(for: 234)
            let cheekR = point(for: 454)
            let faceWidthPx = hypot(cheekR.x - cheekL.x, cheekR.y - cheekL.y)
            let wigWidth    = faceWidthPx * 3.8
            let wigHeight   = wigWidth // Square assets
            
            let angle = atan2(cheekR.y - cheekL.y, cheekR.x - cheekL.x) // Roll
            
            // ── TEMPORAL SMOOTHING ──────────────────────────────────────────
            let f = self.smoothingFactor
            let targetPos = eyeMid
            let currentPos = lastWigPosition != nil ? 
                CGPoint(x: lastWigPosition!.x * (1 - f) + targetPos.x * f, 
                        y: lastWigPosition!.y * (1 - f) + targetPos.y * f) : targetPos
            
            let targetBounds = CGRect(x: 0, y: 0, width: wigWidth, height: wigHeight)
            let currentBounds = lastWigBounds != nil ?
                CGRect(x: 0, y: 0, 
                       width: lastWigBounds!.width * (1 - f) + targetBounds.width * f, 
                       height: lastWigBounds!.height * (1 - f) + targetBounds.height * f) : targetBounds
            
            self.lastWigPosition = currentPos
            self.lastWigBounds   = currentBounds
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // anchorPoint = (0.5, 0.35) aligns our wig's internal EYE LEVEL 
            // exactly with your actual detected EYE CENTER.
            self.hairImageLayer.anchorPoint = CGPoint(x: 0.5, y: 0.35)
            self.hairImageLayer.bounds   = currentBounds
            self.hairImageLayer.position = currentPos
            self.hairImageLayer.setAffineTransform(CGAffineTransform(rotationAngle: angle))
            CATransaction.commit()
            
        } else {
            self.hairImageLayer.opacity = 0
            if self.hairMaskLayer.contents == nil {
                self.hairMaskLayer.opacity  = 0
            }
            self.lastWigPosition = nil
            self.lastWigBounds = nil

        }
        return true
    } else {
        self.hairImageLayer.opacity = 0
    }

    if isHairColor {
        // Hair is now handled by ImageSegmenter in applyHairMask.
        // drawLips is never called for cmd_haircolor, but guard here just in case.
        lipOverlayLayer.opacity = 0
        return true
    } else if isBlush {
        // Blush: Angled upwards along the cheekbones (zygomatic bone)
        let leftCheek = [116, 117, 118, 100, 101, 119, 120, 121, 147, 213, 192, 214, 207, 205, 116]
        let rightCheek = [345, 346, 347, 329, 330, 348, 349, 350, 376, 433, 416, 434, 427, 425, 345]

        lipOverlayLayer.fillRule = .nonZero
        // colorBlendMode: keeps each cheek’s *camera* brightness (avoids soft-light “shiny vs flat”
        // asymmetry when one side catches more light). Hue/sat come from the blush shade.
        lipOverlayLayer.compositingFilter = "colorBlendMode"
        addSmoothedCheekPolygon(indices: leftCheek, to: path)
        addSmoothedCheekPolygon(indices: rightCheek, to: path)
        
        let blushT = pow(max(0.0, min(1.0, self.currentIntensity)), 0.52)
        lipOverlayLayer.fillColor = self.currentShade.withAlphaComponent(max(0.08, 0.30 * blushT)).cgColor
        lipOverlayLayer.strokeColor = UIColor.clear.cgColor
        lipOverlayLayer.lineWidth = 0
        // Neutral shadow only feathers the silhouette — coloured shadow + blend read as “wet” sheen.
        lipOverlayLayer.shadowColor = UIColor.black.cgColor
        lipOverlayLayer.shadowOpacity = Float(0.14 + 0.18 * Float(blushT))
        lipOverlayLayer.shadowRadius = 44.0
        lipOverlayLayer.shadowOffset = .zero

    } else if isHighlight {
        // Cheeks: smoothed fills. Nose: filled ribbon (not 1px stroke — avoids “laser line”). Cupid: smoothed loop.
        let leftHighlight = [116, 117, 118, 100, 101, 119, 120, 121, 147, 116]
        let rightHighlight = [345, 346, 347, 329, 330, 348, 349, 350, 376, 345]
        let noseBridge = [168, 6, 197, 195, 5, 4, 1]
        let cupid = [0, 267, 269, 270, 409, 291, 0]

        lipOverlayLayer.fillRule = .nonZero
        // Soft light reads as diffuse sheen; screen + thin nose was too “stripe / wet” at typical intensities.
        lipOverlayLayer.compositingFilter = "softLightBlendMode"
        addSmoothedCheekPolygon(indices: leftHighlight, to: path)
        addSmoothedCheekPolygon(indices: rightHighlight, to: path)
        let eyeMidY = (point(for: 33).y + point(for: 263).y) * 0.5
        let chinY = point(for: 152).y
        let faceLen = max(abs(chinY - eyeMidY), 40)
        let noseHalfW = max(3.2, min(8.5, faceLen * 0.052))
        addRibbonAlongPolyline(indices: noseBridge, halfWidth: noseHalfW, to: path)
        addSmoothedCheekPolygon(indices: cupid, to: path)

        let hiT = pow(max(0.0, min(1.0, self.currentIntensity)), 0.48)
        lipOverlayLayer.fillColor = self.currentShade.withAlphaComponent(max(0.05, 0.13 * hiT)).cgColor
        lipOverlayLayer.strokeColor = UIColor.clear.cgColor
        lipOverlayLayer.lineWidth = 0
        lipOverlayLayer.lineJoin = .round
        lipOverlayLayer.lineCap = .round
        lipOverlayLayer.shadowColor = self.currentShade.cgColor
        lipOverlayLayer.shadowOpacity = Float(min(0.45, 0.22 + Float(hiT) * 0.28))
        lipOverlayLayer.shadowRadius = 38.0
        lipOverlayLayer.shadowOffset = .zero

    } else if isConcealer {
        // Concealer: under-eye triangles and sides of nose.
        let leftUnderEye = [33, 133, 155, 154, 153, 145, 144, 163, 7, 33]
        let rightUnderEye = [362, 263, 249, 390, 373, 374, 380, 381, 382, 362]
        let leftNoseSide = [48, 115, 131, 134, 220, 45, 48]
        let rightNoseSide = [278, 344, 360, 363, 440, 275, 278]

        addPolygon(indices: leftUnderEye, to: path)
        addPolygon(indices: rightUnderEye, to: path)
        addPolygon(indices: leftNoseSide, to: path)
        addPolygon(indices: rightNoseSide, to: path)

        // Under-eye + nose quads overlap; evenOdd fill subtracts overlaps → invisible patches.
        lipOverlayLayer.fillRule = .nonZero
        lipOverlayLayer.fillColor = self.currentShade.withAlphaComponent(max(0.18, min(0.42, self.currentIntensity * 0.55))).cgColor
        lipOverlayLayer.strokeColor = UIColor.clear.cgColor
        lipOverlayLayer.shadowColor = self.currentShade.cgColor
        lipOverlayLayer.shadowOpacity = Float(min(0.24, self.currentIntensity * 0.35))
        lipOverlayLayer.shadowRadius = 8.0
        lipOverlayLayer.shadowOffset = .zero

    } else if isFace || category.contains("foundation") || category.contains("concealer") {
        // Foundation: Face oval must follow MediaPipe perimeter on the forehead: …109→151→10→338…
        // A straight 151→338 closing chord sits *above* glabella (10) in the mesh, so the skin near
        // the hairline apex stays *outside* the polygon → a bare triangular “cap”. Keep 10 on the path.
        let faceOval = [338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109, 151, 10]
        let outerLips = [61, 185, 40, 39, 37, 0, 267, 269, 270, 409, 291, 375, 321, 405, 314, 17, 84, 181, 91, 146]
        let leftEye = [33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246]
        let rightEye = [362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398]

        // Crown + forehead row lifts. Glabella (21) must NOT be a local minimum vs 162/54/103 — we
        // had 21 weaker than neighbors, which dented the polygon upward and read as a forehead “V”.
        let eyeMidY = (point(for: 33).y + point(for: 263).y) * 0.5
        let chinY = point(for: 152).y
        let faceLen = max(abs(chinY - eyeMidY), 40)
        // Hairline: cap + scale + small fixed crown nudge (px) — last mile above mesh oval.
        let liftPx = min(30, max(8, faceLen * 0.095))
        let hairlineExtraPx: CGFloat = 4.5
        let hairlineCrownIds: Set<Int> = [10, 151, 109, 338, 297, 332, 284, 251]
        let liftWeight: [Int: CGFloat] = [
            151: 1.0, 109: 1.0, 338: 1.0, 10: 0.98,
            297: 0.60, 332: 0.60, 284: 0.42, 251: 0.42,
            389: 0.27, 356: 0.20, 454: 0.16, 323: 0.16, 361: 0.14, 288: 0.12, 397: 0.12, 365: 0.10,
            379: 0.07, 378: 0.07, 400: 0.06, 377: 0.06,
            67: 0.39, 103: 0.34, 54: 0.30, 21: 0.29, 162: 0.27, 127: 0.23, 234: 0.21, 93: 0.17, 132: 0.14,
            172: 0.10, 58: 0.085,
        ]
        func foundationPoint(for idx: Int) -> CGPoint {
            let p = point(for: idx)
            guard let w = liftWeight[idx], w > 0 else { return p }
            var y = p.y - liftPx * w
            if hairlineCrownIds.contains(idx) { y -= hairlineExtraPx }
            return CGPoint(x: p.x, y: y)
        }
        /// Laplacian-ish smoothing on two contour spans (crown + brow–temple row) to remove mesh
        /// zig-zag / “V” artifacts; jaw indices stay untouched. Tune `passes` or ranges if needed.
        func addFoundationFaceOvalSmoothed(_ indices: [Int], to p: UIBezierPath) {
            guard indices.count > 12 else { return }
            var pts = indices.map { foundationPoint(for: $0) }
            func smoothInterior(_ range: ClosedRange<Int>, passes: Int) {
                guard range.count >= 3 else { return }
                let lo = range.lowerBound
                let hi = range.upperBound
                for _ in 0..<passes {
                    let snap = pts
                    for i in (lo + 1)...(hi - 1) {
                        pts[i] = CGPoint(
                            x: snap[i].x * 0.46 + (snap[i - 1].x + snap[i + 1].x) * 0.27,
                            y: snap[i].y * 0.46 + (snap[i - 1].y + snap[i + 1].y) * 0.27
                        )
                    }
                }
            }
            let last = pts.count - 1
            smoothInterior(0...min(6, last), passes: 5)
            if last >= 36 { smoothInterior((last - 10)...last, passes: 5) }
            else if last >= 35 { smoothInterior((last - 9)...last, passes: 5) }
            p.move(to: pts[0])
            for i in 1...last { p.addLine(to: pts[i]) }
            p.close()
        }

        addFoundationFaceOvalSmoothed(faceOval, to: path)
        addPolygon(indices: outerLips, to: path)
        addPolygon(indices: leftEye, to: path)
        addPolygon(indices: rightEye, to: path)
        
        // Foundation needs to be visible enough to see the shade match clearly
        let alpha = max(0.20, min(0.65, self.currentIntensity * 0.7))
        lipOverlayLayer.fillColor = self.currentShade.withAlphaComponent(alpha).cgColor
        
        // Add a subtle glow/bloom for foundation to feel more "full face"
        lipOverlayLayer.shadowColor = self.currentShade.cgColor
        lipOverlayLayer.shadowOpacity = Float(alpha * 0.52)
        lipOverlayLayer.shadowRadius = 24.0
        lipOverlayLayer.shadowOffset = .zero
        
    } else if isShadow {
        // Build a real eyelid band by offsetting the upper lash contour upward.
        func addShadowBand(_ lidIndices: [Int], verticalBias: CGFloat) {
            guard lidIndices.count >= 3 else { return }
            let lid = lidIndices.map { point(for: $0) }

            let minX = lid.map(\.x).min() ?? 0
            let maxX = lid.map(\.x).max() ?? 0
            let eyeWidth = max(1.0, maxX - minX)
            let bandHeight = max(12.0, min(26.0, eyeWidth * 0.25))

            var upper: [CGPoint] = []
            upper.reserveCapacity(lid.count)

            for i in 0..<lid.count {
                let p = lid[i]
                let prev = lid[max(0, i - 1)]
                let next = lid[min(lid.count - 1, i + 1)]

                let dx = next.x - prev.x
                let dy = next.y - prev.y
                let len = max(0.001, sqrt(dx * dx + dy * dy))

                // Normal pointing upward on screen coordinates.
                var nx = -dy / len
                var ny = dx / len
                if ny > 0 { nx = -nx; ny = -ny }

                let t = CGFloat(i) / CGFloat(max(1, lid.count - 1))
                let centerBoost = 0.70 + (0.35 * (1.0 - abs((t * 2.0) - 1.0)))
                let off = bandHeight * centerBoost

                upper.append(CGPoint(
                    x: p.x + (nx * off),
                    y: p.y + (ny * off) + verticalBias
                ))
            }

            path.move(to: upper[0])
            for p in upper.dropFirst() { path.addLine(to: p) }
            for p in lid.reversed() { path.addLine(to: p) }
            path.close()
        }

        let leftUpperLid = [33, 246, 161, 160, 159, 158, 157, 173, 133]
        let rightUpperLid = [263, 466, 388, 387, 386, 385, 384, 398, 362]
        addShadowBand(leftUpperLid, verticalBias: -2.0)
        addShadowBand(rightUpperLid, verticalBias: -2.0)

        let fillAlpha = max(0.14, min(0.34, self.currentIntensity * 0.24))
        lipOverlayLayer.fillColor = self.currentShade.withAlphaComponent(fillAlpha).cgColor
        lipOverlayLayer.strokeColor = UIColor.clear.cgColor

        // Softer diffusion for a realistic matte/shimmer lid blend.
        lipOverlayLayer.shadowColor = self.currentShade.cgColor
        lipOverlayLayer.shadowOpacity = Float(min(0.28, self.currentIntensity * 0.42))
        lipOverlayLayer.shadowRadius = 8.0
        lipOverlayLayer.shadowOffset = .zero

    } else if isMascara {
        let leftUpperLash = [33, 246, 161, 160, 159, 158, 157, 173, 133]
        let rightUpperLash = [362, 398, 384, 385, 386, 387, 388, 466, 263]

        func addMascaraCoat(_ lashIndices: [Int], isLeftEye: Bool) {
            guard lashIndices.count >= 3 else { return }

            // Tight root line.
            addPolygon(indices: lashIndices, to: path, close: false)

            // Short coat strokes that follow natural lash direction.
            for i in 1..<(lashIndices.count - 1) {
                let base = point(for: lashIndices[i])
                let prev = point(for: lashIndices[i - 1])
                let next = point(for: lashIndices[i + 1])

                let dx = next.x - prev.x
                let dy = next.y - prev.y
                let len = max(0.001, sqrt(dx * dx + dy * dy))

                var nx = -dy / len
                var ny = dx / len
                if ny > 0 { nx = -nx; ny = -ny }

                let t = CGFloat(i) / CGFloat(max(1, lashIndices.count - 2))
                let centerFactor = 1.0 - abs((t * 2.0) - 1.0)
                let lashLength = 3.6 + (2.8 * centerFactor)
                let fan = (t - 0.5) * (isLeftEye ? -2.0 : 2.0)

                let control = CGPoint(
                    x: base.x + (nx * lashLength * 0.52) + fan,
                    y: base.y + (ny * lashLength * 0.52)
                )
                let tip = CGPoint(
                    x: base.x + (nx * lashLength) + (fan * 1.05),
                    y: base.y + (ny * lashLength)
                )

                path.move(to: base)
                path.addQuadCurve(to: tip, controlPoint: control)
            }
        }

        addMascaraCoat(leftUpperLash, isLeftEye: true)
        addMascaraCoat(rightUpperLash, isLeftEye: false)
        
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        let resolved = self.currentShade.resolvedColor(with: UITraitCollection.current)
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        let darkTintMix: CGFloat = 0.22
        let darkR = r * darkTintMix
        let darkG = g * darkTintMix
        let darkB = b * darkTintMix
        let mascaraColor = UIColor(
            red: darkR,
            green: darkG,
            blue: darkB,
            alpha: max(0.45, self.currentIntensity * 0.92)
        )

        lipOverlayLayer.fillColor = UIColor.clear.cgColor
        lipOverlayLayer.strokeColor = mascaraColor.cgColor
        lipOverlayLayer.lineWidth = max(0.70, min(1.10, 0.80 + (self.currentIntensity * 0.20)))
        lipOverlayLayer.shadowColor = UIColor.black.cgColor
        lipOverlayLayer.shadowOpacity = Float(min(0.16, self.currentIntensity * 0.16))
        lipOverlayLayer.shadowRadius = 0.8
        lipOverlayLayer.shadowOffset = .zero
        lipOverlayLayer.lineJoin = .round
        lipOverlayLayer.lineCap = .round

    } else if isEyebrow {
        // Brow tint: soft, natural fill inside brow body.
        let leftBrowUpper = [70, 63, 105, 66, 107, 55]
        let leftBrowLower = [46, 53, 52, 65, 55]
        let rightBrowUpper = [300, 293, 334, 296, 336, 285]
        let rightBrowLower = [276, 283, 282, 295, 285]

        addPolygon(indices: leftBrowUpper + Array(leftBrowLower.reversed()), to: path)
        addPolygon(indices: rightBrowUpper + Array(rightBrowLower.reversed()), to: path)

        let browFill = self.currentShade.withAlphaComponent(max(0.16, min(0.38, self.currentIntensity * 0.30)))
        lipOverlayLayer.fillColor = browFill.cgColor
        lipOverlayLayer.strokeColor = UIColor.clear.cgColor
        lipOverlayLayer.lineWidth = 0
        lipOverlayLayer.shadowColor = UIColor.black.cgColor
        lipOverlayLayer.shadowOpacity = Float(min(0.12, self.currentIntensity * 0.14))
        lipOverlayLayer.shadowRadius = 1.0
        lipOverlayLayer.shadowOffset = .zero

    } else if isEyeliner || isGenericEye {
        // Eyeliner: Sharp, precise stroke directly on the lash lines
        let leftEyeTop = [33, 246, 161, 160, 159, 158, 157, 173, 133]
        let leftEyeBottom = [33, 7, 163, 144, 145, 153, 154, 155, 133]
        let rightEyeTop = [362, 398, 384, 385, 386, 387, 388, 466, 263]
        let rightEyeBottom = [362, 382, 381, 380, 374, 373, 390, 249, 263]

        addPolygon(indices: leftEyeTop, to: path, close: false)
        addPolygon(indices: leftEyeBottom, to: path, close: false)
        addPolygon(indices: rightEyeTop, to: path, close: false)
        addPolygon(indices: rightEyeBottom, to: path, close: false)

        lipOverlayLayer.fillColor = UIColor.clear.cgColor
        lipOverlayLayer.strokeColor = self.currentShade.withAlphaComponent(self.currentIntensity).cgColor
        lipOverlayLayer.lineWidth = 2.5 // Sharp thin line
        lipOverlayLayer.shadowOpacity = 0

    } else if isLipLiner {
        // Lip Liner: Trace the outer border of the lips without filling
        let outerIndices = [61, 185, 40, 39, 37, 0, 267, 269, 270, 409, 291, 375, 321, 405, 314, 17, 84, 181, 91, 146]
        addPolygon(indices: outerIndices, to: path)
        
        lipOverlayLayer.fillColor = UIColor.clear.cgColor
        lipOverlayLayer.strokeColor = self.currentShade.withAlphaComponent(self.currentIntensity).cgColor
        lipOverlayLayer.lineWidth = 3.5
        
    } else {
        // Default / Lipstick: Outer lips with inner lips punched out
        let outerIndices = [61, 185, 40, 39, 37, 0, 267, 269, 270, 409, 291, 375, 321, 405, 314, 17, 84, 181, 91, 146]
        let innerIndices = [78, 191, 80, 81, 82, 13, 312, 311, 310, 415, 308, 324, 318, 402, 317, 14, 87, 178, 88, 95]
        
        addPolygon(indices: outerIndices, to: path)
        addPolygon(indices: innerIndices, to: path)
    }

    // Concealer / blush / highlight use nonZero in-branch; lipstick + foundation use evenOdd (holes).
    if category != "cmd_concealer" && category != "cmd_blush" && category != "cmd_highlight" {
        lipOverlayLayer.fillRule = .evenOdd
    }
    lipOverlayLayer.path = path.cgPath
    return false
    }

    if usesMakeupLookStack && makeupLookStack.isEmpty {
        lipOverlayLayer.opacity = 0
        lipOverlayLayer.path = nil
        lipOverlayLayer.mask = nil
        makeupStackParent.mask = nil
        for sl in makeupSlotLayers {
            sl.opacity = 0
            sl.path = nil
        }
        return
    }

    if usesMakeupLookStack && !makeupLookStack.isEmpty {
        lipOverlayLayer.opacity = 0
        lipOverlayLayer.path = nil
        lipOverlayLayer.mask = nil
        makeupStackParent.mask = nil
        layoutMakeupSlotLayersForStack()
        let compareMaskPath: CGPath? = {
            guard isCompareMode else { return nil }
            let splitX = container.bounds.width * currentSplitPosition
            let maskRect = CGRect(x: splitX, y: 0, width: container.bounds.width - splitX, height: container.bounds.height)
            return UIBezierPath(rect: maskRect).cgPath
        }()
        for i in 0..<makeupSlotLayers.count {
            if i < makeupLookStack.count {
                let e = makeupLookStack[i]
                self.currentShade = e.shade
                self.currentIntensity = e.intensity
                self.currentCategory = e.category
                let slotPath = UIBezierPath()
                if fillMakeupPathForCurrentCategory(slotPath) {
                    makeupSlotLayers[i].opacity = 0
                    makeupSlotLayers[i].path = nil
                    makeupSlotLayers[i].mask = nil
                    makeupSlotLayers[i].compositingFilter = nil
                    continue
                }
                self.copyFacePaint(from: lipOverlayLayer, to: makeupSlotLayers[i])
                makeupSlotLayers[i].opacity = 1
                if let compareMaskPath {
                    let slotMask = CAShapeLayer()
                    slotMask.path = compareMaskPath
                    makeupSlotLayers[i].mask = slotMask
                } else {
                    makeupSlotLayers[i].mask = nil
                }
            } else {
                makeupSlotLayers[i].opacity = 0
                makeupSlotLayers[i].path = nil
                makeupSlotLayers[i].mask = nil
                makeupSlotLayers[i].compositingFilter = nil
            }
        }
        let catHair = currentCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if catHair != "cmd_haircolor" { hairSideLayer.opacity = 0 }
        return
    }

    for sl in makeupSlotLayers {
        sl.opacity = 0
        sl.path = nil
    }
    makeupStackParent.mask = nil

    if isCompareMode {
        let mask = CAShapeLayer()
        let splitX = container.bounds.width * currentSplitPosition
        let maskRect = CGRect(x: splitX, y: 0, width: container.bounds.width - splitX, height: container.bounds.height)
        mask.path = UIBezierPath(rect: maskRect).cgPath
        lipOverlayLayer.mask = mask
    } else {
        lipOverlayLayer.mask = nil
    }

    let path = UIBezierPath()
    if fillMakeupPathForCurrentCategory(path) {
        return
    }
    lipOverlayLayer.opacity = 1.0

    let catLowerHair = currentCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if catLowerHair != "cmd_haircolor" { hairSideLayer.opacity = 0 }

    // ── Apply Split Masking (ONLY in compare mode) ─────────────────────
    if isCompareMode && currentSplitPosition < 0.99 {
        let maskBox = CGRect(
            x: container.bounds.width * currentSplitPosition,
            y: 0,
            width: container.bounds.width * (1.0 - currentSplitPosition),
            height: container.bounds.height
        )
        let maskLayer = CAShapeLayer()
        maskLayer.path = UIBezierPath(rect: maskBox).cgPath
        lipOverlayLayer.mask = maskLayer
    } else {
        lipOverlayLayer.mask = nil
    }
  }

  private func copyFacePaint(from src: CAShapeLayer, to dst: CAShapeLayer) {
    dst.path = src.path
    dst.fillRule = src.fillRule
    dst.fillColor = src.fillColor
    dst.strokeColor = src.strokeColor
    dst.lineWidth = src.lineWidth
    dst.lineJoin = src.lineJoin
    dst.lineCap = src.lineCap
    dst.compositingFilter = src.compositingFilter
    dst.shadowColor = src.shadowColor
    dst.shadowOpacity = src.shadowOpacity
    dst.shadowRadius = src.shadowRadius
    dst.shadowOffset = src.shadowOffset
  }

  /// Full-makeup `setLook` slots must sit directly above the camera preview (siblings), not only
  /// inside `makeupStackParent`. Otherwise blush `colorBlendMode` blends with foundation layers
  /// instead of live pixels — same quality as single-product `setEffect` on `lipOverlayLayer`.
  private func layoutMakeupSlotLayersForStack() {
    let size = container.bounds.size
    guard size.width > 1, size.height > 1 else { return }
    let frame = CGRect(origin: .zero, size: size)
    let subs = container.layer.sublayers
    for (i, sl) in makeupSlotLayers.enumerated() {
      var misplaced = sl.superlayer != container.layer
      if !misplaced, let preview = previewLayer, let subs,
         let pi = subs.firstIndex(of: preview), let si = subs.firstIndex(of: sl) {
        misplaced = si <= pi
      }
      if misplaced {
        sl.removeFromSuperlayer()
        if let preview = previewLayer {
          container.layer.insertSublayer(sl, above: preview)
        } else {
          container.layer.insertSublayer(sl, below: lipOverlayLayer)
        }
      }
      sl.frame = frame
      sl.zPosition = 40 + CGFloat(i)
    }
    lipOverlayLayer.zPosition = 120
  }

  /// Normalize EXIF orientation so selfie landmarks/rendering align to actual pixels.
  private func normalizedUIImage(_ image: UIImage) -> UIImage {
    if image.imageOrientation == .up { return image }
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = image.scale
    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
    return renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: image.size))
    }
  }

  /// Try-on does not need full camera resolution; large bitmaps + many layers → EXC_RESOURCE.
  private func downscaleForPhotoTryOn(_ image: UIImage, maxEdge: CGFloat = 1280) -> UIImage {
    let w = image.size.width
    let h = image.size.height
    let m = max(w, h)
    guard m > maxEdge else { return image }
    let s = maxEdge / m
    let nw = max(1, floor(w * s))
    let nh = max(1, floor(h * s))
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: nw, height: nh), format: format)
    return renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: CGSize(width: nw, height: nh)))
    }
  }

  private func renderMakeupOnPhoto(baseImage: UIImage, result: FaceLandmarkerResult) -> Data? {
    guard let landmarks = result.faceLandmarks.first else { return nil }
    let size = baseImage.size
    let w = size.width
    let h = size.height
    if w < 2 || h < 2 { return nil }

    struct Paint {
      var fill: UIColor = .clear
      var stroke: UIColor = .clear
      var lineWidth: CGFloat = 0
      var fillRule: CGPathFillRule = .evenOdd
      var blend: CGBlendMode = .normal
      var shadowColor: UIColor? = nil
      var shadowOpacity: CGFloat = 0
      var shadowRadius: CGFloat = 0
      var shadowOffset: CGSize = .zero
    }

    func point(_ idx: Int) -> CGPoint {
      let lm = landmarks[idx]
      return CGPoint(x: CGFloat(lm.x) * w, y: CGFloat(lm.y) * h)
    }

    func addPolygon(_ indices: [Int], to p: UIBezierPath, close: Bool = true) {
      guard let first = indices.first else { return }
      p.move(to: point(first))
      for i in indices.dropFirst() { p.addLine(to: point(i)) }
      if close { p.close() }
    }

    func addSmoothedCheekPolygon(_ indices: [Int], to p: UIBezierPath) {
      guard indices.count >= 4 else { addPolygon(indices, to: p, close: true); return }
      var pts = indices.map { point($0) }
      let n = pts.count
      let dupClose = indices.first == indices.last
      for _ in 0..<7 {
        if dupClose { pts[n - 1] = pts[0] }
        let snap = pts
        for i in 1...(n - 2) {
          pts[i] = CGPoint(
            x: snap[i].x * 0.42 + (snap[i - 1].x + snap[i + 1].x) * 0.29,
            y: snap[i].y * 0.42 + (snap[i - 1].y + snap[i + 1].y) * 0.29
          )
        }
        if dupClose { pts[n - 1] = pts[0] }
      }
      p.move(to: pts[0])
      for i in 1..<n { p.addLine(to: pts[i]) }
      p.close()
    }

    func addRibbonAlongPolyline(_ indices: [Int], halfWidth: CGFloat, to p: UIBezierPath) {
      guard indices.count >= 2, halfWidth > 0.5 else { return }
      let pts = indices.map { point($0) }
      let n = pts.count
      var left = [CGPoint](repeating: .zero, count: n)
      var right = [CGPoint](repeating: .zero, count: n)
      for i in 0..<n {
        let prev = pts[max(0, i - 1)]
        let next = pts[min(n - 1, i + 1)]
        var dx = next.x - prev.x
        var dy = next.y - prev.y
        let len = max(0.001, hypot(dx, dy))
        dx /= len; dy /= len
        let ox = -dy * halfWidth
        let oy = dx * halfWidth
        left[i] = CGPoint(x: pts[i].x + ox, y: pts[i].y + oy)
        right[i] = CGPoint(x: pts[i].x - ox, y: pts[i].y - oy)
      }
      p.move(to: left[0])
      for i in 1..<n { p.addLine(to: left[i]) }
      for i in (0..<n).reversed() { p.addLine(to: right[i]) }
      p.close()
    }

    func blendMode(for filter: String?) -> CGBlendMode {
      switch filter {
      case "softLightBlendMode": return .softLight
      case "screenBlendMode": return .screen
      case "colorBlendMode": return .color
      default: return .normal
      }
    }

    func buildLayer(category rawCat: String, shade: UIColor, intensity: CGFloat) -> (UIBezierPath, Paint)? {
      let cat = rawCat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if cat == "cmd_none" { return nil }

      let path = UIBezierPath()
      var paint = Paint()
      paint.fill = shade.withAlphaComponent(max(0.0, min(1.0, intensity)))
      paint.fillRule = .evenOdd
      paint.blend = .normal

      let isBlush = cat == "cmd_blush"
      let isFace = cat == "cmd_face" || cat == "cmd_foundation" || cat.contains("foundation")
      let isHighlight = cat == "cmd_highlight"
      let isShadow = cat == "cmd_eyeshadow"
      let isMascara = cat == "cmd_mascara"
      let isEyeliner = cat == "cmd_eyeliner" || cat == "cmd_eye"
      let isEyebrow = cat == "cmd_eyebrow"
      let isLipLiner = cat == "cmd_lipliner"
      let isLipstick = (!isBlush && !isFace && !isHighlight && !isShadow && !isMascara && !isEyeliner && !isEyebrow && !isLipLiner)

      if isBlush {
        let leftCheek = [116, 117, 118, 100, 101, 119, 120, 121, 147, 213, 192, 214, 207, 205, 116]
        let rightCheek = [345, 346, 347, 329, 330, 348, 349, 350, 376, 433, 416, 434, 427, 425, 345]
        paint.fillRule = .winding
        paint.blend = blendMode(for: "colorBlendMode")
        addSmoothedCheekPolygon(leftCheek, to: path)
        addSmoothedCheekPolygon(rightCheek, to: path)
        let t = pow(max(0.0, min(1.0, intensity)), 0.52)
        paint.fill = shade.withAlphaComponent(max(0.08, 0.30 * t))
        paint.shadowColor = UIColor.black
        paint.shadowOpacity = 0.14 + 0.18 * t
        paint.shadowRadius = 44
      } else if isHighlight {
        let leftHighlight = [116, 117, 118, 100, 101, 119, 120, 121, 147, 116]
        let rightHighlight = [345, 346, 347, 329, 330, 348, 349, 350, 376, 345]
        let noseBridge = [168, 6, 197, 195, 5, 4, 1]
        let cupid = [0, 267, 269, 270, 409, 291, 0]
        paint.fillRule = .winding
        paint.blend = blendMode(for: "softLightBlendMode")
        addSmoothedCheekPolygon(leftHighlight, to: path)
        addSmoothedCheekPolygon(rightHighlight, to: path)
        let eyeMidY = (point(33).y + point(263).y) * 0.5
        let chinY = point(152).y
        let faceLen = max(abs(chinY - eyeMidY), 40)
        let noseHalfW = max(3.2, min(8.5, faceLen * 0.052))
        addRibbonAlongPolyline(noseBridge, halfWidth: noseHalfW, to: path)
        addSmoothedCheekPolygon(cupid, to: path)
        let t = pow(max(0.0, min(1.0, intensity)), 0.48)
        paint.fill = shade.withAlphaComponent(max(0.05, 0.13 * t))
        paint.shadowColor = shade
        paint.shadowOpacity = min(0.45, 0.22 + t * 0.28)
        paint.shadowRadius = 38
      } else if isFace {
        let faceOval = [338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109, 151, 10]
        let outerLips = [61, 185, 40, 39, 37, 0, 267, 269, 270, 409, 291, 375, 321, 405, 314, 17, 84, 181, 91, 146]
        let leftEye = [33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246]
        let rightEye = [362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398]

        addPolygon(faceOval, to: path, close: true)
        addPolygon(outerLips, to: path, close: true)
        addPolygon(leftEye, to: path, close: true)
        addPolygon(rightEye, to: path, close: true)
        let a = max(0.20, min(0.65, intensity * 0.7))
        paint.fill = shade.withAlphaComponent(a)
        paint.shadowColor = shade
        paint.shadowOpacity = a * 0.52
        paint.shadowRadius = 24
      } else if isShadow {
        func addShadowBand(_ lidIndices: [Int], verticalBias: CGFloat) {
          guard lidIndices.count >= 3 else { return }
          let lid = lidIndices.map { point($0) }
          let minX = lid.map(\.x).min() ?? 0
          let maxX = lid.map(\.x).max() ?? 0
          let eyeWidth = max(1.0, maxX - minX)
          let bandHeight = max(12.0, min(26.0, eyeWidth * 0.25))
          var upper: [CGPoint] = []
          upper.reserveCapacity(lid.count)
          for i in 0..<lid.count {
            let p0 = lid[i]
            let prev = lid[max(0, i - 1)]
            let next = lid[min(lid.count - 1, i + 1)]
            let dx = next.x - prev.x
            let dy = next.y - prev.y
            let len = max(0.001, sqrt(dx * dx + dy * dy))
            var nx = -dy / len
            var ny = dx / len
            if ny > 0 { nx = -nx; ny = -ny }
            let t = CGFloat(i) / CGFloat(max(1, lid.count - 1))
            let centerBoost = 0.70 + (0.35 * (1.0 - abs((t * 2.0) - 1.0)))
            let off = bandHeight * centerBoost
            upper.append(CGPoint(x: p0.x + (nx * off), y: p0.y + (ny * off) + verticalBias))
          }
          path.move(to: upper[0])
          for p1 in upper.dropFirst() { path.addLine(to: p1) }
          for p1 in lid.reversed() { path.addLine(to: p1) }
          path.close()
        }
        let leftUpperLid = [33, 246, 161, 160, 159, 158, 157, 173, 133]
        let rightUpperLid = [263, 466, 388, 387, 386, 385, 384, 398, 362]
        addShadowBand(leftUpperLid, verticalBias: -2.0)
        addShadowBand(rightUpperLid, verticalBias: -2.0)
        let a = max(0.14, min(0.34, intensity * 0.24))
        paint.fill = shade.withAlphaComponent(a)
        paint.shadowColor = shade
        paint.shadowOpacity = min(0.28, intensity * 0.42)
        paint.shadowRadius = 8
      } else if isMascara {
        let leftUpperLash = [33, 246, 161, 160, 159, 158, 157, 173, 133]
        let rightUpperLash = [362, 398, 384, 385, 386, 387, 388, 466, 263]
        paint.fill = .clear
        paint.stroke = shade.withAlphaComponent(max(0.45, intensity * 0.92))
        paint.lineWidth = max(0.70, min(1.10, 0.80 + (intensity * 0.20)))
        addPolygon(leftUpperLash, to: path, close: false)
        addPolygon(rightUpperLash, to: path, close: false)
        paint.shadowColor = UIColor.black
        paint.shadowOpacity = min(0.16, intensity * 0.16)
        paint.shadowRadius = 0.8
      } else if isEyebrow {
        let leftBrowUpper = [70, 63, 105, 66, 107, 55]
        let leftBrowLower = [46, 53, 52, 65, 55]
        let rightBrowUpper = [300, 293, 334, 296, 336, 285]
        let rightBrowLower = [276, 283, 282, 295, 285]
        addPolygon(leftBrowUpper + Array(leftBrowLower.reversed()), to: path, close: true)
        addPolygon(rightBrowUpper + Array(rightBrowLower.reversed()), to: path, close: true)
        paint.fill = shade.withAlphaComponent(max(0.16, min(0.38, intensity * 0.30)))
        paint.shadowColor = UIColor.black
        paint.shadowOpacity = min(0.12, intensity * 0.14)
        paint.shadowRadius = 1.0
      } else if isEyeliner {
        let leftEyeTop = [33, 246, 161, 160, 159, 158, 157, 173, 133]
        let leftEyeBottom = [33, 7, 163, 144, 145, 153, 154, 155, 133]
        let rightEyeTop = [362, 398, 384, 385, 386, 387, 388, 466, 263]
        let rightEyeBottom = [362, 382, 381, 380, 374, 373, 390, 249, 263]
        paint.fill = .clear
        paint.stroke = shade.withAlphaComponent(intensity)
        paint.lineWidth = 2.5
        addPolygon(leftEyeTop, to: path, close: false)
        addPolygon(leftEyeBottom, to: path, close: false)
        addPolygon(rightEyeTop, to: path, close: false)
        addPolygon(rightEyeBottom, to: path, close: false)
      } else if isLipLiner {
        let outer = [61, 185, 40, 39, 37, 0, 267, 269, 270, 409, 291, 375, 321, 405, 314, 17, 84, 181, 91, 146]
        paint.fill = .clear
        paint.stroke = shade.withAlphaComponent(intensity)
        paint.lineWidth = 3.5
        addPolygon(outer, to: path, close: true)
      } else if isLipstick {
        let outer = [61, 185, 40, 39, 37, 0, 267, 269, 270, 409, 291, 375, 321, 405, 314, 17, 84, 181, 91, 146]
        let inner = [78, 191, 80, 81, 82, 13, 312, 311, 310, 415, 308, 324, 318, 402, 317, 14, 87, 178, 88, 95]
        addPolygon(outer, to: path, close: true)
        addPolygon(inner, to: path, close: true)
        paint.fillRule = .evenOdd
        paint.fill = shade.withAlphaComponent(intensity)
      }

      return (path, paint)
    }

    let renderer = UIGraphicsImageRenderer(size: size)
    let out = renderer.image { ctx in
      baseImage.draw(in: CGRect(origin: .zero, size: size))
      let context = ctx.cgContext
      let layers: [MakeupLookEntry]
      if usesMakeupLookStack {
        layers = makeupLookStack
      } else {
        layers = [MakeupLookEntry(category: currentCategory, shade: currentShade, intensity: currentIntensity)]
      }
      for entry in layers {
        guard let (p, paint) = buildLayer(category: entry.category, shade: entry.shade, intensity: entry.intensity) else { continue }
        context.saveGState()
        context.setBlendMode(paint.blend)
        if let sc = paint.shadowColor, paint.shadowOpacity > 0, paint.shadowRadius > 0 {
          context.setShadow(offset: paint.shadowOffset, blur: paint.shadowRadius, color: sc.withAlphaComponent(paint.shadowOpacity).cgColor)
        }
        p.usesEvenOddFillRule = (paint.fillRule == .evenOdd)
        context.addPath(p.cgPath)
        context.setFillColor(paint.fill.cgColor)
        context.drawPath(using: .fill)
        context.restoreGState()

        if paint.lineWidth > 0, paint.stroke != .clear {
          context.saveGState()
          context.setBlendMode(paint.blend)
          context.addPath(p.cgPath)
          context.setStrokeColor(paint.stroke.cgColor)
          context.setLineWidth(paint.lineWidth)
          context.setLineJoin(.round)
          context.setLineCap(.round)
          context.strokePath()
          context.restoreGState()
        }
      }
    }
    return out.pngData()
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func sendEvent(_ payload: [String: Any]) {
    DispatchQueue.main.async {
      self.eventSink?(payload)
    }
  }

  private func sendError(code: String, message: String) {
    sendEvent(["type": "error", "code": code, "message": message])
  }
}

extension UIColor {
    convenience init(argb: Int64) {
        let a = CGFloat((argb >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
