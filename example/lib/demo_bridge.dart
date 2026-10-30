/// License and analytics bridge for the example app.
///
/// The hosted demo at `dynamsoft.com/codepool/demos/flutter-camera-barcode-scanner/`
/// injects `window.FLUTTER_LITE_CAMERA_LICENSE` from `web/index.html`, which
/// switches between two keys: the Codepool license (bound to dynamsoft.com, so
/// the demo runs with no sign-up) and the public trial key used everywhere else.
/// Native builds keep the compiled-in trial key.
library;

export 'demo_bridge_stub.dart'
    if (dart.library.js_interop) 'demo_bridge_web.dart';
