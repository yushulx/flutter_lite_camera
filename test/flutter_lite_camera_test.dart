import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_lite_camera/flutter_lite_camera.dart';
import 'package:flutter_lite_camera/flutter_lite_camera_platform_interface.dart';
import 'package:flutter_lite_camera/flutter_lite_camera_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterLiteCameraPlatform
    with MockPlatformInterfaceMixin
    implements FlutterLiteCameraPlatform {
  @override
  Future<List<String>> getDeviceList() => Future.value(['camera0']);

  @override
  Future<bool> open(int index) => Future.value(true);

  @override
  Future<Map<String, dynamic>> captureFrame() => Future.value({
        'width': 640,
        'height': 480,
        'data': Uint8List(640 * 480 * 3),
      });

  @override
  Future<int> startPreview() => Future.value(1);

  @override
  Future<void> stopPreview() => Future.value();

  @override
  Future<void> release() => Future.value();
}

void main() {
  final FlutterLiteCameraPlatform initialPlatform =
      FlutterLiteCameraPlatform.instance;

  test('$MethodChannelFlutterLiteCamera is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterLiteCamera>());
  });

  test('getDeviceList', () async {
    FlutterLiteCamera flutterLiteCameraPlugin = FlutterLiteCamera();
    MockFlutterLiteCameraPlatform fakePlatform = MockFlutterLiteCameraPlatform();
    FlutterLiteCameraPlatform.instance = fakePlatform;

    expect(await flutterLiteCameraPlugin.getDeviceList(), ['camera0']);
  });

  test('open', () async {
    FlutterLiteCamera flutterLiteCameraPlugin = FlutterLiteCamera();
    expect(await flutterLiteCameraPlugin.open(0), true);
  });

  test('startPreview returns texture id', () async {
    FlutterLiteCamera flutterLiteCameraPlugin = FlutterLiteCamera();
    expect(await flutterLiteCameraPlugin.startPreview(), 1);
  });

  test('captureFrame returns frame map', () async {
    FlutterLiteCamera flutterLiteCameraPlugin = FlutterLiteCamera();
    final frame = await flutterLiteCameraPlugin.captureFrame();
    expect(frame['width'], 640);
    expect(frame['height'], 480);
    expect((frame['data'] as Uint8List).length, 640 * 480 * 3);
  });
}
