import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_controller.dart';
import '../core/command_parser.dart';
import '../core/groq_service.dart';
import '../core/overlay_service.dart';
import '../core/voice_service.dart';
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final List<ChatMsg> _chat = [ChatMsg('jarvis', 'Halo Sir, saya JARVIS. Tap orb dan bicara, Sir. Contoh: "buka WhatsApp", "kunci layar".')];
  final List<Map<String, String>> _history = [];
  bool _listening = false;
  bool _speaking = false;
  bool _busy = false;
  String _draft = '';
  final _apiCtrl = TextEditingController();
  final _scroll = ScrollController();
  String _acc = '...';
  String _popIcon = OverlayService.defaultIcon;
  String _popColor = OverlayService.defaultColor;
  final _popTitleCtrl = TextEditingController();
  String _popImage = '';
  bool _popAuto = false;
  double _level = 0;
  bool _handsfree = false;
  bool _silent = false;
  String _keyCheck = ''; // '' | 'ok' | 'bad:pesan'

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
    WidgetsBinding.instance.addObserver(this);
    _loadKey();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_handsfree) {
      _handsfree = false;
      AppController.handsfreeWake(false);
    }
    super.dispose();
  }

  /// Dipanggil saat app kembali dibuka (misal dari tap popup robot).
  /// Kalau ada permintaan auto-dengar -> langsung dengar tanpa tap orb.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _consumeAutolisten();
    }
  }

  Future<void> _consumeAutolisten() async {
    try {
      if (await AppController.consumeAutolisten() != 'YA') return;
      if (!mounted || _busy || _listening || _handsfree) return;
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted || _busy || _listening) return;
      await widget.voice.stopSpeak();
      final mic = await AppController.requestMic();
      if (mic != 'OK' || !mounted) return;
      await _listenCycle();
    } catch (_) {}
  }

  /// Minta semua izin yang bisa diminta langsung saat awal buka app.
  /// (Overlay + Accessibility tetap via halaman sistem masing-masing.)
  Future<void> _requestStartupPermissions() async {
    try {
      await AppController.requestMic();
    } catch (_) {}
    try {
      await AppController.requestNotif();
    } catch (_) {}
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
    _popImage = pop['image'] ?? '';
    _popAuto = pop['auto'] == '1';
    setState(() {});
    _refreshAcc(silent: true);
    _checkKey(silent: true);
    _requestStartupPermissions();
    // Cek juga saat pertama buka (misal dibuka dari tap popup).
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _consumeAutolisten();
    });
  }

  /// Validasi API key ke server Groq. Hasil tampil sebagai banner.
  Future<void> _checkKey({bool silent = false}) async {
    final k = widget.groq.apiKey;
    if (k.isEmpty) {
      if (mounted) setState(() => _keyCheck = '');
      return;
    }
    if (mounted) setState(() => _keyCheck = 'cek');
    try {
      final (ok, msg) = await widget.groq.validateKey(k);
      if (mounted) setState(() => _keyCheck = ok ? 'ok' : 'bad:$msg');
      if (!silent && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) setState(() => _keyCheck = 'bad:Tidak bisa hubungi Groq: $e');
    }
  }

  Future<void> _refreshAcc({bool silent = false}) async {
    String s;
    try {
      s = await AppController.accCheck();
    } catch (e) {
      s = 'Gagal cek: $e';
    }
    if (mounted) setState(() => _acc = s);
    if (!silent && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Aksesibilitas: $s')));
    }
  }

  Future<void> _saveKey() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('groq_key', _apiCtrl.text.trim());
    widget.groq.apiKey = _apiCtrl.text.trim();
    if (mounted) setState(() {}); // refresh banner API key
    await _checkKey();
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
    final tl = text.toLowerCase().trim();
    // Mode senyap: Jarvis hanya teks, tanpa suara.
    if (tl == 'mode senyap' ||
        tl == 'senyap' ||
        tl.contains('mode senyap nyala') ||
        tl.contains('jangan bersuara')) {
      if (mounted) setState(() => _silent = true);
      await widget.voice.stopSpeak();
      if (mounted) {
        setState(() {
          _chat.add(ChatMsg('user', text));
          _chat.add(ChatMsg('jarvis', 'Mode senyap aktif, Sir. Saya hanya teks.'));
        });
      }
      _scrollDown();
      return;
    }
    if (tl == 'mode suara' ||
        tl.contains('mode senyap mati') ||
        tl.contains('bersuara lagi')) {
      if (mounted) setState(() => _silent = false);
      if (mounted) {
        setState(() {
          _chat.add(ChatMsg('user', text));
          _chat.add(ChatMsg('jarvis', 'Mode suara aktif, Sir.'));
        });
      }
      _scrollDown();
      await widget.voice.speak('Mode suara aktif, Sir.');
      return;
    }
    setState(() {
      _busy = true;
      _chat.add(ChatMsg('user', text));
    });
    _scrollDown();

    // 1) Coba perintah lokal (buka/tutup app, kunci layar, dsb) -> cepat, offline.
    final sp = await SharedPreferences.getInstance();
    final cmd = parseLocalCommand(text);
    String reply;
    if (cmd.handledLocally) {
      reply = cmd.reply;
      if (cmd.action != null) {
        final res = await cmd.action!();
        if (res.startsWith('SAY:')) {
          reply = res.substring('SAY:'.length);
        } else if (res.startsWith('BATERAI_REPLY:')) {
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
    if (_silent) {
      if (mounted) setState(() => _speaking = false);
      return;
    }
    setState(() => _speaking = true);
    await widget.voice.speak(reply);
    if (mounted) setState(() => _speaking = false);
  }

  Future<void> _tapOrb() async {
    // Saat handsfree ON, tap orb = matikan handsfree.
    if (_handsfree) {
      await _setHandsfree(false);
      return;
    }
    if (_listening) {
      await widget.voice.stopListen();
      if (mounted) {
        setState(() {
          _listening = false;
          _level = 0;
        });
      }
      return;
    }
    await widget.voice.stopSpeak();
    // Minta izin mic eksplisit (tanpa plugin tambahan) sebelum dengar.
    final mic = await AppController.requestMic();
    if (mic != 'OK') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(mic.startsWith('DENIED:')
              ? mic.substring('DENIED:'.length)
              : mic),
        ));
      }
      return;
    }
    await _listenCycle();
  }

  /// Nyalakan/matikan mode handsfree: dengar terus tanpa tap orb.
  /// Layar ditahan redup (wake lock) agar mic tetap hidup.
  /// Batas jujur: HP harus NYALA (standby). Mati total tidak bisa dengar.
  Future<void> _setHandsfree(bool on) async {
    if (on) {
      await widget.voice.stopSpeak();
      final mic = await AppController.requestMic();
      if (mic != 'OK') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(mic.startsWith('DENIED:')
                ? mic.substring('DENIED:'.length)
                : mic),
          ));
        }
        return;
      }
      if (mounted) setState(() => _handsfree = true);
      await AppController.handsfreeWake(true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            duration: Duration(seconds: 4),
            content: Text(
                'Handsfree ON, Sir. Bicara saja tanpa tap. Tap orb untuk berhenti.')));
      }
      _handsfreeLoop();
    } else {
      if (mounted) setState(() => _handsfree = false);
      try {
        await widget.voice.stopListen();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _listening = false;
          _level = 0;
        });
      }
      await AppController.handsfreeWake(false);
    }
  }

  Future<void> _handsfreeLoop() async {
    while (_handsfree && mounted) {
      if (!_busy && !_listening) {
        try {
          await _listenCycle();
        } catch (_) {}
      }
      await Future.delayed(const Duration(milliseconds: 800));
    }
  }

  /// Satu putaran dengar-proses. Dipakai tap orb maupun handsfree loop.
  Future<void> _listenCycle() async {
    setState(() {
      _listening = true;
      _draft = 'Mendengarkan...';
      _level = 0;
    });
    final start = DateTime.now();
    await widget.voice.listenOnce(onResult: (txt, finalR) async {
      if (!mounted) return;
      setState(() => _draft = txt.isEmpty ? 'Mendengarkan...' : txt);
      if (finalR) {
        await widget.voice.stopListen();
        if (mounted) setState(() {
          _listening = false;
          _level = 0;
        });
        if (txt.trim().isNotEmpty) {
          await _handleText(txt);
        } else if (!_handsfree &&
            DateTime.now().difference(start).inMilliseconds > 1500) {
          // Bukan tap-batal (user bicara tapi tak tertangkap): beri penuntun.
          final mic = await widget.voice.hasMicPermission;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              duration: const Duration(seconds: 5),
              content: Text(mic
                  ? 'Tidak dengar suara, Sir. Bicara lebih dekat + keras, atau install paket suara Indonesia di Settings HP > Bahasa.'
                  : 'Izin microphone ditolak, Sir. Buka Settings HP > Apps > JARVIS > Permissions > Microphone > Allow.'),
            ));
          }
        }
      }
    }, onLevel: (v) {
      // Meter mic: update hemat (hanya bila berubah cukup besar).
      if (mounted && (v - _level).abs() > 0.06) {
        setState(() => _level = v);
      }
    });
    // timeout pengaman 22 detik (listenFor 20 dtk + toleransi)
    Future.delayed(const Duration(seconds: 22), () async {
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
              final ok = await OverlayService.show();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    duration: const Duration(seconds: 5),
                    content: Text(ok
                        ? 'Popup Jarvis aktif, Sir. Bisa digeser-geser.'
                        : 'Popup gagal tampil, Sir. Aktifkan manual: Settings HP > Apps > JARVIS > Display over other apps > Allow.')));
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
          // Banner penuntun API key + tanda valid/tidaknya key.
          if (widget.groq.apiKey.isEmpty)
            GestureDetector(
              onTap: _openSettings,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orangeAccent),
                ),
                child: const Text(
                  '⚠ API key Groq belum dipasang, Sir.\nTap di sini > paste key gsk_... > Save.\nDaftar gratis: console.groq.com',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
                ),
              ),
            )
          else if (_keyCheck.startsWith('bad:'))
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent),
              ),
              child: Text(
                '✗ API key BERMASALAH, Sir.\n${_keyCheck.substring(4)}\nTap Settings untuk ganti.',
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            )
          else if (_keyCheck == 'ok')
            Container(
              width: double.infinity,
              margin:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.greenAccent),
              ),
              child: const Text(
                '✓ API key Groq VALID, Sir.',
                style: TextStyle(color: Colors.greenAccent, fontSize: 12),
              ),
            )
          else if (_keyCheck == 'cek')
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Mengecek API key ke Groq...',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ),
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
                    ? (_draft.isEmpty
                        ? 'Mendengarkan... bicara BAHASA INDONESIA, Sir.'
                        : '“$_draft”')
                    : (_handsfree
                        ? 'HANDSFREE ON — bicara saja, Sir.'
                        : 'TAP ORB BICARA / HANDSFREE MODE'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.cyanAccent, fontSize: 13),
          ),
          // Meter level mic: membuktikan mic hidup saat mendengarkan.
          if (_listening)
            Container(
              width: 200,
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                value: _level <= 0.01 ? null : _level,
                backgroundColor: Colors.white10,
                color: Colors.cyanAccent,
                minHeight: 4,
              ),
            ),
          const SizedBox(height: 8),
          // Status otomatisasi (tap = cek ulang, tahan = buka pengaturan).
          GestureDetector(
            onTap: () => _refreshAcc(),
            onLongPress: () async {
              await AppController.accOpenSettings();
              _refreshAcc();
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _acc == 'OK'
                    ? Colors.green.withOpacity(0.15)
                    : Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _acc == 'OK'
                        ? Colors.greenAccent
                        : Colors.orangeAccent),
              ),
              child: Text(
                _acc == 'OK'
                    ? '● Otomatisasi ON — tap cek, tahan buka pengaturan'
                    : '● Otomatisasi: $_acc',
                style:
                    const TextStyle(color: Colors.white70, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 4),
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
                _quick('Baterai', () => _handleText('baterai berapa')),
                _quick(_handsfree ? 'Handsfree ON' : 'Handsfree',
                    () => _setHandsfree(!_handsfree)),
                _quick(_silent ? 'Senyap ON' : 'Senyap', () {
                  if (_silent) {
                    _handleText('mode suara');
                  } else {
                    _handleText('mode senyap');
                  }
                }),
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
    String selImage = _popImage;
    bool selAuto = _popAuto;
    bool saving = false;
    int statusVer = 0;
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
                // Status real overlay: bukti popup hidup/mati + izin.
                FutureBuilder<Map<String, bool>>(
                  key: ValueKey(statusVer),
                  future: OverlayService.overlayStatus(),
                  builder: (c, snap) {
                    final st = snap.data;
                    final txt = st == null
                        ? 'Status popup: mengecek...'
                        : 'Status popup: ${st['active'] == true ? 'AKTIF ✓' : 'MATI ✗'} • Izin overlay: ${st['permission'] == true ? 'YA ✓' : 'BELUM ✗'}';
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(txt,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    );
                  },
                ),
                // Preview persis pilihan saat ini (bukti sebelum save).
                Center(
                  child: Builder(builder: (_) {
                    Color c;
                    try {
                      c = Color(int.parse(
                          'FF${selColor.replaceAll('#', '')}',
                          radix: 16));
                    } catch (_) {
                      c = Colors.cyanAccent;
                    }
                    Widget avatar;
                    if (selImage.isNotEmpty &&
                        File(selImage).existsSync()) {
                      avatar = Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: c, width: 2),
                          image: DecorationImage(
                              image: FileImage(File(selImage)),
                              fit: BoxFit.cover),
                        ),
                      );
                    } else {
                      avatar = Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: c, width: 2),
                        ),
                        child: Icon(popupIcons[selIcon] ?? Icons.smart_toy,
                            color: c, size: 32),
                      );
                    }
                    return Column(
                      children: [
                        avatar,
                        const SizedBox(height: 4),
                        const Text('Preview',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 11)),
                      ],
                    );
                  }),
                ),
                const SizedBox(height: 8),
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
                const SizedBox(height: 4),
                const Text('Atau gambar dari galeri (gantikan ikon):',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final r = await AppController.pickImage();
                          if (r == 'BATAL') return;
                          if (r.startsWith('/')) {
                            setD(() => selImage = r);
                          } else if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text(r)));
                          }
                        },
                        icon: const Icon(Icons.photo, size: 16),
                        label: Text(
                            selImage.isEmpty ? 'Dari galeri' : 'Ganti gambar',
                            style: const TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.cyanAccent,
                            side: const BorderSide(color: Colors.cyanAccent)),
                      ),
                    ),
                    if (selImage.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Hapus gambar, kembali ke ikon',
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.orangeAccent),
                        onPressed: () => setD(() => selImage = ''),
                      ),
                    ],
                  ],
                ),
                if (selImage.isNotEmpty)
                  const Text('✓ Gambar galeri dipilih.',
                      style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
                const SizedBox(height: 8),
                // Auto-dengar: popup dengar sendiri tanpa tap.
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: const Text('Auto-dengar popup',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 13)),
                          ),
                          Switch(
                            value: selAuto,
                            activeColor: Colors.cyanAccent,
                            onChanged: (v) => setD(() => selAuto = v),
                          ),
                        ],
                      ),
                      const Text(
                        'ON = robot dengar terus tanpa tap, bahkan layar mati (app boleh tutup).\nBoros baterai + indikator mic nyala terus. Butuh izin mic.',
                        style:
                            TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal')),
            TextButton(
                onPressed: () async {
                  try {
                    final title = titleCtrl.text.trim().isEmpty
                        ? OverlayService.defaultTitle
                        : titleCtrl.text.trim();
                    await OverlayService.saveConfig(
                        icon: selIcon,
                        color: selColor,
                        title: title,
                        image: selImage);
                    await OverlayService.saveAutolisten(selAuto);
                    if (mounted) {
                      setState(() {
                        _popIcon = selIcon;
                        _popColor = selColor;
                        _popTitleCtrl.text = title;
                        _popImage = selImage;
                        _popAuto = selAuto;
                      });
                    }
                    await OverlayService.hide();
                    final ok = await OverlayService.show();
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                          content: Text(ok
                              ? 'Popup ditampilkan ulang ✓ Sir.'
                              : 'Popup gagal tampil. Aktifkan: Settings HP > Apps > JARVIS > Display over other apps > Allow.')));
                      setD(() => statusVer++);
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Gagal: $e')));
                    }
                  }
                },
                child: const Text('Tampilkan ulang')),
            ElevatedButton(
                onPressed: () async {
                  // Seluruh alur dalam try: tombol tidak boleh terasa mati.
                  try {
                    if (saving) return;
                    saving = true;
                    try {
                      setD(() {});
                    } catch (_) {}
                    final title = titleCtrl.text.trim().isEmpty
                        ? OverlayService.defaultTitle
                        : titleCtrl.text.trim();
                    await OverlayService.saveConfig(
                        icon: selIcon,
                        color: selColor,
                        title: title,
                        image: selImage);
                    await OverlayService.saveAutolisten(selAuto);
                    // Verifikasi baca-balik: bukti nyata tersimpan.
                    final check = await OverlayService.readConfig();
                    final ok = check['icon'] == selIcon &&
                        check['color'] == selColor &&
                        check['title'] == title &&
                        check['image'] == selImage &&
                        check['auto'] == (selAuto ? '1' : '0');
                    if (mounted) {
                      setState(() {
                        _popIcon = selIcon;
                        _popColor = selColor;
                        _popTitleCtrl.text = title;
                        _popImage = selImage;
                        _popAuto = selAuto;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(ok
                              ? 'Tersimpan ✓ ikon=$selIcon warna=$selColor, Sir.'
                              : 'Tersimpan tapi verifikasi beda, Sir. Coba lagi.')));
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    try {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Gagal simpan: $e')));
                      }
                    } catch (_) {}
                  }
                },
                child: Text(saving ? 'Menyimpan...' : 'Save')),
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
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => widget.voice.speak('Halo Sir, suara Jarvis terdengar jelas.'),
              icon: const Icon(Icons.volume_up, size: 16),
              label: const Text('Tes suara',
                  style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.cyanAccent,
                  side: const BorderSide(color: Colors.cyanAccent)),
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
