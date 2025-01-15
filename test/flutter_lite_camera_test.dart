import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_lite_camera/flutter_lite_camera.dart';
import 'package:flutter_lite_camera/flutter_lite_camera_platform_interface.dart';
import 'package:flutter_lite_camera/flutter_lite_camera_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterLiteCameraPlatform
    with MockPlatformInterfaceMixin
    implements FlutterLiteCameraPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterLiteCameraPlatform initialPlatform = FlutterLiteCameraPlatform.instance;

  test('$MethodChannelFlutterLiteCamera is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterLiteCamera>());
  });

  test('getPlatformVersion', () async {
    FlutterLiteCamera flutterLiteCameraPlugin = FlutterLiteCamera();
    MockFlutterLiteCameraPlatform fakePlatform = MockFlutterLiteCameraPlatform();
    FlutterLiteCameraPlatform.instance = fakePlatform;

    expect(await flutterLiteCameraPlugin.getPlatformVersion(), '42');
  });
}
