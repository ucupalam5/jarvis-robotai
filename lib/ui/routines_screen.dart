import 'package:flutter/material.dart';

import '../core/routine_service.dart';

/// Layar kelola rutinitas terjadwal: tambah / hapus / on-off.
///
/// Aksi per rutin: ucapkan teks, briefing cuaca, Wi-Fi, buka aplikasi.
class RoutinesScreen extends StatefulWidget {
  const RoutinesScreen({super.key});

  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends State<RoutinesScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await RoutineService.load();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(int i, bool on) async {
    _items[i]['on'] = on;
    await RoutineService.save(_items);
    if (mounted) setState(() {});
  }

  Future<void> _delete(int i) async {
    _items.removeAt(i);
    await RoutineService.save(_items);
    if (mounted) setState(() {});
  }

  String _daysLabel(List? days) {
    const names = {1: 'Sn', 2: 'Sl', 3: 'Rb', 4: 'Km', 5: 'Jm', 6: 'Sb', 7: 'Mg'};
    if (days == null || days.length == 7) return 'Tiap hari';
    return (days as List).map((d) => names[d] ?? '?').join(' ');
  }

  String _actionsLabel(List? actions) {
    if (actions == null || actions.isEmpty) return '-';
    return (actions as List).map((a) {
      final m = (a as Map).cast<String, dynamic>();
      return switch ((m['t'] ?? '').toString()) {
        'say' => 'Ucap',
        'briefing' => 'Briefing',
        'wifi' => 'Wi-Fi ${m['on'] == true ? 'ON' : 'OFF'}',
        'app' => 'Buka ${m['keyword'] ?? ''}',
        _ => '?',
      };
    }).join(', ');
  }

  Future<void> _addDialog() async {
    final nameCtrl = TextEditingController();
    final sayCtrl = TextEditingController();
    TimeOfDay time = const TimeOfDay(hour: 7, minute: 0);
    final days = <int>{1, 2, 3, 4, 5};
    String action = 'say';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF101418),
          title: const Text('Rutin baru',
              style: TextStyle(color: Colors.cyanAccent)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Nama (mis: pagi kerja)',
                    labelStyle: TextStyle(color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Jam: ',
                        style: TextStyle(color: Colors.white70)),
                    TextButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: ctx, initialTime: time);
                        if (t != null) setD(() => time = t);
                      },
                      child: Text(time.format(ctx),
                          style: const TextStyle(
                              color: Colors.cyanAccent, fontSize: 18)),
                    ),
                  ],
                ),
                const Text('Hari:',
                    style: TextStyle(color: Colors.white70)),
                Wrap(
                  spacing: 4,
                  children: [1, 2, 3, 4, 5, 6, 7].map((d) {
                    const names = {
                      1: 'Sn', 2: 'Sl', 3: 'Rb', 4: 'Km',
                      5: 'Jm', 6: 'Sb', 7: 'Mg'
                    };
                    final sel = days.contains(d);
                    return FilterChip(
                      label: Text(names[d]!,
                          style: TextStyle(
                              color: sel ? Colors.black : Colors.white70)),
                      selected: sel,
                      selectedColor: Colors.cyanAccent,
                      onSelected: (v) => setD(
                          () => v ? days.add(d) : days.remove(d)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                const Text('Aksi:',
                    style: TextStyle(color: Colors.white70)),
                DropdownButton<String>(
                  value: action,
                  dropdownColor: const Color(0xFF101418),
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(
                        value: 'say', child: Text('Ucapkan teks')),
                    DropdownMenuItem(
                        value: 'briefing', child: Text('Briefing cuaca')),
                    DropdownMenuItem(
                        value: 'wifi_on', child: Text('Wi-Fi nyala')),
                    DropdownMenuItem(
                        value: 'wifi_off', child: Text('Wi-Fi mati')),
                  ],
                  onChanged: (v) => setD(() => action = v!),
                ),
                if (action == 'say')
                  TextField(
                    controller: sayCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Teks yang diucapkan',
                      labelStyle: TextStyle(color: Colors.white54),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (nameCtrl.text.trim().isEmpty || days.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Nama dan hari wajib diisi, Sir.')));
      }
      return;
    }
    final actions = <Map<String, dynamic>>[];
    switch (action) {
      case 'say':
        actions.add({'t': 'say', 'text': sayCtrl.text.trim()});
        break;
      case 'briefing':
        actions.add({'t': 'briefing'});
        break;
      case 'wifi_on':
        actions.add({'t': 'wifi', 'on': true});
        break;
      case 'wifi_off':
        actions.add({'t': 'wifi', 'on': false});
        break;
    }
    _items.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'name': nameCtrl.text.trim(),
      'hour': time.hour,
      'minute': time.minute,
      'days': days.toList()..sort(),
      'actions': actions,
      'on': true,
    });
    await RoutineService.save(_items);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Rutinitas',
            style: TextStyle(color: Colors.cyanAccent)),
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Text(
                    'Belum ada rutin.\nContoh: tiap jam 7 pagi -> briefing cuaca.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (ctx, i) {
                    final r = _items[i];
                    final hh = (r['hour'] as int).toString().padLeft(2, '0');
                    final mm =
                        (r['minute'] as int).toString().padLeft(2, '0');
                    return Card(
                      color: const Color(0xFF101418),
                      child: ListTile(
                        title: Text('${r['name']} — $hh:$mm',
                            style:
                                const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          '${_daysLabel(r['days'] as List?)} • ${_actionsLabel(r['actions'] as List?)}',
                          style:
                              const TextStyle(color: Colors.white54),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: (r['on'] ?? true) as bool,
                              activeColor: Colors.cyanAccent,
                              onChanged: (v) => _toggle(i, v),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete,
                                  color: Colors.redAccent),
                              onPressed: () => _delete(i),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.cyanAccent,
        foregroundColor: Colors.black,
        onPressed: _addDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
