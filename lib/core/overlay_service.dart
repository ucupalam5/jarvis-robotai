import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_controller.dart';

/// Pilihan ikon popup robot (harus sama dengan drawable native:
/// ic_ov_<key>.xml di android/.../res/drawable).
const Map<String, IconData> popupIcons = {
  'robot': Icons.smart_toy,
  'bolt': Icons.bolt,
  'eye': Icons.visibility,
  'chip': Icons.memory,
};

/// Popup RobotAI melayang — dirender NATIVE (JarvisOverlayService),
/// tanpa plugin overlay. Ikon/warna/teks/gambar dibaca service dari
/// SharedPreferences setiap show(), jadi save = tampil ulang = tampilan baru.
class OverlayService {
  static const String kIcon = 'popup_icon';
  static const String kColor = 'popup_color';
  static const String kTitle = 'popup_title';
  static const String kImage = 'popup_image'; // path file galeri, '' = ikon
  static const String kAuto = 'popup_autolisten'; // bool: dengar tanpa tap
  static const String kEnabled = 'popup_enabled'; // bool: popup boleh tampil

  static const String defaultIcon = 'robot';
  static const String defaultColor = '00D4FF';
  static const String defaultTitle = 'jarvis';

  static Future<bool> isEnabled() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getBool(kEnabled) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(bool on) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(kEnabled, on);
    if (!on) await hide();
  }

  /// Izin overlay sistem. Bila belum ada, buka halaman izin agar user
  /// aktifkan manual, lalu kembalikan false (tap popup sekali lagi).
  static Future<bool> ensurePermission() async {
    try {
      if (await AppController.overlayPerm() == 'YA') return true;
      await AppController.overlayRequest();
      return await AppController.overlayPerm() == 'YA';
    } catch (_) {
      return false;
    }
  }

  /// true bila popup benar-benar tampil (dicek ulang setelah jeda).
  static Future<bool> show() async {
    if (!await isEnabled()) return false;
    if (!await ensurePermission()) return false;
    final r = await AppController.overlayShow();
    if (r != 'OK') return false;
    await Future.delayed(const Duration(milliseconds: 1800));
    return await AppController.overlayActive() == 'YA';
  }

  static Future<void> hide() async {
    await AppController.overlayHide();
  }

  /// Status jujur untuk ditampilkan di dialog setting.
  static Future<Map<String, bool>> overlayStatus() async {
    bool active = false;
    bool perm = false;
    try {
      active = await AppController.overlayActive() == 'YA';
    } catch (_) {}
    try {
      perm = await AppController.overlayPerm() == 'YA';
    } catch (_) {}
    return {'active': active, 'permission': perm};
  }

  /// Simpan config + tampilkan ulang bila popup sedang aktif.
  static Future<void> pushConfig() async {
    try {
      if (!await isEnabled()) {
        await hide();
        return;
      }
      if (await AppController.overlayActive() == 'YA') {
        await AppController.overlayShow();
      }
    } catch (_) {}
  }

  static Future<Map<String, String>> readConfig() async {
    final sp = await SharedPreferences.getInstance();
    return {
      'icon': sp.getString(kIcon) ?? defaultIcon,
      'color': sp.getString(kColor) ?? defaultColor,
      'title': sp.getString(kTitle) ?? defaultTitle,
      'image': sp.getString(kImage) ?? '',
      'auto': (sp.getBool(kAuto) ?? false) ? '1' : '0',
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

  /// Nyalakan/matikan auto-dengar popup (service baca saat restart).
  static Future<void> saveAutolisten(bool on) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(kAuto, on);
    await pushConfig();
  }
}
