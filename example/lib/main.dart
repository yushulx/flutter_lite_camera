import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_barcode_sdk/dynamsoft_barcode.dart';
import 'package:flutter_barcode_sdk/flutter_barcode_sdk.dart';
import 'package:flutter_lite_camera/flutter_lite_camera.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CameraApp(),
    );
  }
}

class CameraApp extends StatefulWidget {
  @override
  State<CameraApp> createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp> {
  final FlutterLiteCamera _flutterLiteCameraPlugin = FlutterLiteCamera();
  bool _isCameraOpened = false;
  int _textureId = -1;
  int _width = 640;
  int _height = 480;
  bool _shouldDecode = false;
  FlutterBarcodeSdk? _barcodeReader;
  // To read barcodes, get a 30-day FREEE trial license for Dynamsoft Barcode Reader https://www.dynamsoft.com/customer/license/trialLicense/?product=dcv&package=cross-platform
  String licenseKey =
      'DLS2eyJoYW5kc2hha2VDb2RlIjoiMjAwMDAxLTE2NDk4Mjk3OTI2MzUiLCJvcmdhbml6YXRpb25JRCI6IjIwMDAwMSIsInNlc3Npb25QYXNzd29yZCI6IndTcGR6Vm05WDJrcEQ5YUoifQ==';
  bool isDecoding = false;
  List<BarcodeResult>? results;

  @override
  void initState() {
    super.initState();
    _handleWindowClose();
    if (licenseKey != '') {
      initBarcodeSDK();
    }
  }

  Future<void> initBarcodeSDK() async {
    _barcodeReader = FlutterBarcodeSdk();
    await _barcodeReader!.setLicense(licenseKey);
    await _barcodeReader!.init();
  }

  Future<void> _startCamera() async {
    try {
      List<String> devices = await _flutterLiteCameraPlugin.getDeviceList();
      if (devices.isNotEmpty) {
        print("Available Devices: $devices");
        print("Opening camera 0");
        bool opened = await _flutterLiteCameraPlugin.open(0);
        if (opened) {
          // The native layer renders the video feed into this texture; no
          // frame data crosses into Dart for display purposes.
          int textureId = await _flutterLiteCameraPlugin.startPreview();
          setState(() {
            _isCameraOpened = true;
            _textureId = textureId;
            _shouldDecode = true;
          });

          // Start pulling frames for barcode decoding only. This does not
          // affect the preview stream.
          _decodeFrames();
        } else {
          print("Failed to open the camera.");
        }
      }
    } catch (e) {
      // print("Error initializing camera: $e");
    }
  }

  Future<void> _decodeFrames() async {
    if (!_isCameraOpened || !_shouldDecode) return;

    if (!isDecoding && _barcodeReader != null) {
      isDecoding = true;
      try {
        Map<String, dynamic> frame =
            await _flutterLiteCameraPlugin.captureFrame();
        if (frame.containsKey('data')) {
          _width = frame['width'];
          _height = frame['height'];
          Uint8List rgbBuffer = frame['data'];

          final ret = await _barcodeReader!.decodeImageBuffer(
            rgbBuffer,
            _width,
            _height,
            _width * 3,
            ImagePixelFormat.IPF_RGB_888.index,
            ImageRotation.rotation0.index,
          );

          setState(() {
            results = ret;
          });
        }
      } catch (e) {
        // No frame available yet.
      }
      isDecoding = false;
    }

    if (_shouldDecode) {
      Future.delayed(const Duration(milliseconds: 30), _decodeFrames);
    }
  }

  Future<void> _stopCamera() async {
    _shouldDecode = false;

    if (_isCameraOpened) {
      await _flutterLiteCameraPlugin.stopPreview();
      await _flutterLiteCameraPlugin.release();
      setState(() {
        _isCameraOpened = false;
        _textureId = -1;
        results = null;
      });
    }
  }

  void _handleWindowClose() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChannels.lifecycle.setMessageHandler((message) async {
        if (message == AppLifecycleState.detached.toString()) {
          await _stopCamera();
        }
        return null;
      });
    });
  }

  @override
  void dispose() {
    _stopCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (_textureId >= 0)
            LayoutBuilder(
              builder: (context, constraints) {
                final screenWidth = constraints.maxWidth;
                final screenHeight = constraints.maxHeight;
                final imageAspectRatio = _width / _height;
                final screenAspectRatio = screenWidth / screenHeight;

                double drawWidth, drawHeight;
                if (imageAspectRatio > screenAspectRatio) {
                  drawWidth = screenWidth;
                  drawHeight = screenWidth / imageAspectRatio;
                } else {
                  drawHeight = screenHeight;
                  drawWidth = screenHeight * imageAspectRatio;
                }

                return Center(
                  child: SizedBox(
                    width: drawWidth,
                    height: drawHeight,
                    child: Stack(
                      children: [
                        Texture(textureId: _textureId),
                        CustomPaint(
                          painter: ResultPainter(
                              results ?? [], drawWidth / _width),
                          child: Container(),
                        ),
                      ],
                    ),
                  ),
                );
              },
            )
          else
            Center(
              child: Text('Camera not initialized'),
            ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Start Button
                ElevatedButton(
                  onPressed: _isCameraOpened ? null : () => _startCamera(),
                  child: const Text('Start'),
                ),
                // Stop Button
                ElevatedButton(
                  onPressed: !_isCameraOpened ? null : () => _stopCamera(),
                  child: const Text('Stop'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ResultPainter extends CustomPainter {
  final List<BarcodeResult> results;
  final double scale;

  ResultPainter(this.results, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    if (results.isEmpty) return;

    final textPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (var result in results) {
      final path = Path()
        ..moveTo(result.x1.toDouble() * scale, result.y1.toDouble() * scale)
        ..lineTo(result.x2.toDouble() * scale, result.y2.toDouble() * scale)
        ..lineTo(result.x3.toDouble() * scale, result.y3.toDouble() * scale)
        ..lineTo(result.x4.toDouble() * scale, result.y4.toDouble() * scale)
        ..close();

      canvas.drawPath(path, textPaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: result.text,
          style: const TextStyle(
            color: Colors.red,
            fontSize: 16,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(result.x1.toDouble() * scale, result.y1.toDouble() * scale),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
