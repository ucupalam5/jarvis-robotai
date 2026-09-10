import 'dart:convert';

import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../overlay/overlay_widget.dart';

/// Popup RobotAI melayang (SYSTEM_ALERT_WINDOW).
/// Ikon/warna/teks bisa diganti dari Settings di aplikasi utama,
/// overlay ikut update live via shareData (tanpa restart popup).
class OverlayService {
  static const String kIcon = 'popup_icon';
  static const String kColor = 'popup_color';
  static const String kTitle = 'popup_title';
  static const String kImage = 'popup_image'; // path file galeri, '' = pakai ikon

  static const String defaultIcon = 'robot';
  static const String defaultColor = '00D4FF';
  static const String defaultTitle = 'JARVIS standby...';

  static Future<bool> ensurePermission() async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!granted) {
      await FlutterOverlayWindow.requestPermission();
      return await FlutterOverlayWindow.isPermissionGranted();
    }
    return true;
  }

  /// true bila popup benar-benar tampil. false = izin overlay belum diberi.
  static Future<bool> show() async {
    if (!await ensurePermission()) return false;
    if (await FlutterOverlayWindow.isActive()) {
      // Sudah aktif: kirim config terbaru saja biar tampilannya refresh.
      await pushConfig();
      return true;
    }
    try {
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
    } catch (_) {
      return false;
    }
    // Kirim tampilan tersimpan begitu overlay siap.
    Future.delayed(const Duration(seconds: 1), pushConfig);
    return await FlutterOverlayWindow.isActive();
  }

  static Future<void> hide() async {
    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.closeOverlay();
    }
  }

  /// Baca config tersimpan lalu kirim ke overlay sebagai JSON string.
  static Future<void> pushConfig() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final data = jsonEncode({
        'icon': sp.getString(kIcon) ?? defaultIcon,
        'color': sp.getString(kColor) ?? defaultColor,
        'title': sp.getString(kTitle) ?? defaultTitle,
        'image': sp.getString(kImage) ?? '',
      });
      await FlutterOverlayWindow.shareData(data);
    } catch (_) {}
  }

  static Future<Map<String, String>> readConfig() async {
    final sp = await SharedPreferences.getInstance();
    return {
      'icon': sp.getString(kIcon) ?? defaultIcon,
      'color': sp.getString(kColor) ?? defaultColor,
      'title': sp.getString(kTitle) ?? defaultTitle,
      'image': sp.getString(kImage) ?? '',
    };
  }

  static Future<void> saveConfig(
      {required String icon,
      required String color,
      required String title,
      String image = ''}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(kIcon, icon);
    await sp.setString(kColor, color);
    await sp.setString(kTitle, title);
    await sp.setString(kImage, image);
    await pushConfig();
  }
}

// Supaya file overlay_widget terdaftar saat compile overlay entry-point.
void _keepOverlayImportAlive() => overlayMain();
