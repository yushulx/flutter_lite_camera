# Flutter Lite Camera

`Flutter Lite Camera` is a lightweight Flutter plugin designed for capturing camera frames in **RGB888** format. The plugin supports **Windows**, **Linux**, **macOS**, **iOS**, **Android**, and **web**, making it ideal for building camera preview applications and performing image processing tasks with any recognition SDK. The default target resolution is **640x480**; each platform negotiates with the device and every frame reports its actual width and height.

![Flutter camera preview app](https://www.dynamsoft.com/codepool/img/2025/01/flutter-lite-camera.png)

## Live demo

[Flutter Camera Barcode Scanner](https://www.dynamsoft.com/codepool/demos/flutter-camera-barcode-scanner/) runs the `example` app as a Flutter web build: open the camera, switch resolution, and read 1D/2D barcodes with Dynamsoft Barcode Reader.

The hosted page activates a Codepool license bound to `dynamsoft.com`. Everywhere else — `localhost`, a fork, a self-hosted copy — `example/web/index.html` falls back to the SDK's public trial key and reports a `license_fallback` event, so the same build runs without any configuration. The key reaches Dart through `example/lib/demo_bridge.dart`.

## Features
- **Cross-Platform**: Compatible with **Windows**, **Linux**, **macOS**, **iOS**, **Android**, and **web**.
- **Zero-Copy Preview**: Renders the video feed directly at the native layer — a `FlutterTexture` fed by BGRA buffers on iOS/macOS, an engine `SurfaceTexture` on Android, and an embedded `getUserMedia` video element on the web. No per-frame data copies into Dart.
- **RGB888 Frame Format**: Captures uncompressed **RGB888** frames on demand for easy image processing, without disturbing the preview stream.
- **Simple Integration**: Easy-to-use API for seamless Flutter integration.

## Requirements
- **Flutter SDK**: 3.27 (Dart 3.6) or above. Flutter 3.44 or above is required
  when the host app enables Swift Package Manager for iOS or macOS.
- **Web**: The page must be served over **HTTPS** (or `localhost`) for `getUserMedia` to work.
- **macOS / iOS permissions**: Ensure camera access is granted.
    - macOS — in `DebugProfile.entitlements` or `Release.entitlements`, add:
    
        ```xml
        <key>com.apple.security.device.camera</key>
        <true/>
        ```
        
    - iOS — in `Runner/Info.plist`, add:
    
        ```xml
        <key>NSCameraUsageDescription</key>
        <string>The app uses the camera.</string>
        ```
        
- **Android permissions**: The plugin requests the `CAMERA` runtime permission automatically when `open()` is called as long as the app declares it:
    
    ```xml
    <uses-permission android:name="android.permission.CAMERA"/>
    ```
    
    Add the declaration to `android/app/src/main/AndroidManifest.xml`.

## API

| Method          | Description                                      |
|-----------------|--------------------------------------------------|
| `getDeviceList()` | Returns a list of available camera devices.      |
| `open(int index)` | Opens the camera at the specified index.         |
| `startPreview()` | Starts the preview stream and returns a texture id to pass to `buildPreview()`. |
| `buildPreview(textureId)` | Returns the preview widget: a `Texture` on native platforms, an embedded video element on the web. |
| `stopPreview()`  | Stops the preview stream. |
| `captureFrame()` | Captures a single frame as an RGB888 image. While a preview is running, the frame comes from a native cache and the stream is unaffected. |
| `getRotation()` | Returns the clockwise degrees (0/90/180/270) to apply to the preview and decoded coordinates so they appear upright (typically 90 on iOS phones, 0 elsewhere — Android frames already arrive display-oriented). |
| `setResolution(int width, int height)` | Requests a capture size; the platform negotiates the closest supported size instead of failing when the exact one is unavailable. |
| `setResolutionPreset(ResolutionPreset preset)` | Same, using a preset: `low` (320x240), `medium` (640x480), `high` (1280x720), `veryHigh` (1920x1080), `ultraHigh` (3840x2160), `max` (device maximum). |
| `getWidth()` / `getHeight()` | Returns the actual negotiated frame size, in display orientation. |
| `release()`      | Releases the camera resources.                   |

## Usage

```dart
final camera = FlutterLiteCamera();

final devices = await camera.getDeviceList();
if (devices.isNotEmpty) {
  await camera.open(0);

  // Optional: pick a resolution. The platform negotiates the closest
  // supported size; getWidth()/getHeight() report the actual result.
  await camera.setResolutionPreset(ResolutionPreset.veryHigh); // 1920x1080

  // Preview: display the returned texture id with buildPreview, which picks
  // the right widget for the platform (Texture on native, a video element on
  // the web).
  final int textureId = await camera.startPreview();
  // ... SizedBox(... child: camera.buildPreview(textureId))

  // Decode: grab a single frame whenever you need one (e.g. for barcode
  // scanning). This does not interrupt the preview.
  final frame = await camera.captureFrame();
  final Uint8List rgb = frame['data'];   // RGB888, width * height * 3 bytes
  final int width = frame['width'];
  final int height = frame['height'];

  // Rotate the preview widget and decoded coordinates by this angle so they
  // display upright (typically 90 on iOS phones, 0 elsewhere).
  final int rotation = await camera.getRotation();

  await camera.stopPreview();
  await camera.release();
}
```

## Platform notes

| Platform | Preview path | `captureFrame()` source | Permission handling |
|----------|--------------|-------------------------|---------------------|
| Windows | Native texture (`CameraWindows.cpp`) | RGB frame cache | — |
| Linux | Native texture (`CameraLinux.cpp`, V4L2) | RGB frame cache | — |
| macOS | Native texture (AVFoundation BGRA) | Latest BGRA pixel buffer | Entitlements + TCC |
| iOS | Native texture (AVFoundation BGRA) | Latest BGRA pixel buffer | `Info.plist` + `AVCaptureDevice.requestAccess` |
| Android | `SurfaceTexture` fed by Camera2 | Latest `YUV_420_888` frame, converted to RGB888 | `AndroidManifest.xml` + runtime request |
| Web | `getUserMedia` video element in a platform view | Snapshot drawn via an `ImageData` pass | Browser prompt (HTTPS required) |
