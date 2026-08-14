// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_lite_camera/flutter_lite_camera.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('getDeviceList test', (WidgetTester tester) async {
    final FlutterLiteCamera plugin = FlutterLiteCamera();
    final List<String> devices = await plugin.getDeviceList();
    // The device list depends on the host machine, so just assert that the
    // call succeeds and returns a list.
    expect(devices, isA<List<String>>());
  });

  testWidgets('camera open/preview/capture pipeline test',
      (WidgetTester tester) async {
    final FlutterLiteCamera plugin = FlutterLiteCamera();
    final List<String> devices = await plugin.getDeviceList();

    if (devices.isEmpty) {
      // No camera on this host (e.g. a CI runner without a virtual camera).
      // The full pipeline cannot be exercised here.
      return;
    }

    expect(await plugin.open(0), isTrue);

    // Native texture preview: frames are drawn at the native layer and only
    // the texture id crosses into Dart.
    final int textureId = await plugin.startPreview();
    expect(textureId, greaterThanOrEqualTo(0));

    // Give the capture thread a moment to fill the frame cache.
    await tester.pump(const Duration(seconds: 1));
    await Future.delayed(const Duration(seconds: 1));

    // Grabbing a frame for image processing must not disturb the preview.
    final Map<String, dynamic> frame = await plugin.captureFrame();
    final int width = frame['width'] as int;
    final int height = frame['height'] as int;
    final Uint8List data = frame['data'] as Uint8List;
    expect(width, greaterThan(0));
    expect(height, greaterThan(0));
    expect(data.length, width * height * 3);

    // A second frame proves the stream is still running after captureFrame().
    await Future.delayed(const Duration(milliseconds: 200));
    final Map<String, dynamic> frame2 = await plugin.captureFrame();
    expect((frame2['data'] as Uint8List).length,
        (frame2['width'] as int) * (frame2['height'] as int) * 3);

    await plugin.stopPreview();
    await plugin.release();
  });
}
