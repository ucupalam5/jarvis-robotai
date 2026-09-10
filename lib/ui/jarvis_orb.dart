import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Orb Jarvis berdenyut (ala reactor Iron Man).
class JarvisOrb extends StatefulWidget {
  final bool listening;
  final bool speaking;
  const JarvisOrb({super.key, required this.listening, required this.speaking});

  @override
  State<JarvisOrb> createState() => _JarvisOrbState();
}

class _JarvisOrbState extends State<JarvisOrb>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.listening || widget.speaking;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return CustomPaint(
          size: const Size(220, 220),
          painter: _OrbPainter(
            progress: _c.value,
            color: widget.listening
                ? Colors.redAccent
                : widget.speaking
                    ? Colors.greenAccent
                    : const Color(0xFF00D4FF),
            active: active,
          ),
          child: SizedBox(
            width: 220,
            height: 220,
            child: Center(
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0A1628),
                  border: Border.all(
                      color: const Color(0xFF00D4FF).withOpacity(0.8), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00D4FF)
                          .withOpacity(active ? 0.9 : 0.4),
                      blurRadius: active ? 45 : 20,
                    ),
                  ],
                ),
                child: Icon(
                  widget.listening
                      ? Icons.mic
                      : widget.speaking
                          ? Icons.volume_up
                          : Icons.smart_toy,
                  color: Colors.cyanAccent,
                  size: 48,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool active;
  _OrbPainter({required this.progress, required this.color, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (int i = 0; i < 3; i++) {
      final p = (progress + i / 3) % 1.0;
      final r = 60 + p * 50;
      final paint = Paint()
        ..color = color.withOpacity((1 - p) * (active ? 0.8 : 0.4))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, r, paint);
      // tick ala HUD
      for (int k = 0; k < 24; k++) {
        final a = (k / 24) * math.pi * 2 + progress * math.pi * 2;
        final p1 = center + Offset(math.cos(a), math.sin(a)) * (r - 4);
        final p2 = center + Offset(math.cos(a), math.sin(a)) * (r + 4);
        canvas.drawLine(p1, p2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => true;
}
