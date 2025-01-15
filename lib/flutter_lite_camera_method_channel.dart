import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_lite_camera_platform_interface.dart';

/// An implementation of [FlutterLiteCameraPlatform] that uses method channels.
class MethodChannelFlutterLiteCamera extends FlutterLiteCameraPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_lite_camera');

  /// Lists the available video capture devices.
  ///
  /// Returns a [Future] that completes with a list of device names as strings.
  @override
  Future<List<String>> getDeviceList() async {
    List<dynamic> devices = await methodChannel.invokeMethod('getDeviceList');
    return devices.cast<String>();
  }

  /// Opens the camera with the specified index.
  ///
  /// Takes an [index] as a parameter to specify the camera to open.
  /// Returns a [Future] that completes with a boolean indicating success or failure.
  @override
  Future<bool> open(int index) async {
    bool success = await methodChannel.invokeMethod('open', [index]);
    return success;
  }

  /// Captures a frame from the camera.
  ///
  /// Returns a [Future] that completes with a map containing the frame RGB88 data, width, and height.
  @override
  Future<Map<String, dynamic>> captureFrame() async {
    Map<dynamic, dynamic> frame =
        await methodChannel.invokeMethod('captureFrame');
    return frame.cast<String, dynamic>();
  }

  /// Releases the camera resources.
  ///
  /// Returns a [Future] that completes when the resources are released.
  @override
  Future<void> release() async {
    await methodChannel.invokeMethod('release');
  }
}
