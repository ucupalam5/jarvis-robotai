import 'package:flutter/material.dart';
import 'core/groq_service.dart';
import 'core/voice_service.dart';
import 'ui/home_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await voice.initTts();
    await voice.initStt();
    // API key dibaca dari TextField di Home (disimpan SharedPreferences).
    // Default kosong -> user isi di Settings.
    groq = GroqService('');
    setState(() => ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
      );
    }
    return HomeScreen(voice: voice, groq: groq!);
  }
}
