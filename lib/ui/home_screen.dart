import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_controller.dart';
import '../core/command_parser.dart';
import '../core/groq_service.dart';
import '../core/overlay_service.dart';
import '../core/voice_service.dart';
import '../overlay/overlay_widget.dart' show popupIcons;
import 'jarvis_orb.dart';

class ChatMsg {
  final String who; // 'user' | 'jarvis'
  final String text;
  ChatMsg(this.who, this.text);
}

class HomeScreen extends StatefulWidget {
  final VoiceService voice;
  final GroqService groq;
  const HomeScreen({super.key, required this.voice, required this.groq});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<ChatMsg> _chat = [ChatMsg('jarvis', 'Halo Sir, saya JARVIS. Tap orb dan bicara, Sir. Contoh: "buka WhatsApp", "kunci layar".')];
  final List<Map<String, String>> _history = [];
  bool _listening = false;
  bool _speaking = false;
  bool _busy = false;
  String _draft = '';
  final _apiCtrl = TextEditingController();
  final _scroll = ScrollController();
  String _popIcon = OverlayService.defaultIcon;
  String _popColor = OverlayService.defaultColor;
  final _popTitleCtrl = TextEditingController();

  static const List<String> _popColors = [
    '00D4FF', // cyan Jarvis
    '00FF9D', // hijau
    'FFB300', // oranye
    'FF4D6D', // merah muda
    'B388FF', // ungu
  ];

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  Future<void> _loadKey() async {
    final sp = await SharedPreferences.getInstance();
    final k = sp.getString('groq_key') ?? '';
    widget.groq.apiKey = k;
    _apiCtrl.text = k;
    final pop = await OverlayService.readConfig();
    _popIcon = pop['icon'] ?? _popIcon;
    _popColor = pop['color'] ?? _popColor;
    _popTitleCtrl.text = pop['title'] ?? '';
    setState(() {});
  }

  Future<void> _saveKey() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('groq_key', _apiCtrl.text.trim());
    widget.groq.apiKey = _apiCtrl.text.trim();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API key Groq tersimpan, Sir.')),
      );
    }
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _handleText(String text) async {
    if (text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _chat.add(ChatMsg('user', text));
    });
    _scrollDown();

    // 1) Coba perintah lokal (buka/tutup app, kunci layar, dsb) -> cepat, offline.
    final cmd = parseLocalCommand(text);
    String reply;
    if (cmd.handledLocally) {
      reply = cmd.reply;
      if (cmd.action != null) {
        final res = await cmd.action!();
        if (res.startsWith('BATERAI_REPLY:')) {
          reply = res.substring('BATERAI_REPLY:'.length);
        } else if (res != 'OK') {
          reply = '$reply (catatan: $res)';
        }
      }
    } else {
      // 2) Selain itu -> tanya ke Groq AI.
      reply = await widget.groq.chat(text, _history);
      _history.add({'role': 'user', 'content': text});
      _history.add({'role': 'assistant', 'content': reply});
    }

    setState(() {
      _chat.add(ChatMsg('jarvis', reply));
      _busy = false;
    });
    _scrollDown();
    setState(() => _speaking = true);
    await widget.voice.speak(reply);
    if (mounted) setState(() => _speaking = false);
  }

  Future<void> _tapOrb() async {
    if (_listening) {
      await widget.voice.stopListen();
      setState(() => _listening = false);
      return;
    }
    await widget.voice.stopSpeak();
    setState(() {
      _listening = true;
      _draft = 'Mendengarkan...';
    });
    await widget.voice.listenOnce(onResult: (txt, finalR) async {
      setState(() => _draft = txt.isEmpty ? 'Mendengarkan...' : txt);
      if (finalR) {
        await widget.voice.stopListen();
        if (mounted) setState(() => _listening = false);
        if (txt.trim().isNotEmpty) await _handleText(txt);
      }
    });
    // timeout pengaman 16 detik
    Future.delayed(const Duration(seconds: 16), () async {
      if (_listening && mounted) {
        await widget.voice.stopListen();
        setState(() => _listening = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('J.A.R.V.I.S  •  RobotAI',
            style: TextStyle(color: Colors.cyanAccent, letterSpacing: 1.2)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_in_picture, color: Colors.cyanAccent),
            tooltip: 'Popup robot',
            onPressed: () async {
              await OverlayService.show();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Popup Jarvis aktif, Sir. Bisa digeser-geser.')));
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.tune, color: Colors.cyanAccent),
            tooltip: 'Setting ikon popup',
            onPressed: _openPopupSettings,
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.cyanAccent),
            onPressed: _openSettings,
            tooltip: 'API Key Groq',
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _busy ? null : _tapOrb,
            child: JarvisOrb(listening: _listening, speaking: _speaking),
          ),
          const SizedBox(height: 6),
          Text(
            _busy
                ? 'Processing...'
                : _listening
                    ? (_draft.isEmpty ? 'Mendengarkan...' : '“$_draft”')
                    : 'TAP ORB UNTUK BICARA',
            style: const TextStyle(color: Colors.cyanAccent, fontSize: 13),
          ),
          const SizedBox(height: 8),
          // Tombol cepat
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _quick('Buka WA', () => _handleText('buka whatsapp')),
                _quick('Buka YT', () => _handleText('buka youtube')),
                _quick('Tutup app', () => AppController.closeApp()),
                _quick('Home', () => AppController.goHome()),
                _quick('Kunci layar', () => _handleText('kunci layar')),
                _quick('Nyalakan layar', () => _handleText('nyalakan layar')),
                _quick('Senter ON', () => _handleText('nyalakan senter')),
              ],
            ),
          ),
          const Divider(color: Colors.cyanAccent),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _chat.length,
              itemBuilder: (_, i) {
                final m = _chat[i];
                final isUser = m.who == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(10),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.8),
                    decoration: BoxDecoration(
                      color: isUser
                          ? const Color(0xFF00D4FF).withOpacity(0.2)
                          : const Color(0xFF0E1E3A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isUser ? Colors.cyanAccent : Colors.blueGrey),
                    ),
                    child: Text(m.text,
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _quick(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: OutlinedButton(
        onPressed: _busy ? null : onTap,
        style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.cyanAccent)),
        child: Text(label, style: const TextStyle(color: Colors.cyanAccent, fontSize: 12)),
      ),
    );
  }

  void _openPopupSettings() {
    String selIcon = _popIcon;
    String selColor = _popColor;
    final titleCtrl = TextEditingController(text: _popTitleCtrl.text);
    Color hex(String h) {
      try {
        return Color(int.parse('FF${h.replaceAll('#', '')}', radix: 16));
      } catch (_) {
        return Colors.cyanAccent;
      }
    }

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF0A1628),
          title: const Text('Ikon Popup Robot',
              style: TextStyle(color: Colors.cyanAccent)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pilih ikon:',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: popupIcons.entries.map((e) {
                    final sel = selIcon == e.key;
                    return GestureDetector(
                      onTap: () => setD(() => selIcon = e.key),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: sel
                              ? hex(selColor).withOpacity(0.25)
                              : Colors.white10,
                          border: Border.all(
                              color: sel ? hex(selColor) : Colors.white24,
                              width: sel ? 2 : 1),
                        ),
                        child: Icon(e.value,
                            color: sel ? hex(selColor) : Colors.white70),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                const Text('Pilih warna:',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: _popColors.map((c) {
                    final sel = selColor == c;
                    return GestureDetector(
                      onTap: () => setD(() => selColor = c),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hex(c),
                          border: Border.all(
                              color: sel ? Colors.white : Colors.transparent,
                              width: 2),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                const Text('Teks popup:',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: titleCtrl,
                  maxLength: 30,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'JARVIS standby...',
                    hintStyle: TextStyle(color: Colors.white30),
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.cyanAccent)),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.cyanAccent)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal')),
            ElevatedButton(
                onPressed: () async {
                  final title = titleCtrl.text.trim().isEmpty
                      ? OverlayService.defaultTitle
                      : titleCtrl.text.trim();
                  await OverlayService.saveConfig(
                      icon: selIcon, color: selColor, title: title);
                  if (mounted) {
                    setState(() {
                      _popIcon = selIcon;
                      _popColor = selColor;
                      _popTitleCtrl.text = title;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Ikon popup tersimpan, Sir.')));
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save')),
          ],
        ),
      ),
    );
  }

  void _openSettings() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0A1628),
        title: const Text('Groq API Key (gratis)',
            style: TextStyle(color: Colors.cyanAccent)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '1. Buka console.groq.com\n2. Create API Key gratis\n3. Paste ke sini, Save.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _apiCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'gsk_...',
                hintStyle: TextStyle(color: Colors.white30),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.cyanAccent)),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.cyanAccent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          ElevatedButton(
              onPressed: () {
                _saveKey();
                Navigator.pop(context);
              },
              child: const Text('Save')),
        ],
      ),
    );
  }
}
