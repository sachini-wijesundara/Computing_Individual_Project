import Flutter
import UIKit

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
}

private class NativeLipRendererView: NSObject, FlutterPlatformView, FlutterStreamHandler {
  private let container: UIView
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
    container = UIView(frame: frame)
    container.backgroundColor = .black

    let label = UILabel(frame: container.bounds)
    label.textAlignment = .center
    label.textColor = .white
    label.numberOfLines = 0
    label.text = "Native lip renderer (iOS) coming soon"
    label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.addSubview(label)

    methodChannel = FlutterMethodChannel(
      name: "\(channelPrefix)/\(viewId)",
      binaryMessenger: messenger
    )
    eventChannel = FlutterEventChannel(
      name: "\(channelPrefix)/\(viewId)/events",
      binaryMessenger: messenger
    )

    super.init()
    methodChannel.setMethodCallHandler(handle)
    eventChannel.setStreamHandler(self)
  }

  func view() -> UIView {
    return container
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      sendReady()
      result(nil)
    case "stop", "setEffect", "setDebug":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    sendReady()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func sendReady() {
    eventSink?(["type": "ready"])
  }
}
