import 'flutter_lite_camera_platform_interface.dart';

class FlutterLiteCamera {
  Future<List<String>> getDeviceList() {
    return FlutterLiteCameraPlatform.instance.getDeviceList();
  }

  Future<bool> open(int index) {
    return FlutterLiteCameraPlatform.instance.open(index);
  }

  Future<Map<String, dynamic>> captureFrame() {
    return FlutterLiteCameraPlatform.instance.captureFrame();
  }

  /// Starts the native preview stream and returns a texture id that can be
  /// shown with a [Texture] widget. Call [open] before this.
  Future<int> startPreview() {
    return FlutterLiteCameraPlatform.instance.startPreview();
  }

  /// Stops the preview stream started with [startPreview].
  Future<void> stopPreview() {
    return FlutterLiteCameraPlatform.instance.stopPreview();
  }

  Future<void> release() {
    return FlutterLiteCameraPlatform.instance.release();
  }
}
