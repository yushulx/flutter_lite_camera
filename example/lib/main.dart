import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_barcode_sdk/flutter_barcode_sdk.dart';
import 'package:flutter_lite_camera/flutter_lite_camera.dart';

import 'demo_bridge.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const CameraApp(),
    );
  }
}

class CameraApp extends StatefulWidget {
  const CameraApp({super.key});

  @override
  State<CameraApp> createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp> {
  final FlutterLiteCamera _flutterLiteCameraPlugin = FlutterLiteCamera();
  bool _isCameraOpened = false;
  int _textureId = -1;
  // Actual frame size negotiated with the device. Filled in after the camera
  // opens (and after every resolution change) — never hard-coded.
  int _width = 0;
  int _height = 0;
  // Clockwise degrees to rotate the preview/result so it appears upright.
  // Phones report 90 (or 180/270) depending on how the device is held;
  // desktop/web report 0.
  int _rotation = 0;
  ResolutionPreset _preset = ResolutionPreset.medium;
  bool _shouldDecode = false;
  FlutterBarcodeSdk? _barcodeReader;
  // Resolved at runtime: the hosted demo injects the Codepool license on
  // dynamsoft.com and the public trial key everywhere else (see
  // demo_bridge.dart). For anything beyond local experiments, get your own
  // 30-day free trial license:
  // https://www.dynamsoft.com/customer/license/trialLicense/?product=dcv&package=cross-platform
  final String _licenseKey = resolveDemoLicenseKey();
  bool isDecoding = false;
  bool _reportedFirstScan = false;
  List<BarcodeResult>? results;
  // Shown over the preview until the first result arrives: the browser build
  // has to download and initialise the barcode wasm module, and the first
  // decode can take several seconds on a slow machine.
  String _status = 'Starting camera…';

  @override
  void initState() {
    super.initState();
    _handleWindowClose();
    if (_licenseKey.isNotEmpty) {
      initBarcodeSDK();
    }
    // The hosted demo appends ?autostart=1 to the iframe URL so the camera
    // opens on load; a standalone run keeps the manual Start button.
    if (Uri.base.queryParameters['autostart'] == '1') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startCamera());
    }
  }

  Future<void> initBarcodeSDK() async {
    final Stopwatch stopwatch = Stopwatch()..start();
    // License activation can fail when the page runs from a stale cache or the
    // SDK bundle never loaded (DBR then reports -30063 on the first capture).
    // Retry once so a transient failure does not leave the demo silent.
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        _barcodeReader = FlutterBarcodeSdk();
        final int licensed = await _barcodeReader!.setLicense(_licenseKey);
        if (licensed != 0) {
          throw StateError('setLicense returned $licensed');
        }
        await _barcodeReader!.init();
        reportDemoReady(stopwatch.elapsedMilliseconds);
        if (mounted && _isCameraOpened) {
          setState(() => _status = 'Scanning for barcodes…');
        }
        return;
      } catch (e) {
        reportDemoAction('barcode_init_failed', {'attempt': attempt, 'error': '$e'});
        debugPrint('Barcode SDK init failed (attempt $attempt): $e');
        _barcodeReader = null;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    if (mounted) {
      setState(() => _status =
          'Barcode engine unavailable — hard-reload the page (Ctrl+F5).');
    }
  }

  Future<void> _startCamera() async {
    try {
      List<String> devices = await _flutterLiteCameraPlugin.getDeviceList();
      if (devices.isEmpty) {
        debugPrint('No camera devices found. On an emulator, enable a '
            'webcam/virtual scene in the AVD settings.');
        return;
      }
      debugPrint("Available Devices: $devices");
      debugPrint("Opening camera 0");
      bool opened = await _flutterLiteCameraPlugin.open(0);
      if (!opened) {
        // false = permission denied or the device is busy/unavailable.
        debugPrint("Failed to open the camera.");
        return;
      }
      // The native layer renders the video feed into this texture; no
      // frame data crosses into Dart for display purposes.
      setState(() => _status = 'Loading barcode engine…');
    int textureId = await _flutterLiteCameraPlugin.startPreview();
      int rotation = 0;
      try {
        rotation = await _flutterLiteCameraPlugin.getRotation();
      } catch (e) {
        debugPrint("getRotation failed, assuming 0: $e");
      }
      // The plugin negotiates the actual frame size with the device; read it
      // back instead of assuming a fixed resolution.
      int width = await _flutterLiteCameraPlugin.getWidth();
      int height = await _flutterLiteCameraPlugin.getHeight();
      debugPrint("Negotiated frame size: ${width}x$height, rotation $rotation");
      setState(() {
        _isCameraOpened = true;
        _textureId = textureId;
        if (width > 0 && height > 0) {
          _width = width;
          _height = height;
        }
        _rotation = rotation;
        _shouldDecode = true;
        _status = 'Scanning for barcodes…';
      });

      // Start pulling frames for barcode decoding only. This does not
      // affect the preview stream.
      _decodeFrames();

      // Honor a preset chosen before the camera was opened (open()
      // negotiates the medium target by default).
      if (_preset != ResolutionPreset.medium) {
        await _applyResolution(_preset);
      }
    } catch (e) {
      reportDemoAction('camera_error', {'message': '$e'});
      debugPrint("Error initializing camera: $e");
    }
  }

  Future<void> _applyResolution(ResolutionPreset preset) async {
    setState(() => _preset = preset);
    bool ok = await _flutterLiteCameraPlugin.setResolutionPreset(preset);
    if (!ok) {
      debugPrint("setResolutionPreset($preset) failed.");
      return;
    }
    // The device may have fallen back to a different size; read the actual
    // one so the preview aspect ratio and overlay stay correct.
    int width = await _flutterLiteCameraPlugin.getWidth();
    int height = await _flutterLiteCameraPlugin.getHeight();
    debugPrint("Resolution after $preset: ${width}x$height");
    if (width > 0 && height > 0) {
      setState(() {
        _width = width;
        _height = height;
      });
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

          // The first wasm decode can take tens of seconds on a slow
          // machine. Without a timeout a stalled call would leave
          // isDecoding true forever and stop the loop.
          final ret = await _barcodeReader!
              .decodeImageBuffer(
                rgbBuffer,
                _width,
                _height,
                _width * 3,
                ImagePixelFormat.IPF_RGB_888.index,
                ImageRotation.rotation0.value,
              )
              .timeout(const Duration(seconds: 30));

          if (ret.isNotEmpty && !_reportedFirstScan) {
            _reportedFirstScan = true;
            reportDemoScan('camera');
          }

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
        _reportedFirstScan = false;
        results = null;
        _status = 'Starting camera…';
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

                // When the preview is rotated 90/270 degrees the displayed
                // frame becomes portrait, so the aspect ratio flips. Fall
                // back to 4:3 until the first frame reports its real size.
                final frameWidth = _width > 0 ? _width : 4;
                final frameHeight = _height > 0 ? _height : 3;
                final rotated = _rotation % 180 == 90;
                final imageAspectRatio = rotated
                    ? frameHeight / frameWidth
                    : frameWidth / frameHeight;
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
                        // Rotate only the widget — never the native pixels —
                        // so the preview appears upright without any per-frame
                        // buffer processing.
                        RotatedBox(
                          quarterTurns: (_rotation ~/ 90) % 4,
                          child: _flutterLiteCameraPlugin
                              .buildPreview(_textureId),
                        ),
                        CustomPaint(
                          painter: ResultPainter(
                            results ?? [],
                            srcWidth: frameWidth,
                            srcHeight: frameHeight,
                            drawWidth: drawWidth,
                            drawHeight: drawHeight,
                            rotation: _rotation,
                          ),
                          child: Container(),
                        ),
                        // Status pill: the wasm engine needs a few seconds to
                        // load, so say so instead of showing an empty overlay.
                        if (_isCameraOpened &&
                            (results == null || results!.isEmpty))
                          Positioned(
                            left: 12,
                            right: 12,
                            top: 12,
                            child: IgnorePointer(
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    _status,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                  ),
                                ),
                              ),
                            ),
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
                // Resolution preset selector
                Expanded(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<ResolutionPreset>(
                        value: _preset,
                        underline: const SizedBox.shrink(),
                        isExpanded: true,
                        onChanged: (preset) {
                          if (preset == null) return;
                          if (_isCameraOpened) {
                            _applyResolution(preset);
                          } else {
                            setState(() => _preset = preset);
                          }
                        },
                        items: ResolutionPreset.values
                            .map((p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(
                                    '${p.name} (${p.width}x${p.height})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
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
  final int srcWidth;
  final int srcHeight;
  final double drawWidth;
  final double drawHeight;
  final int rotation;

  ResultPainter(
    this.results, {
    required this.srcWidth,
    required this.srcHeight,
    required this.drawWidth,
    required this.drawHeight,
    required this.rotation,
  });

  /// Maps a point from source-frame coordinates to the displayed (possibly
  /// rotated) canvas, so overlay boxes align with the upright preview even
  /// when the texture is rotated by [rotation] degrees clockwise.
  Offset _transform(double x, double y) {
    final q = (rotation ~/ 90) % 4;
    switch (q) {
      case 1: // 90° clockwise
        final nx = srcHeight - y;
        final ny = x;
        return Offset(nx * drawWidth / srcHeight, ny * drawHeight / srcWidth);
      case 2: // 180°
        final nx = srcWidth - x;
        final ny = srcHeight - y;
        return Offset(nx * drawWidth / srcWidth, ny * drawHeight / srcHeight);
      case 3: // 270° clockwise (90° counter-clockwise)
        final nx = y;
        final ny = srcWidth - x;
        return Offset(nx * drawWidth / srcHeight, ny * drawHeight / srcWidth);
      default: // 0°
        return Offset(x * drawWidth / srcWidth, y * drawHeight / srcHeight);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (results.isEmpty) return;

    final textPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (var result in results) {
      final a = _transform(result.x1.toDouble(), result.y1.toDouble());
      final b = _transform(result.x2.toDouble(), result.y2.toDouble());
      final c = _transform(result.x3.toDouble(), result.y3.toDouble());
      final d = _transform(result.x4.toDouble(), result.y4.toDouble());

      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(c.dx, c.dy)
        ..lineTo(d.dx, d.dy)
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
      textPainter.paint(canvas, a);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
