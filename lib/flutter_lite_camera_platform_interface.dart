import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_lite_camera_method_channel.dart';

abstract class FlutterLiteCameraPlatform extends PlatformInterface {
  /// Constructs a FlutterLiteCameraPlatform.
  FlutterLiteCameraPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterLiteCameraPlatform _instance = MethodChannelFlutterLiteCamera();

  /// The default instance of [FlutterLiteCameraPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterLiteCamera].
  static FlutterLiteCameraPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterLiteCameraPlatform] when
  /// they register themselves.
  static set instance(FlutterLiteCameraPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Lists available video capture devices.
  Future<List<String>> getDeviceList() {
    throw UnimplementedError('getDeviceList() has not been implemented.');
  }

  /// Opens the camera with the specified index.
  Future<bool> open(int index) {
    throw UnimplementedError('open() has not been implemented.');
  }

  /// Captures a single RGB frame from the camera.
  Future<Map<String, dynamic>> captureFrame() {
    throw UnimplementedError('captureFrame() has not been implemented.');
  }

  /// Releases the camera and associated resources.
  Future<void> release() {
    throw UnimplementedError('release() has not been implemented.');
  }
}
