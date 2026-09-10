// Entry point overlay "TrueCaller style" - widget kecil yang melayang di atas aplikasi lain.
// Dipanggil oleh flutter_overlay_window via @pragma('vm:entry-point')
import 'package:flutter/material.dart';

@pragma("vm:entry-point")
void overlayMain() {
  runApp(const JarvisOverlayApp());
}

class JarvisOverlayApp extends StatelessWidget {
  const JarvisOverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
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
              border: Border.all(color: const Color(0xFF00D4FF), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00D4FF).withOpacity(0.5),
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
                    border: Border.all(color: const Color(0xFF00D4FF), width: 2),
                  ),
                  child: const Icon(Icons.smart_toy,
                      color: Color(0xFF00D4FF), size: 36),
                ),
                const SizedBox(height: 8),
                const Text(
                  'JARVIS standby...',
                  style: TextStyle(color: Colors.cyanAccent, fontSize: 12),
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
