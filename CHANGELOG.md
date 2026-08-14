## 0.1.0
- Added native texture preview on Windows, Linux, and macOS. The new `startPreview()`/`stopPreview()` methods render the video feed directly at the native layer through a Flutter texture, so frame data no longer crosses the platform channel for display.
- `captureFrame()` now reads from a native frame cache while the preview is running, so grabbing a frame for image processing does not disturb the video stream.
- Fixed RGB channel order: `captureFrame()` now returns true RGB888 on all platforms (Windows and Linux previously emitted BGR-ordered data).

## 0.0.2
- Fixed camera release issue for Windows.

## 0.0.1

- Initial release of the Flutter Lite Camera plugin.
- Add the following methods:
    
    - getDeviceList(): Returns a list of available camera devices.
    - open(int index): Opens the camera at the specified index.
    - captureFrame(): Captures a single frame as an RGB888 image.
    - release(): Releases the camera resources.
