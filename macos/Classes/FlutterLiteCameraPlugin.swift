import Cocoa
import FlutterMacOS

/// FlutterTexture backed by the latest camera CVPixelBuffer. The buffer is
/// BGRA, which Flutter supports natively, so preview rendering is zero-copy.
class CameraTexture: NSObject, FlutterTexture {
  private var pixelBuffer: CVPixelBuffer?
  private let lock = NSLock()

  /// Called on the Flutter raster thread. The returned buffer must be
  /// retained; Flutter releases it when done.
  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    defer { lock.unlock() }
    guard let buffer = pixelBuffer else { return nil }
    return Unmanaged.passRetained(buffer)
  }

  /// Called on the camera capture queue.
  func update(_ buffer: CVPixelBuffer) {
    lock.lock()
    pixelBuffer = buffer
    lock.unlock()
  }
}

public class FlutterLiteCameraPlugin: NSObject, FlutterPlugin {
  private let cameraManager = CameraManager()
  private var textureRegistry: FlutterTextureRegistry?
  private var cameraTexture: CameraTexture?
  private var textureId: Int64 = -1

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_lite_camera", binaryMessenger: registrar.messenger)
    let instance = FlutterLiteCameraPlugin()
    instance.textureRegistry = registrar.textures
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private func stopPreview() {
    cameraManager.onFrame = nil
    if textureId >= 0 {
      textureRegistry?.unregisterTexture(textureId)
      textureId = -1
    }
    cameraTexture = nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
    case "getDeviceList":
      result(cameraManager.listDevices())
    case "open":
      if let args = call.arguments as? [Int], let index = args.first {
        stopPreview()
        result(cameraManager.open(cameraIndex: index))
      } else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Index required", details: nil))
      }
    case "startPreview":
      if textureId >= 0 {
        result(textureId)
        return
      }
      guard let registry = textureRegistry else {
        result(FlutterError(code: "TEXTURE_ERROR", message: "Texture registry unavailable", details: nil))
        return
      }
      let texture = CameraTexture()
      let id = registry.register(texture)
      self.cameraTexture = texture
      self.textureId = id
      cameraManager.onFrame = { [weak self, weak texture] pixelBuffer in
        guard let self = self, let texture = texture else { return }
        texture.update(pixelBuffer)
        self.textureRegistry?.textureFrameAvailable(id)
      }
      result(id)
    case "stopPreview":
      stopPreview()
      result(nil)
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
      stopPreview()
      cameraManager.release()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
