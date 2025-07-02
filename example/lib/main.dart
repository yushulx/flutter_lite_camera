import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_barcode_sdk/dynamsoft_barcode.dart';
import 'package:flutter_barcode_sdk/flutter_barcode_sdk.dart';
import 'package:flutter_lite_camera/flutter_lite_camera.dart';
import 'dart:ui' as ui;

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
  bool _isCapturing = false;
  int _width = 640;
  int _height = 480;
  ui.Image? _latestFrame;
  bool _shouldCapture = false;
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
          setState(() {
            _isCameraOpened = true;
            _shouldCapture = true;
          });

          // Start capturing frames
          _isCapturing = true;
          _captureFrames();
        } else {
          print("Failed to open the camera.");
        }
      }
    } catch (e) {
      // print("Error initializing camera: $e");
    }
  }

  Future<void> _decodeFrame(Uint8List rgb, int width, int height) async {
    if (isDecoding || _barcodeReader == null) return;

    isDecoding = true;
    results = await _barcodeReader!.decodeImageBuffer(
      rgb,
      width,
      height,
      width * 3,
      ImagePixelFormat.IPF_RGB_888.index,
      ImageRotation.rotation0.index,
    );

    isDecoding = false;
  }

  Future<void> _captureFrames() async {
    if (!_isCameraOpened || !_shouldCapture) return;

    try {
      Map<String, dynamic> frame =
          await _flutterLiteCameraPlugin.captureFrame();
      if (frame.containsKey('data')) {
        Uint8List rgbBuffer = frame['data'];
        _decodeFrame(rgbBuffer, frame['width'], frame['height']);
        await _convertBufferToImage(rgbBuffer, frame['width'], frame['height']);
      }
    } catch (e) {
      // print("Error capturing frame: $e");
    }

    // Schedule the next frame
    if (_shouldCapture) {
      Future.delayed(const Duration(milliseconds: 30), _captureFrames);
    }
  }

  Future<void> _convertBufferToImage(
      Uint8List rgbBuffer, int width, int height) async {
    final pixels = Uint8List(width * height * 4); // RGBA buffer

    for (int i = 0; i < width * height; i++) {
      int r = rgbBuffer[i * 3];
      int g = rgbBuffer[i * 3 + 1];
      int b = rgbBuffer[i * 3 + 2];

      // Populate RGBA buffer
      pixels[i * 4] = b;
      pixels[i * 4 + 1] = g;
      pixels[i * 4 + 2] = r;
      pixels[i * 4 + 3] = 255; // Alpha channel
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );

    final image = await completer.future;
    setState(() {
      _latestFrame = image;
    });
  }

  Future<void> _stopCamera() async {
    setState(() {
      _shouldCapture = false;
    });

    if (_isCameraOpened) {
      await _flutterLiteCameraPlugin.release();
      setState(() {
        _isCameraOpened = false;
        _latestFrame = null;
      });
    }

    _isCapturing = false;
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
          if (_latestFrame != null)
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
                  child: CustomPaint(
                    painter: FramePainter(_latestFrame!, results ?? []),
                    child: SizedBox(
                      width: drawWidth,
                      height: drawHeight,
                    ),
                  ),
                );
              },
            )
          else
            Center(
              child: Text('Camera not initialized or no frame captured'),
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
                  onPressed: _isCapturing ? null : () => _startCamera(),
                  child: const Text('Start'),
                ),
                // Stop Button
                ElevatedButton(
                  onPressed: !_isCapturing ? null : () => _stopCamera(),
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

class FramePainter extends CustomPainter {
  final ui.Image image;
  final List<BarcodeResult> results;

  FramePainter(this.image, this.results);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // Calculate the scaling factor (minimum of X and Y ratios)
    final double scale =
        (size.width / image.width).compareTo(size.height / image.height) < 0
            ? size.width / image.width
            : size.height / image.height;

    // Center the image in the canvas
    final double dx = (size.width - image.width * scale) / 2;
    final double dy = (size.height - image.height * scale) / 2;

    // Draw the image
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(dx, dy, image.width * scale, image.height * scale),
      paint,
    );

    // Draw barcode results
    if (results.isNotEmpty) {
      final textPaint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      for (var result in results) {
        // Scale the coordinates and offset by dx and dy
        final path = Path()
          ..moveTo(dx + result.x1.toDouble() * scale,
              dy + result.y1.toDouble() * scale)
          ..lineTo(dx + result.x2.toDouble() * scale,
              dy + result.y2.toDouble() * scale)
          ..lineTo(dx + result.x3.toDouble() * scale,
              dy + result.y3.toDouble() * scale)
          ..lineTo(dx + result.x4.toDouble() * scale,
              dy + result.y4.toDouble() * scale)
          ..close();

        canvas.drawPath(path, textPaint);

        // Scale text position
        final double textX = dx + result.x1.toDouble() * scale;
        final double textY = dy + result.y1.toDouble() * scale;

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
          Offset(textX, textY),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
