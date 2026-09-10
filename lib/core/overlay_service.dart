import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../overlay/overlay_widget.dart';

/// Popup RobotAI melayang (SYSTEM_ALERT_WINDOW).
class OverlayService {
  static Future<bool> ensurePermission() async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!granted) {
      await FlutterOverlayWindow.requestPermission();
      return await FlutterOverlayWindow.isPermissionGranted();
    }
    return true;
  }

  static Future<void> show() async {
    if (!await ensurePermission()) return;
    if (await FlutterOverlayWindow.isActive()) return;
    await FlutterOverlayWindow.showOverlay(
      enableDrag: true,
      overlayTitle: 'JARVIS standby',
      overlayContent: 'Tap untuk perintah suara',
      flag: OverlayFlag.defaultFlag,
      visibility: NotificationVisibility.visibilityPublic,
      positionGravity: PositionGravity.right,
      height: 220,
      width: 200,
      startPosition: const OverlayPosition(0, -200),
    );
  }

  static Future<void> hide() async {
    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.closeOverlay();
    }
  }
}

// Supaya file overlay_widget terdaftar saat compile overlay entry-point.
void _keepOverlayImportAlive() => overlayMain();
