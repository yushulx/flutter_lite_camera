import AVFoundation
import Accelerate
import FlutterMacOS
import Foundation

class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var captureDevice: AVCaptureDevice?
    private var frameWidth: Int = 640
    private var frameHeight: Int = 480

    private let frameQueue = DispatchQueue(
        label: "com.flutter_lite_camera.frameQueue", attributes: .concurrent)
    private var _currentFrame: FrameData?

    var currentFrame: FrameData? {
        get {
            return frameQueue.sync { _currentFrame }
        }
        set {
            frameQueue.async(flags: .barrier) { self._currentFrame = newValue }
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

            // Find the format with 640x480 resolution
            if let format = self.captureDevice?.formats.first(where: {
                let dimensions = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                return dimensions.width == 1280 && dimensions.height == 720
            }) {
                try self.captureDevice?.lockForConfiguration()
                self.captureDevice?.activeFormat = format
                self.captureDevice?.unlockForConfiguration()
                print("Resolution set to 640x480")
            } else {
                print("640x480 resolution not supported")
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

    func captureFrame() -> FrameData? {
        guard let frame = currentFrame else {
            return nil
        }
        return frame
    }

    func getWidth() -> Int {
        return self.frameWidth
    }

    func getHeight() -> Int {
        return self.frameHeight
    }

    func release() {
        self.captureSession?.stopRunning()
        self.captureSession = nil
        self.videoOutput = nil
        self.captureDevice = nil
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

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)

        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)

        guard let baseAddress = baseAddress else {
            print("Failed to get base address.")
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return
        }

        let targetWidth = 640
        let targetHeight = 480

        // Calculate aspect-ratio-preserving dimensions
        let aspectRatio = CGFloat(sourceWidth) / CGFloat(sourceHeight)
        let scaledWidth = Int(min(CGFloat(targetWidth), CGFloat(targetHeight) * aspectRatio))
        let scaledHeight = Int(CGFloat(scaledWidth) / aspectRatio)

        // Prepare source buffer for resizing
        var sourceBuffer = vImage_Buffer(
            data: baseAddress,
            height: vImagePixelCount(sourceHeight),
            width: vImagePixelCount(sourceWidth),
            rowBytes: bytesPerRow
        )

        // Prepare destination buffer for resized RGBA frame
        let targetBytesPerRowRGBA = scaledWidth * 4  // RGBA
        var resizedRGBAData = Data(count: scaledHeight * targetBytesPerRowRGBA)
        resizedRGBAData.withUnsafeMutableBytes { resizedPointer in
            var destinationBuffer = vImage_Buffer(
                data: resizedPointer.baseAddress!,
                height: vImagePixelCount(scaledHeight),
                width: vImagePixelCount(scaledWidth),
                rowBytes: targetBytesPerRowRGBA
            )

            // Perform resizing using vImage
            vImageScale_ARGB8888(
                &sourceBuffer,
                &destinationBuffer,
                nil,
                vImage_Flags(kvImageNoFlags)
            )
        }

        // Prepare the final buffer for the padded 640x480 image
        let targetBytesPerRowRGB = targetWidth * 3  // RGB
        var paddedRGBData = Data(count: targetHeight * targetBytesPerRowRGB)

        paddedRGBData.withUnsafeMutableBytes { paddedPointer in
            resizedRGBAData.withUnsafeBytes { rgbaPointer in
                let rgbaBytes = rgbaPointer.baseAddress!.assumingMemoryBound(to: UInt8.self)
                let paddedBytes = paddedPointer.baseAddress!.assumingMemoryBound(to: UInt8.self)

                // Center the resized image in the 640x480 frame
                let paddingX = (targetWidth - scaledWidth) / 2
                let paddingY = (targetHeight - scaledHeight) / 2

                for y in 0..<scaledHeight {
                    for x in 0..<scaledWidth {
                        let srcIndex = (y * targetBytesPerRowRGBA) + (x * 4)
                        let dstIndex =
                            ((y + paddingY) * targetBytesPerRowRGB) + ((x + paddingX) * 3)

                        // Copy RGB data, ignoring the alpha channel
                        paddedBytes[dstIndex] = rgbaBytes[srcIndex]  // R
                        paddedBytes[dstIndex + 1] = rgbaBytes[srcIndex + 1]  // G
                        paddedBytes[dstIndex + 2] = rgbaBytes[srcIndex + 2]  // B
                    }
                }
            }
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

        // Create the padded RGB frame
        let paddedFrame = FrameData(
            width: targetWidth, height: targetHeight, rgbData: paddedRGBData)
        self.currentFrame = paddedFrame
        frameWidth = targetWidth
        frameHeight = targetHeight
    }
}
