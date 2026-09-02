package com.example.flutter_lite_camera

import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry

/**
 * Method-channel surface for the plugin. Channel name and argument shapes
 * match the macOS/Windows/Linux implementation exactly.
 *
 * Preview frames are delivered through an engine-managed
 * [TextureRegistry.SurfaceTextureEntry]: the engine wraps the SurfaceTexture
 * in a GL consumer and refreshes the texture on every frame, so no per-frame
 * data ever crosses the platform channel.
 */
class FlutterLiteCameraPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener {
    companion object {
        private const val TAG = "FlutterLiteCameraPlugin"
        private const val CHANNEL = "flutter_lite_camera"
        private const val CAMERA_PERMISSION_REQUEST = 5791
    }

    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var textureRegistry: TextureRegistry? = null
    private var cameraManager: CameraManager? = null
    private var activityBinding: ActivityPluginBinding? = null

    @Volatile
    private var surfaceTextureEntry: TextureRegistry.SurfaceTextureEntry? = null

    // Pending open() call waiting for a permission grant.
    private var pendingOpenIndex: Int? = null
    private var pendingOpenResult: MethodChannel.Result? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        textureRegistry = binding.textureRegistry
        cameraManager = CameraManager(binding.applicationContext)
        channel =
            MethodChannel(binding.binaryMessenger, CHANNEL)
                .also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        stopPreview()
        cameraManager?.release()
        cameraManager = null
        textureRegistry = null
        appContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    private fun stopPreview() {
        synchronized(this) {
            cameraManager?.stopPreview()
            surfaceTextureEntry?.release()
            surfaceTextureEntry = null
        }
    }

    // Method channel handlers run on the platform main thread.
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val manager = cameraManager
        when (call.method) {
            "getPlatformVersion" ->
                result.success("Android ${android.os.Build.VERSION.RELEASE}")

            "getDeviceList" ->
                result.success(manager?.listDevices() ?: emptyList<String>())

            "open" -> {
                val index = (call.arguments as? List<*>)?.firstOrNull() as? Int
                if (index == null) {
                    result.error("INVALID_ARGUMENT", "Index required", null)
                    return
                }
                if (manager == null) {
                    result.error("NOT_READY", "Plugin not attached", null)
                    return
                }
                stopPreview()
                if (manager.hasCameraPermission()) {
                    openCamera(manager, index, result)
                } else {
                    requestPermissionAndOpen(manager, index, result)
                }
            }

            "startPreview" -> {
                if (manager == null) {
                    result.error("NOT_READY", "Plugin not attached", null)
                    return
                }
                synchronized(this) {
                    val existing = surfaceTextureEntry
                    if (existing != null) {
                        result.success(existing.id())
                        return
                    }
                    val registry = textureRegistry
                    if (registry == null) {
                        result.error(
                            "TEXTURE_ERROR",
                            "Texture registry unavailable",
                            null,
                        )
                        return
                    }
                    val entry = registry.createSurfaceTexture()
                    if (!manager.startPreview(entry.surfaceTexture())) {
                        entry.release()
                        result.error(
                            "CAMERA_ERROR",
                            "Failed to start preview. Is the camera open?",
                            null,
                        )
                        return
                    }
                    surfaceTextureEntry = entry
                    result.success(entry.id())
                }
            }

            "stopPreview" -> {
                stopPreview()
                result.success(null)
            }

            "captureFrame" -> {
                val args = call.arguments as? Map<*, *>
                val byteOrder = (args?.get("byteOrder") as? Number)?.toInt() ?: 2
                val frame = manager?.captureFrame(byteOrder)
                if (frame == null) {
                    result.error("CAPTURE_FAILED", "No frame available", null)
                } else {
                    result.success(
                        mapOf(
                            "width" to frame.width,
                            "height" to frame.height,
                            "data" to frame.rgbData,
                        )
                    )
                }
            }

            "setResolution" -> {
                val args = call.arguments as? List<*>
                val width = args?.getOrNull(0) as? Int
                val height = args?.getOrNull(1) as? Int
                if (width == null || height == null) {
                    result.error("INVALID_ARGUMENT", "Width and height required", null)
                    return
                }
                result.success(manager?.setResolution(width, height) ?: false)
            }

            "getWidth" -> result.success(manager?.getWidth() ?: 0)
            "getHeight" -> result.success(manager?.getHeight() ?: 0)
            "getRotation" -> result.success(manager?.rotationDegrees() ?: 0)

            "release" -> {
                stopPreview()
                manager?.release()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun openCamera(
        manager: CameraManager,
        index: Int,
        result: MethodChannel.Result,
    ) {
        manager.open(index) { success ->
            // Match the other platforms: report failure as a plain false
            // (permission denied / device busy), not a channel error.
            mainHandler.post { result.success(success) }
        }
    }

    private fun requestPermissionAndOpen(
        manager: CameraManager,
        index: Int,
        result: MethodChannel.Result,
    ) {
        val activity = activityBinding?.activity
        if (activity == null) {
            // Without an activity the runtime request is impossible; report a
            // plain failed open like permission denial on the other platforms.
            result.success(false)
            return
        }
        pendingOpenIndex = index
        pendingOpenResult = result
        activity.requestPermissions(
            arrayOf(android.Manifest.permission.CAMERA),
            CAMERA_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != CAMERA_PERMISSION_REQUEST) return false
        val granted =
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
        val index = pendingOpenIndex
        val pending = pendingOpenResult
        pendingOpenIndex = null
        pendingOpenResult = null
        val manager = cameraManager
        if (granted && index != null && pending != null && manager != null) {
            openCamera(manager, index, pending)
        } else {
            // Same contract as every other open() failure: plain false.
            pending?.success(false)
        }
        return true
    }
}
