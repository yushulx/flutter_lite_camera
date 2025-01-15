# Flutter Lite Camera

`Flutter Lite Camera` is a lightweight Flutter plugin designed for capturing camera frames with a fixed resolution of **640x480** in **RGB888** format. The plugin supports **Windows**, **Linux**, and **macOS** platforms, making it ideal for building camera preview applications and performing image processing tasks.

![Flutter camera preview app](https://www.dynamsoft.com/codepool/img/2025/01/flutter-lite-camera.png)

## Features
- **Cross-Platform**: Compatible with **Windows**, **Linux**, and macOS.
- **RGB888 Frame Format**: Captures uncompressed **RGB888** frames for easy image processing.
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
| `captureFrame()` | Captures a single frame as an RGB888 image.       |
| `release()`      | Releases the camera resources.                   |

