import Flutter
import UIKit
import AVFoundation
import MediaPipeTasksVision

private let viewType = "native_lip_renderer/view"
private let channelPrefix = "native_lip_renderer"

public class NativeLipRendererPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let factory = NativeLipRendererViewFactory(messenger: registrar.messenger())
    registrar.register(factory, withId: viewType)
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

private class NativeLipRendererView: NSObject, FlutterPlatformView, FlutterStreamHandler, AVCaptureVideoDataOutputSampleBufferDelegate {
  private let container: PreviewContainerView
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?

  private var captureSession: AVCaptureSession?
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var faceLandmarker: FaceLandmarker?

  private let lipOverlayLayer = CAShapeLayer()
  private var currentShade: UIColor = .red
  private var currentIntensity: CGFloat = 0.7
  private var currentSplitPosition: CGFloat = 0.5 // Default to middle
  private var isCompareMode: Bool = false // Added
  private var currentCategory: String = "Lip Sticks"

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
    container = PreviewContainerView(frame: frame)
    container.backgroundColor = .black
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
        self?.previewLayer?.frame = bounds
        self?.lipOverlayLayer.frame = bounds
    }

    setupLipLayer()
    methodChannel.setMethodCallHandler(handle)
    eventChannel.setStreamHandler(self)
    setupFaceLandmarker()
  }

  func view() -> UIView {
    return container
  }

  private func setupLipLayer() {
    lipOverlayLayer.fillRule = .evenOdd
    lipOverlayLayer.opacity = 0.0
    container.layer.addSublayer(lipOverlayLayer)
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
            let shadeNum = args["shade"] as? NSNumber
            let intensityNum = args["intensity"] as? NSNumber

            if let shadeNum, let intensityNum {
                self.currentShade = UIColor(argb: shadeNum.int64Value)
                self.currentIntensity = CGFloat(intensityNum.doubleValue)
            }
            if let cat = args["category"] as? String {
                self.currentCategory = cat
            }
            if let compare = args["isCompareMode"] as? Bool {
                self.isCompareMode = compare
            }
            // Basic fill setup, will override in drawLips if needed
            self.lipOverlayLayer.fillColor = self.currentShade.withAlphaComponent(self.currentIntensity).cgColor
            self.lipOverlayLayer.shadowOpacity = 0 // reset shadow
        }
        result(nil)
    case "setDebug":
        // Debug mode can be implemented if needed
        result(nil)
    case "setCalibration":
        if let args = call.arguments as? [String: Any],
           let splitPosition = args["splitPosition"] as? Double {
            self.currentSplitPosition = CGFloat(splitPosition)
        }
        result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startCamera() {
    let session = AVCaptureSession()
    session.sessionPreset = .hd1280x720

    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
          let input = try? AVCaptureDeviceInput(device: device) else {
            sendError(code: "camera", message: "Failed to access front camera")
            return
          }

    if session.canAddInput(input) {
        session.addInput(input)
    }

    let output = AVCaptureVideoDataOutput()
    output.alwaysDiscardsLateVideoFrames = true
    output.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)]
    output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_queue"))
    if session.canAddOutput(output) {
        session.addOutput(output)
    }
    
    if let connection = output.connection(with: .video), connection.isVideoOrientationSupported {
        connection.videoOrientation = .portrait
        connection.isVideoMirrored = true // Front camera naturally mirrored
    }

    let preview = AVCaptureVideoPreviewLayer(session: session)
    preview.frame = container.bounds
    preview.videoGravity = .resizeAspectFill
    container.layer.insertSublayer(preview, at: 0)

    self.captureSession = session
    self.previewLayer = preview

    DispatchQueue.global(qos: .userInitiated).async {
        session.startRunning()
        self.sendEvent(["type": "ready"])
    }
  }

  private func stopCamera() {
    captureSession?.stopRunning()
    previewLayer?.removeFromSuperlayer()
    captureSession = nil
    previewLayer = nil
  }

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard let landmarker = faceLandmarker else { return }

    // Convert CMSampleBuffer to MPImage
    do {
        let image = try MPImage(sampleBuffer: sampleBuffer)
        let timestampMs = Int(Date().timeIntervalSince1970 * 1000)

        let result = try landmarker.detect(videoFrame: image, timestampInMilliseconds: timestampMs)

        DispatchQueue.main.async {
            self.drawLips(result)
        }
    } catch {
        // Silently fail or log occasionally to avoid spam
    }
  }

  private func drawLips(_ result: FaceLandmarkerResult) {
    guard let landmarks = result.faceLandmarks.first else {
        lipOverlayLayer.opacity = 0
        return
    }

    let path = UIBezierPath()
    
    // Apply Comparison Mask
    if isCompareMode {
        let mask = CAShapeLayer()
        let splitX = container.bounds.width * currentSplitPosition
        let maskRect = CGRect(x: splitX, y: 0, width: container.bounds.width - splitX, height: container.bounds.height)
        mask.path = UIBezierPath(rect: maskRect).cgPath
        lipOverlayLayer.mask = mask
    } else {
        lipOverlayLayer.mask = nil
    }

    func point(for index: Int) -> CGPoint {
        let lm = landmarks[index]
        let viewW = container.bounds.width
        let viewH = container.bounds.height
        if viewW == 0 || viewH == 0 { return .zero }
        
        let viewAspect = viewW / viewH
        let bufferAspect: CGFloat = 720.0 / 1280.0
        
        if viewAspect > bufferAspect {
            let scaledH = viewW / bufferAspect
            let yOffset = -(scaledH - viewH) / 2.0
            return CGPoint(
                x: CGFloat(lm.x) * viewW,
                y: CGFloat(lm.y) * scaledH + yOffset
            )
        } else {
            let scaledW = viewH * bufferAspect
            let xOffset = -(scaledW - viewW) / 2.0
            return CGPoint(
                x: CGFloat(lm.x) * scaledW + xOffset,
                y: CGFloat(lm.y) * viewH
            )
        }
    }

    func addPolygon(indices: [Int], to path: UIBezierPath, close: Bool = true) {
        if indices.isEmpty { return }
        path.move(to: point(for: indices[0]))
        for i in 1..<indices.count {
            path.addLine(to: point(for: indices[i]))
        }
        if close { path.close() }
    }

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
    
    // Fallback for generic "Eye Makeup" that lacks the specific keywords
    let isGenericEye = category == "cmd_eye"
    
    print("iOS Swift: Category parsed incoming string '\(category)'")
    print("iOS Swift: isMascara=\(isMascara) isShadow=\(isShadow) isEyeliner=\(isEyeliner) isEyebrow=\(isEyebrow) isHighlight=\(isHighlight) isConcealer=\(isConcealer) isHairColor=\(isHairColor) isGenericEye=\(isGenericEye)")

    if isHairColor {
        // Hair overlay estimation: Since FaceMesh doesn't track hair, we trace the very top
        // of the forehead and expand it outwards/upwards to act as an ambient color bloom over the hair region.
        let foreheadLine = [103, 67, 109, 10, 338, 297, 332]
        
        // Extrapolate points high up into the hair volume
        func pointHighUpRow(_ pIdx: Int, heightScale: CGFloat, widthScale: CGFloat = 1.0) -> CGPoint {
            let p = point(for: pIdx)
            let centerP = point(for: 10) // top center of forehead
            let dx = (p.x - centerP.x) * widthScale
            let dy = p.y - centerP.y
            // Push it significantly higher up the forehead
            return CGPoint(x: centerP.x + dx, y: p.y - (abs(dy) * 0.5) - heightScale)
        }

        let hairBloom = [
            pointHighUpRow(103, heightScale: 180, widthScale: 1.8),
            pointHighUpRow(67, heightScale: 200, widthScale: 1.5),
            pointHighUpRow(109, heightScale: 210, widthScale: 1.2),
            pointHighUpRow(10, heightScale: 220, widthScale: 1.0),
            pointHighUpRow(338, heightScale: 210, widthScale: 1.2),
            pointHighUpRow(297, heightScale: 200, widthScale: 1.5),
            pointHighUpRow(332, heightScale: 180, widthScale: 1.8),
        ]
        
        if hairBloom.count > 0 && foreheadLine.count > 0 {
            path.move(to: hairBloom[0])
            for i in 1..<hairBloom.count {
                path.addLine(to: hairBloom[i])
            }
            // Loop back down the forehead contour
            for (_, pIdx) in foreheadLine.reversed().enumerated() {
                path.addLine(to: point(for: pIdx))
            }
            path.close()
        }

        // Extremely soft blend to simulate hair dye glow without hard edges
        lipOverlayLayer.fillColor = self.currentShade.withAlphaComponent(max(0.1, self.currentIntensity * 0.4)).cgColor
        lipOverlayLayer.strokeColor = UIColor.clear.cgColor
        lipOverlayLayer.shadowColor = self.currentShade.cgColor
        lipOverlayLayer.shadowOpacity = Float(min(0.6, self.currentIntensity))
        lipOverlayLayer.shadowRadius = 45.0 // massive feathering
        lipOverlayLayer.shadowOffset = .zero

    } else if isBlush {
        // Blush: Angled upwards along the cheekbones (zygomatic bone)
        let leftCheek = [116, 117, 118, 100, 101, 119, 120, 121, 147, 213, 192, 214, 207, 205, 116]
        let rightCheek = [345, 346, 347, 329, 330, 348, 349, 350, 376, 433, 416, 434, 427, 425, 345]

        addPolygon(indices: leftCheek, to: path)
        addPolygon(indices: rightCheek, to: path)
        
        // Slight fill + glow so blush is clearly visible.
        lipOverlayLayer.fillColor = self.currentShade.withAlphaComponent(max(0.10, self.currentIntensity * 0.22)).cgColor
        lipOverlayLayer.shadowColor = self.currentShade.cgColor
        lipOverlayLayer.shadowOpacity = Float(min(0.55, self.currentIntensity * 0.9))
        lipOverlayLayer.shadowRadius = 18.0
        lipOverlayLayer.shadowOffset = .zero

    } else if isHighlight {
        // Highlighter on upper cheekbones + nose bridge + cupid's bow.
        let leftHighlight = [116, 117, 118, 100, 101, 119, 120, 121, 147, 116]
        let rightHighlight = [345, 346, 347, 329, 330, 348, 349, 350, 376, 345]
        let noseBridge = [168, 6, 197, 195, 5, 4, 1]
        let cupid = [0, 267, 269, 270, 409, 291, 0]

        addPolygon(indices: leftHighlight, to: path)
        addPolygon(indices: rightHighlight, to: path)
        addPolygon(indices: noseBridge, to: path, close: false)
        addPolygon(indices: cupid, to: path, close: false)

        lipOverlayLayer.fillColor = UIColor.clear.cgColor
        lipOverlayLayer.strokeColor = self.currentShade.withAlphaComponent(max(0.10, self.currentIntensity * 0.25)).cgColor
        lipOverlayLayer.lineWidth = 2.0
        lipOverlayLayer.shadowColor = self.currentShade.cgColor
        lipOverlayLayer.shadowOpacity = Float(min(0.50, self.currentIntensity * 0.75))
        lipOverlayLayer.shadowRadius = 14.0
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

        lipOverlayLayer.fillColor = self.currentShade.withAlphaComponent(max(0.12, self.currentIntensity * 0.24)).cgColor
        lipOverlayLayer.strokeColor = UIColor.clear.cgColor
        lipOverlayLayer.shadowColor = self.currentShade.cgColor
        lipOverlayLayer.shadowOpacity = Float(min(0.24, self.currentIntensity * 0.35))
        lipOverlayLayer.shadowRadius = 8.0
        lipOverlayLayer.shadowOffset = .zero

    } else if isFace {
        // Foundation: Face contour minus eyes and lips
        let faceOval = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109]
        let outerLips = [61, 185, 40, 39, 37, 0, 267, 269, 270, 409, 291, 375, 321, 405, 314, 17, 84, 181, 91, 146]
        let leftEye = [33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246]
        let rightEye = [362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398]

        addPolygon(indices: faceOval, to: path)
        addPolygon(indices: outerLips, to: path)
        addPolygon(indices: leftEye, to: path)
        addPolygon(indices: rightEye, to: path)
        
        // Foundation needs to be very light and blended
        lipOverlayLayer.fillColor = self.currentShade.withAlphaComponent(max(0.1, self.currentIntensity * 0.4)).cgColor
        
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

    lipOverlayLayer.path = path.cgPath
    lipOverlayLayer.opacity = 1.0

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
