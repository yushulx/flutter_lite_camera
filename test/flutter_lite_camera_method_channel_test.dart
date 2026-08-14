import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_lite_camera/flutter_lite_camera_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelFlutterLiteCamera platform = MethodChannelFlutterLiteCamera();
  const MethodChannel channel = MethodChannel('flutter_lite_camera');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'getDeviceList':
            return ['camera0'];
          case 'open':
            return true;
          case 'startPreview':
            return 7;
          case 'stopPreview':
          case 'release':
            return null;
          case 'captureFrame':
            return <String, dynamic>{
              'width': 640,
              'height': 480,
              'data': Uint8List(640 * 480 * 3),
            };
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getDeviceList', () async {
    expect(await platform.getDeviceList(), ['camera0']);
  });

  test('open', () async {
    expect(await platform.open(0), true);
  });

  test('startPreview', () async {
    expect(await platform.startPreview(), 7);
  });

  test('captureFrame', () async {
    final frame = await platform.captureFrame();
    expect(frame['width'], 640);
    expect(frame['height'], 480);
  });
}
