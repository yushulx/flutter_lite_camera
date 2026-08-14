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
  ///
  /// While a preview is running (see [startPreview]) this returns the latest
  /// frame from the native frame cache without disturbing the video stream.
  Future<Map<String, dynamic>> captureFrame() {
    throw UnimplementedError('captureFrame() has not been implemented.');
  }

  /// Starts the native preview stream and returns a texture id.
  ///
  /// The camera must be opened with [open] first. Pass the returned id to a
  /// [Texture] widget to display the video feed. Frames are drawn entirely at
  /// the native layer; no pixel data crosses the platform channel.
  Future<int> startPreview() {
    throw UnimplementedError('startPreview() has not been implemented.');
  }

  /// Stops the preview stream and unregisters the texture.
  Future<void> stopPreview() {
    throw UnimplementedError('stopPreview() has not been implemented.');
  }

  /// Releases the camera and associated resources.
  Future<void> release() {
    throw UnimplementedError('release() has not been implemented.');
  }
}
