## 0.2.0
- Added **iOS**, **Android**, and **web** implementations — one API across all six platforms.
- Zero-copy preview everywhere: a `FlutterTexture` fed by BGRA buffers on iOS/macOS, an engine `SurfaceTexture` on Android, and an embedded `getUserMedia` video element on the web. No frame data crosses the platform channel for display.
- Added `buildPreview(textureId)`, which returns the correct preview widget per platform (a `Texture` on native, an `HtmlElementView` on the web). Prefer it over a raw `Texture`.
- Added `getRotation()` returning the clockwise degrees (0/90/180/270) to apply in Dart so the preview and decoded coordinates appear upright (typically 90 on iOS phones, 0 elsewhere — Android frames already arrive display-oriented, with coordinates mapping 1:1 onto the preview).
- Added a resolution API: the `ResolutionPreset` enum (`low`/`medium`/`high`/`veryHigh`/`ultraHigh`/`max`) plus `setResolution()`, `setResolutionPreset()`, `getWidth()` and `getHeight()`. Every platform negotiates the closest supported size instead of failing, and the actual size is always queryable. The example no longer hard-codes 640x480 and offers a preset picker.
- Android: requests the `CAMERA` runtime permission from `open()`; fixed preview failing to start and a display-orientation crash on API < 30.

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
