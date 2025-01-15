import Cocoa
import FlutterMacOS

public class FlutterLiteCameraPlugin: NSObject, FlutterPlugin {
  private let cameraManager = CameraManager()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_lite_camera", binaryMessenger: registrar.messenger)
    let instance = FlutterLiteCameraPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
    case "getDeviceList":
      result(cameraManager.listDevices())
    case "open":
      if let args = call.arguments as? [Int], let index = args.first {
        result(cameraManager.open(cameraIndex: index))
      } else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Index required", details: nil))
      }
    case "captureFrame":
      if let frame = cameraManager.captureFrame() {
        result([
          "width": frame.width,
          "height": frame.height,
          "data": frame.rgbData,
        ])
      } else {
        result(FlutterError(code: "CAPTURE_FAILED", message: "No frame available", details: nil))
      }
    case "setResolution":
      if let args = call.arguments as? [Int], args.count == 2 {
        result(cameraManager.setResolution(width: args[0], height: args[1]))
      } else {
        result(
          FlutterError(code: "INVALID_ARGUMENT", message: "Width and height required", details: nil)
        )
      }
    case "getWidth":
      result(cameraManager.getWidth())
    case "getHeight":
      result(cameraManager.getHeight())
    case "release":
      cameraManager.release()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
