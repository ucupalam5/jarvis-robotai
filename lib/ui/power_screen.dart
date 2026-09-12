import 'package:flutter/material.dart';
import '../core/app_controller.dart';
import '../core/overlay_service.dart';

/// Pusat Kekuasaan: semua izin + akses Jarvis dalam 1 layar.
/// Hijau = aktif. Tap baris oranye = langsung lompat ke pengaturannya.
/// Semua GRATIS, tanpa root.
class PowerItem {
  final String title;
  final String desc;
  final Future<String> Function() check;
  final Future<String> Function() request;
  String status = '...';
  PowerItem(
      {required this.title,
      required this.desc,
      required this.check,
      required this.request});
}

class PowerScreen extends StatefulWidget {
  const PowerScreen({super.key});

  @override
  State<PowerScreen> createState() => _PowerScreenState();
}

class _PowerScreenState extends State<PowerScreen> {
  late final List<PowerItem> _items;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _items = [
      PowerItem(
          title: 'Microphone',
          desc: 'Dengar perintah suara.',
          check: () async {
            final ok = await AppController.requestMic();
            return ok == 'OK' ? 'OK' : ok;
          },
          request: () => AppController.requestMic()),
      PowerItem(
          title: 'Notifikasi sistem',
          desc: 'Notifikasi status popup (Android 13+).',
          check: () => AppController.requestNotif(),
          request: () => AppController.requestNotif()),
      PowerItem(
          title: 'Kamera',
          desc: 'Senter + foto.',
          check: () => AppController.requestCamera(),
          request: () => AppController.requestCamera()),
      PowerItem(
          title: 'Kontak',
          desc: 'Chat/telpon pakai nama ("telpon mama").',
          check: () => AppController.requestContacts(),
          request: () => AppController.requestContacts()),
      PowerItem(
          title: 'SMS',
          desc: 'Find-my-phone via SMS darurat.',
          check: () => AppController.requestSms(),
          request: () => AppController.requestSms()),
      PowerItem(
          title: 'Lokasi',
          desc: 'Kirim titik GPS saat diminta (FIND).',
          check: () => AppController.requestLoc(),
          request: () => AppController.requestLoc()),
      PowerItem(
          title: 'Bluetooth',
          desc: 'Nyalakan/matikan bluetooth via suara.',
          check: () => AppController.requestBt(),
          request: () => AppController.requestBt()),
      PowerItem(
          title: 'Overlay (tampil di atas app)',
          desc: 'Syarat popup robot melayang.',
          check: () => AppController.overlayPerm(),
          request: () => AppController.overlayRequest()),
      PowerItem(
          title: 'Aksesibilitas',
          desc: 'Tap/ketik/klik + screenshot otomatis.',
          check: () => AppController.accCheck(),
          request: () => AppController.accOpenSettings()),
      PowerItem(
          title: 'Device Admin',
          desc: 'Syarat kunci/mati layar via suara.',
          check: () => AppController.adminCheck(),
          request: () => AppController.adminRequest()),
      PowerItem(
          title: 'Akses Notifikasi',
          desc: 'Baca + balas WA/Telegram/SMS masuk.',
          check: () => AppController.notifCheck(),
          request: () => AppController.notifOpenSettings()),
      PowerItem(
          title: 'Tulis Pengaturan',
          desc: 'Kecerahan, timeout layar, putar otomatis.',
          check: () => AppController.writeCheck(),
          request: () => AppController.writeRequest()),
      PowerItem(
          title: 'Akses Penggunaan',
          desc: 'Laporan screen time ("main apa aja").',
          check: () => AppController.usageCheck(),
          request: () => AppController.usageRequest()),
      PowerItem(
          title: 'Abaikan Optimasi Baterai',
          desc: 'Agar Jarvis tidak dibunuh sistem saat standby.',
          check: () => AppController.batteryCheck(),
          request: () => AppController.batteryRequest()),
      PowerItem(
          title: 'Akses Jangan Ganggu',
          desc: 'Mode hening dijamin walau DND aktif.',
          check: () => AppController.dndCheck(),
          request: () => AppController.dndRequest()),
      PowerItem(
          title: 'Asisten Default',
          desc: 'Tombol power / home lama memanggil Jarvis.',
          check: () => AppController.assistCheck(),
          request: () => AppController.assistRequest()),
    ];
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() => _loading = true);
    for (final it in _items) {
      try {
        it.status = await it.check();
      } catch (e) {
        it.status = 'Gagal cek: $e';
      }
      if (mounted) setState(() {});
    }
    if (mounted) setState(() => _loading = false);
  }

  int get _okCount => _items.where((e) => e.status == 'OK').length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050B18),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('Pusat Kekuasaan ($_okCount/${_items.length})',
            style:
                const TextStyle(color: Colors.cyanAccent, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
            tooltip: 'Cek ulang semua',
            onPressed: _refreshAll,
          ),
        ],
      ),
      body: _loading && _okCount == 0
          ? const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final it = _items[i];
                final ok = it.status == 'OK';
                return Card(
                  color: const Color(0xFF0E1E3A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color: ok ? Colors.greenAccent : Colors.orangeAccent),
                  ),
                  child: ListTile(
                    title: Text(it.title,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14)),
                    subtitle: Text(
                        '${it.desc}\n${ok ? 'AKTIF ✓' : it.status}',
                        style: TextStyle(
                            color: ok
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            fontSize: 12)),
                    trailing: ok
                        ? const Icon(Icons.check_circle,
                            color: Colors.greenAccent)
                        : const Icon(Icons.arrow_forward,
                            color: Colors.orangeAccent),
                    onTap: ok
                        ? null
                        : () async {
                            final r = await it.request();
                            if (context.mounted && r != 'OK') {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                      SnackBar(content: Text(r)));
                            }
                            // Balik dari pengaturan -> cek ulang otomatis.
                            Future.delayed(
                                const Duration(seconds: 1), () {
                              if (mounted) _refreshAll();
                            });
                          },
                  ),
                );
              },
            ),
    );
  }
}
