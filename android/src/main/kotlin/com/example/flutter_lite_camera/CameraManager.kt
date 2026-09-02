package com.example.flutter_lite_camera

import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.display.DisplayManager
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager as AndroidCameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.media.Image
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.util.Size
import android.view.Surface
import java.util.concurrent.CountDownLatch
import kotlin.math.abs

/**
 * Camera2 capture pipeline.
 *
 * Preview runs through a [SurfaceTexture] owned by Flutter's texture
 * registry, so video frames are composited natively and never cross the
 * platform channel. A YUV_420_888 [ImageReader] runs alongside it in the same
 * capture session and keeps the most recent frame cached; [captureFrame]
 * converts that cached frame to RGB888 on demand (e.g. for barcode decoding)
 * without interrupting the preview stream.
 */
class CameraManager(private val context: Context) {

    companion object {
        private const val TAG = "CameraManager"
        private const val DEFAULT_WIDTH = 640
        private const val DEFAULT_HEIGHT = 480
    }

    /** A cached frame converted to packed RGB888, matching other platforms. */
    class FrameData(val width: Int, val height: Int, val rgbData: ByteArray)

    private val camera2Manager =
        context.getSystemService(Context.CAMERA_SERVICE) as AndroidCameraManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null

    // Fields below are only touched on the background thread after the
    // camera is open; the volatile reference allows the main thread to check
    // whether open() completed.
    @Volatile
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var characteristics: CameraCharacteristics? = null

    // SurfaceTexture provided by Flutter's texture registry; null while no
    // preview is running.
    @Volatile
    private var previewSurfaceTexture: SurfaceTexture? = null

    // Rotate-and-crop mode forced on the capture request, or -1 to leave the
    // HAL default. Modern HALs default to AUTO, which lets them rotate the
    // capture (ImageReader) stream independently of the preview stream. When
    // NONE is available it is forced so the capture stream is deterministically
    // sensor-native; the preview-side rotation is handled separately through
    // the SurfaceTexture transform (see previewTransformRotation).
    @Volatile
    private var rotateAndCropMode = -1

    // Clockwise degrees the display pipeline (SurfaceTexture transform hint,
    // applied by the Flutter engine while sampling) rotates the preview
    // relative to the sensor frame. -1 = not measured yet. Modern devices
    // rotate the preview to the display orientation this way, which is why
    // the official camera plugin never applies sensor orientation in Dart.
    @Volatile
    private var previewTransformRotation = -1

    // Surface wrapping the current preview SurfaceTexture. Created, swapped,
    // and released on the background thread only, keyed to the texture so a
    // session never references a finalized Surface and session rebuilds do
    // not leak one Surface per call.
    private var bgPreviewTexture: SurfaceTexture? = null
    private var bgPreviewSurface: Surface? = null

    private var frameWidth = DEFAULT_WIDTH
    private var frameHeight = DEFAULT_HEIGHT

    // Cached planes of the latest YUV frame for captureFrame().
    private val frameLock = Any()
    private var yPlane: ByteArray? = null
    private var uPlane: ByteArray? = null
    private var vPlane: ByteArray? = null
    private var yRowStride = 0
    private var uRowStride = 0
    private var uPixelStride = 0
    private var vRowStride = 0
    private var vPixelStride = 0

    /** Lists the camera names, ordered the same way [open] indexes them. */
    fun listDevices(): List<String> {
        return camera2Manager.cameraIdList.mapIndexed { index, id ->
            val lens = camera2Manager.getCameraCharacteristics(id)
                .get(CameraCharacteristics.LENS_FACING)
            val facing = when (lens) {
                CameraMetadata.LENS_FACING_FRONT -> "front"
                CameraMetadata.LENS_FACING_BACK -> "back"
                CameraMetadata.LENS_FACING_EXTERNAL -> "external"
                else -> "unknown"
            }
            "Camera $index ($facing)"
        }
    }

    fun hasCameraPermission(): Boolean =
        context.checkSelfPermission(android.Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED

    /**
     * Opens the camera at [cameraIndex] and starts a capture session that
     * feeds the YUV frame cache. Safe to call before any preview exists —
     * frames flow to [captureFrame] even without [startPreview].
     * [completion] is called on the main thread with true once the repeating
     * request is running.
     */
    fun open(cameraIndex: Int, completion: (Boolean) -> Unit) {
        val ids = camera2Manager.cameraIdList
        if (cameraIndex >= ids.size) {
            Log.e(TAG, "Camera index out of range.")
            mainHandler.post { completion(false) }
            return
        }

        release()
        startBackgroundThread()
        val cameraId = ids[cameraIndex]

        backgroundHandler?.post {
            try {
                characteristics = camera2Manager.getCameraCharacteristics(cameraId)
                selectRotateAndCropMode()

                val closest = chooseOutputSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
                Log.i(
                    TAG,
                    "open camera=$cameraId sensorOrientation=${
                        characteristics?.get(CameraCharacteristics.SENSOR_ORIENTATION)
                    } negotiated=${closest.width}x${closest.height}" +
                        " racMode=$rotateAndCropMode",
                )

                imageReader = ImageReader.newInstance(
                    closest.width, closest.height, ImageFormat.YUV_420_888, 2,
                ).apply {
                    setOnImageAvailableListener({ reader ->
                        val image = reader.acquireLatestImage()
                        if (image != null) {
                            try {
                                cacheFrame(image)
                            } finally {
                                image.close()
                            }
                        }
                    }, backgroundHandler)
                }

                frameWidth = closest.width
                frameHeight = closest.height

                camera2Manager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                    override fun onOpened(device: CameraDevice) {
                        cameraDevice = device
                        buildSession(device) { success ->
                            mainHandler.post { completion(success) }
                        }
                    }

                    override fun onDisconnected(device: CameraDevice) {
                        device.close()
                        cameraDevice = null
                    }

                    override fun onError(device: CameraDevice, error: Int) {
                        Log.e(TAG, "openCamera error: $error")
                        device.close()
                        cameraDevice = null
                        mainHandler.post { completion(false) }
                    }
                }, backgroundHandler)
            } catch (e: Exception) {
                Log.e(TAG, "Error opening camera: ${e.localizedMessage}")
                mainHandler.post { completion(false) }
            }
        }
    }

    /**
     * Attaches [surfaceTexture] (from Flutter's texture registry) to the
     * active camera and begins rendering the preview through it. Returns
     * false when the camera is not open; otherwise the session is rebuilt
     * asynchronously, so a frame appears shortly after this returns.
     */
    fun startPreview(surfaceTexture: SurfaceTexture): Boolean {
        val device = cameraDevice
        if (device == null) {
            Log.e(TAG, "startPreview called before open().")
            return false
        }
        // The camera renders into Flutter's SurfaceTexture; match the buffer
        // size to the negotiated output size so the preview frame is not
        // blank/stretched.
        surfaceTexture.setDefaultBufferSize(frameWidth, frameHeight)
        previewSurfaceTexture = surfaceTexture
        previewTransformRotation = -1
        backgroundHandler?.post { buildSession(device) { } }
        return true
    }

    /** Detaches the preview surface; the YUV frame cache keeps running. */
    fun stopPreview() {
        val device = cameraDevice
        previewSurfaceTexture = null
        previewTransformRotation = -1
        if (device != null) {
            backgroundHandler?.post { buildSession(device) { } }
        }
    }

    /**
     * The clockwise degrees the display pipeline rotates the preview relative
     * to the sensor frame, measured from the SurfaceTexture transform matrix
     * (the same matrix the Flutter engine applies while sampling). Before the
     * first frame arrives the matrix is still identity, so fall back to the
     * framework behavior every modern device exhibits: the camera service
     * rotates the preview to the display orientation, i.e. the full sensor
     * compensation [sensorCompensationDegrees].
     */
    private fun previewRotationDegrees(): Int {
        previewTransformRotation.let { if (it >= 0) return it }
        val texture = previewSurfaceTexture
        if (texture != null) {
            val m = FloatArray(16)
            try {
                texture.getTransformMatrix(m)
            } catch (ignored: Exception) {
                return sensorCompensationDegrees()
            }
            if (texture.timestamp != 0L) {
                val rotation = extractRotationDegrees(m)
                previewTransformRotation = rotation
                return rotation
            }
        }
        return sensorCompensationDegrees()
    }

    /**
     * Extracts the rotational component of a SurfaceTexture transform matrix.
     * The matrix may also carry the flips used to map between image and GL
     * texture coordinates; only the axis-swapping 90° steps matter here.
     */
    private fun extractRotationDegrees(m: FloatArray): Int {
        val m0 = m[0]
        val m1 = m[1]
        val m4 = m[4]
        val m5 = m[5]
        return when {
            // Axes swapped: a 90°/270° rotation is present. Same signs mean
            // the content is turned 90° clockwise, opposite signs 270°.
            m0 == 0f && m5 == 0f -> if (m4 < 0 && m1 < 0) 90 else 270
            // Both axes negated: 180°.
            m0 < 0 && m5 < 0 -> 180
            else -> 0
        }
    }

    /** Clockwise degrees to rotate a sensor-native frame for the display. */
    private fun sensorCompensationDegrees(): Int {
        val sensor = characteristics
            ?.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
        return (sensor - deviceRotationDegrees() + 360) % 360
    }

    /**
     * (Re)builds the capture session around the current set of output
     * surfaces and starts the preview repeating request. Background thread
     * only.
     */
    private fun buildSession(device: CameraDevice, onConfigured: (Boolean) -> Unit) {
        // Runs on the background thread. Keep exactly one Surface per
        // SurfaceTexture: release the wrapper when the texture changes or the
        // preview is detached, so the session never references a finalized
        // Surface and rebuilds do not leak.
        val texture = previewSurfaceTexture
        if (texture !== bgPreviewTexture) {
            try {
                bgPreviewSurface?.release()
            } catch (ignored: Exception) {
            }
            bgPreviewSurface = texture?.let { Surface(it) }
            bgPreviewTexture = texture
        }

        val outputs = mutableListOf<Surface>()
        bgPreviewSurface?.let { outputs.add(it) }
        imageReader?.surface?.let { outputs.add(it) }

        try {
            captureSession?.close()
        } catch (ignored: Exception) {
        }

        try {
            @Suppress("DEPRECATION")
            device.createCaptureSession(
                outputs,
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        captureSession = session
                        try {
                            val request =
                                device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                            for (surface in outputs) request.addTarget(surface)
                            request.set(
                                CaptureRequest.CONTROL_MODE,
                                CameraMetadata.CONTROL_MODE_AUTO,
                            )
                            if (rotateAndCropMode >= 0 &&
                                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
                            ) {
                                request.set(
                                    CaptureRequest.SCALER_ROTATE_AND_CROP,
                                    rotateAndCropMode,
                                )
                            }
                            session.setRepeatingRequest(
                                request.build(), null, backgroundHandler,
                            )
                            onConfigured(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to start preview: ${e.localizedMessage}")
                            onConfigured(false)
                        }
                    }

                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        Log.e(TAG, "Capture session configuration failed.")
                        onConfigured(false)
                    }
                },
                backgroundHandler,
            )
        } catch (e: Exception) {
            // createCaptureSession throws synchronously when the device has
            // been closed by a fatal HAL error.
            Log.e(TAG, "createCaptureSession error: ${e.localizedMessage}")
            onConfigured(false)
        }
    }

    /**
     * Picks the rotate-and-crop mode for the capture request. Forces
     * [CameraMetadata.SCALER_ROTATE_AND_CROP_NONE] when the HAL lists it, so
     * the capture (ImageReader) stream is deterministically sensor-native
     * instead of being rotated at the HAL's discretion (AUTO). The preview
     * side is handled separately via [previewRotationDegrees]. Leaves the HAL
     * default (-1) when the device exposes no mode list.
     */
    private fun selectRotateAndCropMode() {
        rotateAndCropMode = -1
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val modes = characteristics
            ?.get(CameraCharacteristics.SCALER_AVAILABLE_ROTATE_AND_CROP_MODES)
            ?: return
        if (modes.contains(CameraMetadata.SCALER_ROTATE_AND_CROP_NONE)) {
            rotateAndCropMode = CameraMetadata.SCALER_ROTATE_AND_CROP_NONE
        }
    }

    /** Copies the planar YUV data of [image] into the small cache. */
    private fun cacheFrame(image: Image) {
        val planes = image.planes
        val y = ByteArray(planes[0].buffer.remaining()).also { planes[0].buffer.get(it) }
        val u = ByteArray(planes[1].buffer.remaining()).also { planes[1].buffer.get(it) }
        val v = ByteArray(planes[2].buffer.remaining()).also { planes[2].buffer.get(it) }

        synchronized(frameLock) {
            yPlane = y
            uPlane = u
            vPlane = v
            yRowStride = planes[0].rowStride
            uRowStride = planes[1].rowStride
            uPixelStride = planes[1].pixelStride
            vRowStride = planes[2].rowStride
            vPixelStride = planes[2].pixelStride
            frameWidth = image.width
            frameHeight = image.height
        }
    }

    /**
     * Grabs a still frame. [byteOrder] selects the output channel
     * arrangement of the RGB888 buffer:
     * 0=RGB, 1=RBG, 2=GRB, 3=GBR, 4=BRG, 5=BGR.
     */
    fun captureFrame(byteOrder: Int): FrameData? {
        return yuvCaptureFrame(2)
    }

    /**
     * Converts the cached YUV_420_888 frame to packed RGB888 (BT.601 full
     * range) with integer math, handling planar and semi-planar chroma
     * layouts through the pixel strides. The result is rotated by
     * [previewRotationDegrees] so the returned frame matches what the user
     * sees in the preview — coordinates derived from it (e.g. barcode
     * bounding boxes) map 1:1 onto the displayed image. Runs only when a
     * frame is explicitly requested and never touches the preview path.
     */
    private fun yuvCaptureFrame(byteOrder: Int): FrameData? {
        // Snapshot planes and strides under one lock so they all come from
        // the same cached frame.
        lateinit var y: ByteArray
        lateinit var u: ByteArray
        lateinit var v: ByteArray
        var yRs = 0
        var uRs = 0
        var uPs = 0
        var vRs = 0
        var vPs = 0
        var w = 0
        var h = 0
        synchronized(frameLock) {
            val cachedY = yPlane ?: return null
            val cachedU = uPlane ?: return null
            val cachedV = vPlane ?: return null
            y = cachedY
            u = cachedU
            v = cachedV
            yRs = yRowStride
            uRs = uRowStride
            uPs = uPixelStride
            vRs = vRowStride
            vPs = vPixelStride
            w = frameWidth
            h = frameHeight
        }

        // The chroma roles below, combined with the GRB write of scheme 2
        // (the default byteOrder), reproduce verified-correct colors on
        // Android. Other devices can select a different arrangement through
        // the byteOrder parameter.
        val uData = v
        val vData = u
        val uRowStride = vRs
        val vRowStride = uRs
        val uPixelStride = vPs
        val vPixelStride = uPs

        val rotation = previewRotationDegrees()
        val outW = if (rotation % 180 == 90) h else w
        val outH = if (rotation % 180 == 90) w else h
        val rgb = ByteArray(w * h * 3)
        for (row in 0 until h) {
            val chromaRow = row / 2
            val uRow = chromaRow * uRowStride
            val vRow = chromaRow * vRowStride
            var yCol = row * yRs
            for (col in 0 until w) {
                val chromaCol = col / 2
                var cn = uRow + chromaCol * uPixelStride
                if (cn >= uData.size) cn = uData.size - 1
                var cb = vRow + chromaCol * vPixelStride
                if (cb >= vData.size) cb = vData.size - 1
                val yv = y[yCol++].toInt() and 0xFF
                val cv = (vData[cb].toInt() and 0xFF) - 128
                val cu = (uData[cn].toInt() and 0xFF) - 128
                // BT.601 full-range YUV -> RGB, fixed point (<<16 scale):
                // R = Y + 1.402·V, G = Y − 0.344·U − 0.714·V, B = Y + 1.772·U.
                var r = yv + ((cv * 91881) shr 16)
                var g = yv - ((cu * 22554 + cv * 46802) shr 16)
                var b = yv + ((cu * 116130) shr 16)
                if (r < 0) r = 0 else if (r > 255) r = 255
                if (g < 0) g = 0 else if (g > 255) g = 255
                if (b < 0) b = 0 else if (b > 255) b = 255
                // Write to the rotated destination position so the frame
                // matches the on-screen preview orientation.
                val dst = when (rotation) {
                    90 -> (col * outW + (h - 1 - row)) * 3
                    180 -> ((h - 1 - row) * outW + (w - 1 - col)) * 3
                    270 -> ((w - 1 - col) * outW + row) * 3
                    else -> (row * outW + col) * 3
                }
                // Write the pixel in the channel arrangement selected by
                // [byteOrder]: 0=RGB, 1=RBG, 2=GRB, 3=GBR, 4=BRG, 5=BGR.
                when (byteOrder) {
                    1 -> {
                        rgb[dst] = r.toByte(); rgb[dst + 1] = b.toByte(); rgb[dst + 2] = g.toByte()
                    }
                    2 -> {
                        rgb[dst] = g.toByte(); rgb[dst + 1] = r.toByte(); rgb[dst + 2] = b.toByte()
                    }
                    3 -> {
                        rgb[dst] = g.toByte(); rgb[dst + 1] = b.toByte(); rgb[dst + 2] = r.toByte()
                    }
                    4 -> {
                        rgb[dst] = b.toByte(); rgb[dst + 1] = r.toByte(); rgb[dst + 2] = g.toByte()
                    }
                    5 -> {
                        rgb[dst] = b.toByte(); rgb[dst + 1] = g.toByte(); rgb[dst + 2] = r.toByte()
                    }
                    else -> {
                        rgb[dst] = r.toByte(); rgb[dst + 1] = g.toByte(); rgb[dst + 2] = b.toByte()
                    }
                }
            }
        }
        return FrameData(outW, outH, rgb)
    }

    // Width/height of the frames captureFrame() returns, i.e. the sensor
    // size with the preview rotation applied (swapped when rotated 90/270).
    fun getWidth(): Int =
        if (previewRotationDegrees() % 180 == 90) frameHeight else frameWidth

    fun getHeight(): Int =
        if (previewRotationDegrees() % 180 == 90) frameWidth else frameHeight

    /**
     * The clockwise degrees the caller must still apply to the preview widget
     * (and to coordinates derived from [captureFrame]) so they appear
     * upright. On Android the display pipeline already rotates the preview by
     * [previewRotationDegrees], so this is the sensor compensation minus the
     * part the pipeline handles — typically 0 on modern phones, matching the
     * official camera plugin, which never applies sensor orientation in Dart.
     */
    fun rotationDegrees(): Int {
        val compensation = sensorCompensationDegrees()
        return (compensation - previewRotationDegrees() + 360) % 360
    }

    private fun deviceRotationDegrees(): Int {
        // DisplayManager works on every supported API level and from a
        // non-visual application context. Context.display requires API 30
        // and returns null for contexts not associated with a display.
        val dm = context.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
        return when (dm?.getDisplay(android.view.Display.DEFAULT_DISPLAY)?.rotation) {
            android.view.Surface.ROTATION_90 -> 90
            android.view.Surface.ROTATION_180 -> 180
            android.view.Surface.ROTATION_270 -> 270
            else -> 0
        }
    }

    /**
     * All output sizes usable for the capture stream. Falls back to the
     * SurfaceTexture class list when YUV_420_888 is not reported (some HALs
     * omit it), and to the default size only as a last resort so the plugin
     * never invents a size the camera cannot produce.
     */
    private fun supportedOutputSizes(): List<Size> {
        val map = characteristics
            ?.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            ?: return listOf(Size(DEFAULT_WIDTH, DEFAULT_HEIGHT))
        val yuv = map.getOutputSizes(ImageFormat.YUV_420_888)
        if (!yuv.isNullOrEmpty()) return yuv.toList()
        val texture = map.getOutputSizes(SurfaceTexture::class.java)
        if (!texture.isNullOrEmpty()) return texture.toList()
        return listOf(Size(DEFAULT_WIDTH, DEFAULT_HEIGHT))
    }

    /**
     * The supported size closest to [width]x[height]. A portrait request
     * (e.g. 480x640) matches the equivalent landscape sensor size (640x480)
     * because mobile sensors are physically landscape — the same convention
     * the iOS implementation uses when matching formats.
     */
    private fun chooseOutputSize(width: Int, height: Int): Size {
        val sizes = supportedOutputSizes()
        return sizes.minByOrNull {
            minOf(
                abs(it.width - width) + abs(it.height - height),
                abs(it.width - height) + abs(it.height - width),
            )
        } ?: Size(DEFAULT_WIDTH, DEFAULT_HEIGHT)
    }

    /**
     * Switches the capture stream to the requested resolution. If the exact
     * size is unsupported, falls back to the closest supported size instead
     * of failing — the camera always keeps running, and the actual size is
     * reported through getWidth()/getHeight() and every captureFrame() call.
     * Returns false only when no camera is open.
     */
    fun setResolution(width: Int, height: Int): Boolean {
        if (characteristics == null) return false
        val chosen = chooseOutputSize(width, height)
        if (chosen.width != width || chosen.height != height) {
            Log.w(
                TAG,
                "Resolution ${width}x${height} not supported; " +
                    "using ${chosen.width}x${chosen.height} instead.",
            )
        }
        val newReader = ImageReader.newInstance(
            chosen.width, chosen.height, ImageFormat.YUV_420_888, 2,
        ).apply {
            setOnImageAvailableListener({ reader ->
                val image = reader.acquireLatestImage()
                if (image != null) {
                    try {
                        cacheFrame(image)
                    } finally {
                        image.close()
                    }
                }
            }, backgroundHandler)
        }
        val oldReader = imageReader
        imageReader = newReader
        frameWidth = chosen.width
        frameHeight = chosen.height
        // Keep the preview buffer size in sync with the capture stream.
        previewSurfaceTexture?.setDefaultBufferSize(chosen.width, chosen.height)
        val device = cameraDevice
        if (device != null) {
            backgroundHandler?.post {
                try {
                    oldReader?.close()
                } catch (ignored: Exception) {
                }
                buildSession(device) { }
            }
        } else {
            try {
                oldReader?.close()
            } catch (ignored: Exception) {
            }
        }
        return true
    }

    /** Closes the camera and every associated resource. */
    fun release() {
        previewSurfaceTexture = null
        val handler = backgroundHandler
        val device = cameraDevice
        val session = captureSession
        val reader = imageReader
        cameraDevice = null
        captureSession = null
        imageReader = null
        characteristics = null
        synchronized(frameLock) {
            yPlane = null
            uPlane = null
            vPlane = null
        }
        if (handler != null && (device != null || session != null || reader != null)) {
            // Close on the camera thread and wait for completion so the
            // objects are fully torn down before the thread stops, avoiding
            // Camera2's async finalizers posting to a dead thread.
            val latch = CountDownLatch(1)
            handler.post {
                try {
                    session?.close()
                } catch (ignored: Exception) {
                }
                try {
                    reader?.close()
                } catch (ignored: Exception) {
                }
                try {
                    device?.close()
                } catch (ignored: Exception) {
                }
                releaseBgPreviewSurface()
                latch.countDown()
            }
            try {
                latch.await()
            } catch (ignored: InterruptedException) {
            }
        } else {
            try {
                session?.close()
            } catch (ignored: Exception) {
            }
            try {
                reader?.close()
            } catch (ignored: Exception) {
            }
            try {
                device?.close()
            } catch (ignored: Exception) {
            }
            releaseBgPreviewSurface()
        }
        stopBackgroundThread()
    }

    /** Releases the retained preview Surface wrapper, if any. */
    private fun releaseBgPreviewSurface() {
        try {
            bgPreviewSurface?.release()
        } catch (ignored: Exception) {
        }
        bgPreviewSurface = null
        bgPreviewTexture = null
    }

    private fun startBackgroundThread() {
        if (backgroundThread != null) return
        backgroundThread = HandlerThread("CameraBackground").also { it.start() }
        backgroundHandler = Handler(backgroundThread!!.looper)
    }

    private fun stopBackgroundThread() {
        backgroundThread?.quitSafely()
        try {
            backgroundThread?.join()
        } catch (e: InterruptedException) {
            Log.e(TAG, "stopBackgroundThread: ${e.localizedMessage}")
        }
        backgroundThread = null
        backgroundHandler = null
    }
}
