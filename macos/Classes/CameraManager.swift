import AVFoundation
import FlutterMacOS
import Foundation

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

    func listDevices() -> [String] {
        let devices = AVCaptureDevice.devices()
            .filter { $0.hasMediaType(.video) }
        return devices.map { $0.localizedName }
    }

    func open(cameraIndex: Int) -> Bool {
        guard cameraIndex < AVCaptureDevice.devices(for: .video).count else {
            print("Camera index out of range.")
            return false
        }

        let devices = AVCaptureDevice.devices(for: .video)
        self.captureDevice = devices[cameraIndex]

        do {
            let input = try AVCaptureDeviceInput(device: self.captureDevice!)
            self.captureSession = AVCaptureSession()
            self.captureSession?.beginConfiguration()

            if self.captureSession?.canAddInput(input) == true {
                self.captureSession?.addInput(input)
            } else {
                print("Cannot add input to session.")
                return false
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

            if self.captureSession?.canAddOutput(self.videoOutput!) == true {
                self.captureSession?.addOutput(self.videoOutput!)
                self.videoOutput?.setSampleBufferDelegate(
                    self, queue: DispatchQueue.global(qos: .userInteractive))
            } else {
                print("Cannot add video output to session.")
                return false
            }

            self.captureSession?.commitConfiguration()
            self.captureSession?.startRunning()

            return true

        } catch {
            print("Error initializing camera: \(error.localizedDescription)")
            return false
        }
    }

    func setResolution(width: Int, height: Int) -> Bool {
        guard let device = self.captureDevice else {
            print("Capture device is not initialized.")
            return false
        }

        do {
            try device.lockForConfiguration()
            if let format = device.formats.first(where: {
                CMVideoFormatDescriptionGetDimensions($0.formatDescription).width == width
                    && CMVideoFormatDescriptionGetDimensions($0.formatDescription).height == height
            }) {
                device.activeFormat = format
                device.unlockForConfiguration()
                self.frameWidth = width
                self.frameHeight = height
                return true
            } else {
                print("Resolution not supported.")
                device.unlockForConfiguration()
                return false
            }
        } catch {
            print("Error setting resolution: \(error.localizedDescription)")
            return false
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

    func release() {
        self.onFrame = nil
        self.captureSession?.stopRunning()
        self.captureSession = nil
        self.videoOutput = nil
        self.captureDevice = nil
        self.latestPixelBuffer = nil
    }

    func listSupportedMediaTypes() -> [[String: Any]] {
        guard let device = self.captureDevice else {
            print("Capture device is not initialized.")
            return []
        }

        return device.formats.map {
            let dimensions = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            return [
                "width": dimensions.width,
                "height": dimensions.height,
                "format": "\(CMFormatDescriptionGetMediaSubType($0.formatDescription))",
            ]
        }
    }

    func saveJpeg(filename: String, width: Int, height: Int, rgbData: Data) {
        guard let url = URL(string: filename) else {
            print("Invalid filename.")
            return
        }

        guard let provider = CGDataProvider(data: rgbData as CFData) else {
            print("Failed to create data provider.")
            return
        }

        guard
            let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 24,
                bytesPerRow: width * 3,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        else {
            print("Failed to create CGImage.")
            return
        }

        let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypeJPEG, 1, nil)
        CGImageDestinationAddImage(destination!, cgImage, nil)
        if !CGImageDestinationFinalize(destination!) {
            print("Failed to save image.")
        } else {
            print("Image saved to \(filename).")
        }
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
