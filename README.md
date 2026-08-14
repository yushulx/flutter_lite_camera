# Flutter Lite Camera

`Flutter Lite Camera` is a lightweight Flutter plugin designed for capturing camera frames with a fixed resolution of **640x480** in **RGB888** format. The plugin supports **Windows**, **Linux**, and **macOS** platforms, making it ideal for building camera preview applications and performing image processing tasks.

![Flutter camera preview app](https://www.dynamsoft.com/codepool/img/2025/01/flutter-lite-camera.png)

## Features
- **Cross-Platform**: Compatible with **Windows**, **Linux**, and macOS.
- **Native Texture Preview**: Renders the video feed directly at the native layer through a Flutter texture — no per-frame data copies into Dart.
- **RGB888 Frame Format**: Captures uncompressed **RGB888** frames on demand for easy image processing, without disturbing the preview stream.
- **Simple Integration**: Easy-to-use API for seamless Flutter integration.

## Requirements
- **Flutter SDK: Version** 3.0.0 or above
- **Permissions**: Ensure camera access is granted on macOS. In `DebugProfile.entitlements` or `Release.entitlements`, add:
    
    ```xml
    <key>com.apple.security.device.camera</key>
	<true/>
    ```
    
## API

| Method          | Description                                      |
|-----------------|--------------------------------------------------|
| `getDeviceList()` | Returns a list of available camera devices.      |
| `open(int index)` | Opens the camera at the specified index.         |
| `startPreview()` | Starts the native preview stream and returns a texture id for a `Texture` widget. |
| `stopPreview()`  | Stops the preview stream and unregisters the texture. |
| `captureFrame()` | Captures a single frame as an RGB888 image. While a preview is running, the frame comes from a native cache and the stream is unaffected. |
| `release()`      | Releases the camera resources.                   |

## Usage

```dart
final camera = FlutterLiteCamera();

final devices = await camera.getDeviceList();
if (devices.isNotEmpty) {
  await camera.open(0);

  // Preview: display the returned texture id with a Texture widget.
  final int textureId = await camera.startPreview();
  // ... Texture(textureId: textureId)

  // Decode: grab a single frame whenever you need one (e.g. for barcode
  // scanning). This does not interrupt the preview.
  final frame = await camera.captureFrame();
  final Uint8List rgb = frame['data'];   // RGB888, width * height * 3 bytes
  final int width = frame['width'];
  final int height = frame['height'];

  await camera.stopPreview();
  await camera.release();
}
```

