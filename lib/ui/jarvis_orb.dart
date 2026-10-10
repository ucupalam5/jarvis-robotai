import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Status orb JARVIS.
enum OrbState {
  idle, // denyut pelan, cyan
  listening, // merah/orange, cepat (mendengar user)
  thinking, // ungu, putar (mikir / hubungi AI)
  speaking, // cyan terang + waveform (bicara)
  wake, // kilatan putih (wake word terdeteksi)
}

/// Orb reaktif: warna + kecepatan + efek berubah sesuai status.
class JarvisOrb extends StatefulWidget {
  final OrbState state;
  final double level; // level mic 0..1 (untuk efek speaking/listening)
  const JarvisOrb({super.key, required this.state, this.level = 0});

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
  void didUpdateWidget(JarvisOrb old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      // Kecepatan animasi mengikuti status.
      final d = switch (widget.state) {
        OrbState.idle => const Duration(seconds: 4),
        OrbState.listening => const Duration(milliseconds: 900),
        OrbState.thinking => const Duration(seconds: 2),
        OrbState.speaking => const Duration(milliseconds: 600),
        OrbState.wake => const Duration(milliseconds: 400),
      };
      _c.duration = d;
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return CustomPaint(
          size: const Size(220, 220),
          painter: _OrbPainter(
            progress: _c.value,
            state: widget.state,
            level: widget.level,
          ),
        );
      },
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double progress;
  final OrbState state;
  final double level;

  _OrbPainter(
      {required this.progress, required this.state, required this.level});

  Color get _color => switch (state) {
        OrbState.idle => Colors.cyanAccent,
        OrbState.listening => Colors.redAccent,
        OrbState.thinking => Colors.deepPurpleAccent,
        OrbState.speaking => Colors.lightBlueAccent,
        OrbState.wake => Colors.white,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final baseR = size.width / 2 - 14;
    // Denyut: idle pelan, lainnya lebih agresif + ikut level mic.
    final pulseAmp = switch (state) {
      OrbState.idle => 4.0,
      OrbState.listening => 6.0 + level * 14,
      OrbState.thinking => 8.0,
      OrbState.speaking => 5.0 + level * 18,
      OrbState.wake => 12.0,
    };
    final pulse = math.sin(progress * math.pi * 2) * pulseAmp;

    // Glow luar.
    final glow = Paint()
      ..color = _color.withOpacity(0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(c, baseR + pulse + 10, glow);

    // Ring luar berputar (thinking: dua ring).
    final ringPaint = Paint()
      ..color = _color.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final sweep = math.pi * 2 * progress;
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: baseR + pulse), sweep, math.pi * 1.2, false, ringPaint);
    if (state == OrbState.thinking) {
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: baseR + pulse - 10),
          -sweep,
          math.pi * 0.8,
          false,
          ringPaint);
    }

    // Inti orb.
    final core = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, _color.withOpacity(0.85), _color.withOpacity(0.25)],
      ).createShader(Rect.fromCircle(center: c, radius: baseR * 0.62 + pulse / 2));
    canvas.drawCircle(c, baseR * 0.62 + pulse / 2, core);

    // Waveform saat speaking: garis-garis di sekeliling inti.
    if (state == OrbState.speaking) {
      final wave = Paint()
        ..color = Colors.white.withOpacity(0.8)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 24; i++) {
        final a = i / 24 * math.pi * 2;
        final wob = math.sin(a * 3 + progress * math.pi * 4) *
            (4 + level * 12);
        final r1 = baseR * 0.66 + pulse / 2;
        final r2 = r1 + 6 + wob;
        canvas.drawLine(
          c + Offset(math.cos(a) * r1, math.sin(a) * r1),
          c + Offset(math.cos(a) * r2, math.sin(a) * r2),
          wave,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.progress != progress ||
      old.state != state ||
      old.level != level;
}
