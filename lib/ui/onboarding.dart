import 'package:flutter/material.dart';

/// Tur pertama kali buka app: kunci API, bicara, popup + izin.
/// Ditampilkan sekali (prefs onboarded), bisa diulang dari Settings.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _i = 0;

  static const _pages = [
    (
      Icons.key,
      '1. Pasang Otak AI',
      'Daftar gratis di console.groq.com > API Keys > Create.\nCopy key gsk_... > Settings (ikon gear) > paste > Save.\nBanner hijau VALID = siap.',
    ),
    (
      Icons.mic,
      '2. Bicara Bahasa Indonesia',
      'Tap orb > izinkan Microphone > bicara.\nContoh: "buka whatsapp", "kunci layar",\n"berapa 12 kali 3", "catat beli susu".\nBar level = bukti mic hidup.',
    ),
    (
      Icons.smart_toy,
      '3. Popup + Otomatisasi',
      'Tombol popup > izinkan overlay > robot melayang.\nAuto-dengar = dengar sendiri tanpa tap.\nAktifkan Aksesibilitas Jarvis untuk tap/ketik otomatis.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050B18),
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onDone,
                child: const Text('Lewati',
                    style: TextStyle(color: Colors.white54)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _i = i),
                itemBuilder: (_, i) {
                  final (icon, title, body) = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.cyanAccent, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.cyanAccent.withOpacity(0.4),
                                blurRadius: 25,
                              ),
                            ],
                          ),
                          child: Icon(icon,
                              color: Colors.cyanAccent, size: 48),
                        ),
                        const SizedBox(height: 24),
                        Text(title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Text(body,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                height: 1.5)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (i) => Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _i ? Colors.cyanAccent : Colors.white24,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (_i < _pages.length - 1) {
                      _page.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut);
                    } else {
                      widget.onDone();
                    }
                  },
                  child:
                      Text(_i < _pages.length - 1 ? 'Lanjut' : 'Mulai, Sir'),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
