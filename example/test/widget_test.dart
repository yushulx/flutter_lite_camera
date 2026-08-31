// Smoke test for the example app.

import 'package:flutter/material.dart';
import 'package:flutter_lite_camera/flutter_lite_camera.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_lite_camera_example/main.dart';

void main() {
  testWidgets('App builds and shows camera controls',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // The example UI always exposes the Start button and the
    // resolution preset dropdown, even without a camera.
    expect(find.text('Start'), findsOneWidget);
    expect(find.byType(DropdownButton<ResolutionPreset>), findsOneWidget);
  });
}
