// Entry point overlay - widget robot melayang di atas aplikasi lain.
// Dipanggil oleh flutter_overlay_window via @pragma('vm:entry-point').
// Tampilan (ikon/warna/teks) dibaca dari SharedPreferences + live-update
// lewat FlutterOverlayWindow.shareData (JSON string).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma("vm:entry-point")
void overlayMain() {
  runApp(const JarvisOverlayApp());
}

/// Pilihan ikon popup. Key disimpan di prefs; tambah di sini + di Settings
/// aplikasi utama kalau mau ikon baru.
const Map<String, IconData> popupIcons = {
  'robot': Icons.smart_toy,
  'android': Icons.android,
  'bolt': Icons.bolt,
  'eye': Icons.visibility,
  'chip': Icons.memory,
  'orb': Icons.album,
};

Color _hexColor(String hex, {Color fallback = const Color(0xFF00D4FF)}) {
  try {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  } catch (_) {
    return fallback;
  }
}

class JarvisOverlayApp extends StatefulWidget {
  const JarvisOverlayApp({super.key});

  @override
  State<JarvisOverlayApp> createState() => _JarvisOverlayAppState();
}

class _JarvisOverlayAppState extends State<JarvisOverlayApp> {
  String _icon = 'robot';
  String _color = '00D4FF';
  String _title = 'JARVIS standby...';

  @override
  void initState() {
    super.initState();
    _loadSaved();
    // Live update saat user ganti setting di aplikasi utama.
    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is String && event.isNotEmpty) {
        try {
          final m = jsonDecode(event) as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              _icon = (m['icon'] as String?) ?? _icon;
              _color = (m['color'] as String?) ?? _color;
              _title = (m['title'] as String?) ?? _title;
            });
          }
        } catch (_) {}
      }
    });
  }

  Future<void> _loadSaved() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _icon = sp.getString('popup_icon') ?? _icon;
          _color = sp.getString('popup_color') ?? _color;
          _title = sp.getString('popup_title') ?? _title;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final accent = _hexColor(_color);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Container(
            width: 180,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xCC0A1628),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.5),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: accent, width: 2),
                  ),
                  child: Icon(popupIcons[_icon] ?? Icons.smart_toy,
                      color: accent, size: 36),
                ),
                const SizedBox(height: 8),
                Text(
                  _title,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: accent, fontSize: 12),
                ),
                const Text(
                  'Tap untuk bicara',
                  style: TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
