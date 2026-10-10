import 'package:flutter/material.dart';

import '../core/app_controller.dart';

/// Layar "Izin & Kepercayaan": jelaskan KENAPA tiap izin dipakai,
/// plus tombol cek/aktifkan. Biar user paham, bukan asal allow.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermItem {
  final IconData icon;
  final String title;
  final String why;
  final Future<String> Function() check;
  final Future<String> Function() request;
  String status;
  _PermItem({
    required this.icon,
    required this.title,
    required this.why,
    required this.check,
    required this.request,
    this.status = '?',
  });
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  late final List<_PermItem> _items;

  @override
  void initState() {
    super.initState();
    _items = [
      _PermItem(
        icon: Icons.mic,
        title: 'Mikrofon',
        why: 'Dengar perintah suara + wake word "Hey Jarvis". Tanpa ini JARVIS tuli.',
        check: () async => 'OK',
        request: AppController.requestMic,
      ),
      _PermItem(
        icon: Icons.notifications_active,
        title: 'Akses notifikasi',
        why: 'Baca WA/Telegram/SMS masuk biar bisa dibacakan + diringkas AI.',
        check: AppController.notifCheck,
        request: () async {
          await AppController.notifOpenSettings();
          return 'OK';
        },
      ),
      _PermItem(
        icon: Icons.location_on,
        title: 'Lokasi',
        why: 'Pengingat berbasis lokasi ("ingatkan saat sampai kantor") + cuaca.',
        check: () async => 'OK',
        request: AppController.requestLoc,
      ),
      _PermItem(
        icon: Icons.sms,
        title: 'SMS',
        why: 'Fitur find-my-phone: SMS kode rahasia -> HP balas lokasi / bunyi / kunci.',
        check: () async => 'OK',
        request: AppController.requestSms,
      ),
      _PermItem(
        icon: Icons.picture_in_picture,
        title: 'Tampil di atas aplikasi',
        why: 'Popup robot mini yang bisa dipanggil dari mana saja.',
        check: AppController.overlayPerm,
        request: AppController.overlayRequest,
      ),
      _PermItem(
        icon: Icons.accessibility_new,
        title: 'Aksesibilitas',
        why: 'Otomatisasi tap/geser/ketik (mode reels, auto-klik). Opsional.',
        check: AppController.accCheck,
        request: () async {
          await AppController.accOpenSettings();
          return 'OK';
        },
      ),
      _PermItem(
        icon: Icons.admin_panel_settings,
        title: 'Admin perangkat',
        why: 'Kunci layar via perintah suara. Opsional.',
        check: AppController.adminCheck,
        request: AppController.adminRequest,
      ),
      _PermItem(
        icon: Icons.battery_charging_full,
        title: 'Abaikan optimasi baterai',
        why: 'Biar wake word + rutinitas tetap jalan saat layar mati.',
        check: AppController.batteryCheck,
        request: AppController.batteryRequest,
      ),
    ];
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    for (final it in _items) {
      try {
        final r = await it.check().timeout(const Duration(seconds: 8));
        it.status = (r == 'OK' || r.startsWith('OK')) ? 'Aktif' : 'Mati';
      } catch (_) {
        it.status = '?';
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Izin & Kepercayaan',
            style: TextStyle(color: Colors.cyanAccent)),
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'JARVIS cuma minta izin yang beneran dipakai. Tidak ada data yang dikirim ke mana-mana kecuali perintahmu sendiri.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          ..._items.map((it) => Card(
                color: const Color(0xFF101418),
                child: ListTile(
                  leading: Icon(it.icon, color: Colors.cyanAccent),
                  title: Text(it.title,
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    '${it.why}\nStatus: ${it.status}',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12),
                  ),
                  isThreeLine: true,
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: it.status == 'Aktif'
                          ? Colors.green.shade700
                          : Colors.cyanAccent,
                      foregroundColor: it.status == 'Aktif'
                          ? Colors.white
                          : Colors.black,
                    ),
                    onPressed: () async {
                      final r = await it.request()
                          .timeout(const Duration(seconds: 15),
                              onTimeout: () => 'OK');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(r)));
                      }
                      await _refreshAll();
                    },
                    child: Text(it.status == 'Aktif' ? 'Cek' : 'Aktifkan'),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
