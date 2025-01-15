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

  Future<void> release() {
    return FlutterLiteCameraPlatform.instance.release();
  }
}
