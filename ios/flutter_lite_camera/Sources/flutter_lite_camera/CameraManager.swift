import AVFoundation
import CoreVideo
import Flutter
import Foundation

/// AVFoundation capture pipeline for iOS.
///
/// Mirrors the macOS implementation: frames are delivered as BGRA pixel
/// buffers that can be handed to a `FlutterTexture` with zero copies. The
/// latest buffer is also cached so `captureFrame()` can convert it to RGB888
/// on demand without disturbing the preview stream.
class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var captureDevice: AVCaptureDevice?
    private var frameWidth: Int = 640
    private var frameHeight: Int = 480

    /// Called on the capture queue for every incoming frame. The pixel buffer
    /// is BGRA and can be handed to a FlutterTexture directly.
    var onFrame: ((CVPixelBuffer) -> Void)?

    private let bufferLock = NSLock()
    private var _latestPixelBuffer: CVPixelBuffer?

    private var latestPixelBuffer: CVPixelBuffer? {
        get {
            bufferLock.lock()
            defer { bufferLock.unlock() }
            return _latestPixelBuffer
        }
        set {
            bufferLock.lock()
            _latestPixelBuffer = newValue
            bufferLock.unlock()
        }
    }

    struct FrameData {
        var width: Int
        var height: Int
        var rgbData: Data
    }

    override init() {
        super.init()
    }

    /// Requests camera permission (if needed) and then opens the camera. The
    /// completion handler is always called on the main queue.
    func open(cameraIndex: Int, completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            doOpen(cameraIndex: cameraIndex, completion: completion)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.doOpen(cameraIndex: cameraIndex, completion: completion)
                    } else {
                        completion(false)
                    }
                }
            }
        default:
            DispatchQueue.main.async {
                completion(false)
            }
        }
    }

    private func doOpen(cameraIndex: Int, completion: @escaping (Bool) -> Void) {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTripleCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: .unspecified
        ).devices

        guard cameraIndex < devices.count else {
            print("Camera index out of range.")
            DispatchQueue.main.async { completion(false) }
            return
        }

        self.captureDevice = devices[cameraIndex]

        do {
            let input = try AVCaptureDeviceInput(device: self.captureDevice!)
            let session = AVCaptureSession()
            self.captureSession = session
            session.beginConfiguration()

            // The device must be configured while the session is not running.
            session.sessionPreset = .high

            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                print("Cannot add input to session.")
                DispatchQueue.main.async { completion(false) }
                return
            }

            // Pick the format closest to the requested resolution
            if let format = self.captureDevice?.formats.min(by: {
                let d0 = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                let d1 = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
                return abs(Int(d0.width) - self.frameWidth) + abs(Int(d0.height) - self.frameHeight)
                    < abs(Int(d1.width) - self.frameWidth) + abs(Int(d1.height) - self.frameHeight)
            }) {
                try self.captureDevice?.lockForConfiguration()
                self.captureDevice?.activeFormat = format
                self.captureDevice?.unlockForConfiguration()
                let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                print("Resolution set to \(d.width)x\(d.height)")
            } else {
                print("\(self.frameWidth)x\(self.frameHeight) resolution not supported")
            }

            self.videoOutput = AVCaptureVideoDataOutput()
            self.videoOutput?.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput?.alwaysDiscardsLateVideoFrames = true

            if session.canAddOutput(self.videoOutput!) {
                session.addOutput(self.videoOutput!)
                self.videoOutput?.setSampleBufferDelegate(
                    self, queue: DispatchQueue.global(qos: .userInteractive))
            } else {
                print("Cannot add video output to session.")
                DispatchQueue.main.async { completion(false) }
                return
            }

            session.commitConfiguration()

            // startRunning blocks until the first frame arrives, so it must
            // never run on the main thread on iOS.
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
                DispatchQueue.main.async { completion(true) }
            }
        } catch {
            print("Error initializing camera: \(error.localizedDescription)")
            DispatchQueue.main.async { completion(false) }
        }
    }

    func setResolution(width: Int, height: Int) -> Bool {
        guard let device = self.captureDevice else {
            print("Capture device is not initialized.")
            return false
        }

        // Mobile sensors are physically landscape, so a requested WxH may
        // map to HxW on the sensor. Pick the closest supported format under
        // either orientation instead of failing on inexact sizes; the actual
        // dimensions are reported through getWidth()/getHeight().
        func distance(_ d: CMVideoDimensions) -> Int {
            min(abs(Int(d.width) - width) + abs(Int(d.height) - height),
                abs(Int(d.width) - height) + abs(Int(d.height) - width))
        }

        do {
            try device.lockForConfiguration()
            if let format = device.formats.min(by: {
                distance(CMVideoFormatDescriptionGetDimensions($0.formatDescription))
                    < distance(CMVideoFormatDescriptionGetDimensions($1.formatDescription))
            }) {
                device.activeFormat = format
                device.unlockForConfiguration()
                let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                if Int(d.width) != width || Int(d.height) != height {
                    print("Resolution \(width)x\(height) not supported; using \(d.width)x\(d.height).")
                }
                self.frameWidth = Int(d.width)
                self.frameHeight = Int(d.height)
                return true
            } else {
                device.unlockForConfiguration()
                return false
            }
        } catch {
            print("Error setting resolution: \(error.localizedDescription)")
            return false
        }
    }

    /// Lists the camera names. On iOS a permission prompt may be required
    /// before real device names are available; completion runs on main.
    func listDevices(completion: @escaping ([String]) -> Void) {
        func enumerate() {
            let devices = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTripleCamera, .builtInTrueDepthCamera],
                mediaType: .video,
                position: .unspecified
            ).devices
            completion(devices.map { device in
                switch device.position {
                case .back: return "\(device.localizedName) (back)"
                case .front: return "\(device.localizedName) (front)"
                default: return device.localizedName
                }
            })
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            enumerate()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { enumerate() } else { completion([]) }
                }
            }
        default:
            completion([])
        }
    }

    /// Converts the latest BGRA frame to RGB888 on demand. This runs only when
    /// a frame is explicitly requested (e.g. for barcode decoding) and never
    /// touches the preview path.
    func captureFrame() -> FrameData? {
        guard let pixelBuffer = latestPixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        var rgbData = Data(count: width * height * 3)
        rgbData.withUnsafeMutableBytes { dstPointer in
            let dst = dstPointer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let src = baseAddress.assumingMemoryBound(to: UInt8.self)

            for y in 0..<height {
                let srcRow = src + y * bytesPerRow
                let dstRow = dst + y * width * 3
                for x in 0..<width {
                    // BGRA -> RGB
                    dstRow[x * 3] = srcRow[x * 4 + 2]
                    dstRow[x * 3 + 1] = srcRow[x * 4 + 1]
                    dstRow[x * 3 + 2] = srcRow[x * 4]
                }
            }
        }

        return FrameData(width: width, height: height, rgbData: rgbData)
    }

    func getWidth() -> Int {
        if let buffer = latestPixelBuffer {
            return CVPixelBufferGetWidth(buffer)
        }
        return self.frameWidth
    }

    func getHeight() -> Int {
        if let buffer = latestPixelBuffer {
            return CVPixelBufferGetHeight(buffer)
        }
        return self.frameHeight
    }

    /// The clockwise degrees to rotate the preview so it appears upright for
    /// the current device orientation. The camera sensor is physically
    /// landscape, so this is non-zero on phones held in portrait (90°).
    ///
    /// Returns 0, 90, 180 or 270. The buffer is never rotated; callers apply
    /// this angle to the preview widget and to decoded result coordinates.
    func rotationDegrees() -> Int {
        let sensor = sensorOrientationDegrees()
        let device = deviceOrientationDegrees()
        return (sensor - device + 360) % 360
    }

    /// The sensor's native orientation in degrees (clockwise) relative to
    /// portrait. Modern iPhones deliver landscape buffers.
    private func sensorOrientationDegrees() -> Int {
        switch self.captureDevice?.position ?? .back {
        case .front: return 270
        default: return 90
        }
    }

    /// The current interface orientation in the same convention (degrees
    /// clockwise from portrait).
    private func deviceOrientationDegrees() -> Int {
        switch UIDevice.current.orientation {
        case .landscapeLeft: return 90
        case .portraitUpsideDown: return 180
        case .landscapeRight: return 270
        case .portrait, .faceUp, .faceDown, .unknown: return 0
        @unknown default: return 0
        }
    }

    func release() {
        self.onFrame = nil
        self.captureSession?.stopRunning()
        self.captureSession = nil
        self.videoOutput = nil
        self.captureDevice = nil
        self.latestPixelBuffer = nil
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to get pixel buffer.")
            return
        }

        // Retain the buffer for on-demand captureFrame() conversions, then
        // forward it to the preview texture without any pixel processing.
        self.latestPixelBuffer = pixelBuffer
        self.onFrame?(pixelBuffer)
    }
}
