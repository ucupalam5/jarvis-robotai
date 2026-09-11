import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/groq_service.dart';
import 'core/voice_service.dart';
import 'ui/home_screen.dart';
import 'ui/onboarding.dart';

/// Tema layar loading. Bisa diganti di Settings > Tampilan.
/// key prefs: loading_theme ('cyan' | 'green' | 'orange')
const Map<String, Map<String, Color>> loadingThemes = {
  'cyan': {
    'bg': Color(0xFF050B18),
    'accent': Color(0xFF00D4FF),
  },
  'green': {
    'bg': Color(0xFF04120C),
    'accent': Color(0xFF00FF9D),
  },
  'orange': {
    'bg': Color(0xFF160B04),
    'accent': Color(0xFFFFB300),
  },
};

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JarvisApp());
}

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JARVIS RobotAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF050B18),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00D4FF),
          secondary: Color(0xFF00D4FF),
        ),
        useMaterial3: true,
      ),
      home: const JarvisBootstrap(),
    );
  }
}

/// Load API key tersimpan lalu buka Home.
class JarvisBootstrap extends StatefulWidget {
  const JarvisBootstrap({super.key});
  @override
  State<JarvisBootstrap> createState() => _JarvisBootstrapState();
}

class _JarvisBootstrapState extends State<JarvisBootstrap> {
  final voice = VoiceService();
  GroqService? groq;
  bool ready = false;
  bool showOnboarding = false;
  String themeKey = 'cyan';
  String loadingBg = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Baca tema loading dulu agar tampil sesuai pilihan user.
    try {
      final sp = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));
      final t = sp.getString('loading_theme') ?? 'cyan';
      if (loadingThemes.containsKey(t) && mounted) {
        setState(() => themeKey = t);
      }
      final bg = sp.getString('loading_bg') ?? '';
      if (bg.isNotEmpty && File(bg).existsSync() && mounted) {
        setState(() => loadingBg = bg);
      }
      if (mounted && !(sp.getBool('onboarded') ?? false)) {
        setState(() => showOnboarding = true);
      }
    } catch (_) {}
    // FAILSAFE: apapun yang terjadi (STT/TTS macet di HP tertentu),
    // aplikasi wajib masuk Home maksimal 12 detik. Tidak boleh loading selamanya.
    Future.delayed(const Duration(seconds: 12), () {
      if (mounted && !ready) setState(() => ready = true);
    });
    try {
      await voice.initTts().timeout(const Duration(seconds: 8));
    } catch (_) {
      // TTS gagal -> app tetap jalan, Jarvis hanya tidak bersuara.
    }
    try {
      await voice.initStt().timeout(const Duration(seconds: 8));
    } catch (_) {
      // STT gagal -> app tetap jalan, user bisa ketik via tombol cepat.
    }
    // API key dibaca dari Settings di Home (disimpan SharedPreferences).
    // Default kosong -> user isi di Settings (ada banner penuntun).
    groq = GroqService('');
    if (mounted) setState(() => ready = true);
  }

  Future<void> _finishOnboarding() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('onboarded', true);
    } catch (_) {}
    if (mounted) setState(() => showOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      final th = loadingThemes[themeKey] ?? loadingThemes['cyan']!;
      final bgFile =
          loadingBg.isNotEmpty ? File(loadingBg) : null;
      final hasBg = bgFile != null && bgFile.existsSync();
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: th['bg'],
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: hasBg
                ? BoxDecoration(
                    image: DecorationImage(
                        image: FileImage(bgFile!), fit: BoxFit.cover),
                  )
                : null,
            child: Container(
              color: hasBg ? Colors.black.withOpacity(0.55) : null,
              child: Center(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: th['accent']!, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: th['accent']!.withOpacity(0.5),
                        blurRadius: 25,
                      ),
                    ],
                  ),
                  child: Icon(Icons.smart_toy,
                      color: th['accent'], size: 44),
                ),
                const SizedBox(height: 16),
                Text('J.A.R.V.I.S',
                    style: TextStyle(
                        color: th['accent'],
                        fontSize: 22,
                        letterSpacing: 4,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Menyiapkan sistem...',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 16),
                SizedBox(
                  width: 160,
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.white10,
                    color: th['accent'],
                  ),
                ),
              ],
            ),
          ),
            ),
          ),
        ),
      );
    }
    if (showOnboarding) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: OnboardingScreen(onDone: _finishOnboarding),
      );
    }
    return HomeScreen(voice: voice, groq: groq!);
  }
}
