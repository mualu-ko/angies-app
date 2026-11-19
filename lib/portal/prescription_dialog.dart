import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/drug_library.dart';
import '../models/models.dart';

/// Lets a clinician add or remove medicines on a patient's prescription.
/// In the demo the portal stands in for the hospital system: the change is
/// written to the patient's record in Firebase and the phone picks it up
/// within seconds, re-arming its alarms.
class PrescriptionDialog extends StatefulWidget {
  const PrescriptionDialog({
    super.key,
    required this.patientRef,
    required this.patient,
    required this.library,
    required this.staff,
  });

  final DocumentReference<Map<String, dynamic>> patientRef;
  final Map<String, dynamic> patient;
  final DrugLibrary library;
  final String staff;

  @override
  State<PrescriptionDialog> createState() => _PrescriptionDialogState();
}

class _PrescriptionDialogState extends State<PrescriptionDialog> {
  Prescription? _rx;
  late List<PrescriptionItem> _items;

  final _name = TextEditingController();
  final _dose = TextEditingController();
  final _times = TextEditingController(text: '08:00');
  final _instructions = TextEditingController();
  final _daysOn = TextEditingController(text: '1');
  final _daysOff = TextEditingController(text: '0');
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final raw = widget.patient['prescription'];
    _rx = raw is Map<String, dynamic> ? Prescription.fromJson(raw) : null;
    _items = [...?_rx?.items];
  }

  @override
  void dispose() {
    for (final c in [_name, _dose, _times, _instructions, _daysOn, _daysOff]) {
      c.dispose();
    }
    super.dispose();
  }

  String _drugId(String name) {
    for (final d in widget.library.drugs.values) {
      if (d.name.toLowerCase() == name.toLowerCase()) return d.id;
    }
    // No underscores: dose keys use "_" as a separator.
    return name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  }

  List<String>? _parseTimes(String text) {
    final out = <String>[];
    for (final part in text.split(RegExp(r'[,\s]+')).where((p) => p.isNotEmpty)) {
      final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(part);
      if (m == null) return null;
      final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
      if (h > 23 || min > 59) return null;
      out.add('${two(h)}:${two(min)}');
    }
    return out.isEmpty ? null : (out..sort());
  }

  void _add() {
    final name = _name.text.trim();
    final times = _parseTimes(_times.text);
    final on = int.tryParse(_daysOn.text.trim());
    final off = int.tryParse(_daysOff.text.trim());
    String? err;
    if (name.isEmpty) err = 'Enter a medicine.';
    if (err == null && _dose.text.trim().isEmpty) err = 'Enter the dose, e.g. 1 tablet (500 mg).';
    if (err == null && times == null) err = 'Times must look like 08:00, 20:00.';
    if (err == null && (on == null || on < 1 || off == null || off < 0)) err = 'Days on must be 1 or more; days off 0 or more.';
    if (err == null && _items.any((i) => i.drugId == _drugId(name))) err = '$name is already on the prescription.';
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _error = null;
      _items.add(PrescriptionItem(
        drugId: _drugId(name),
        drugName: name,
        dose: _dose.text.trim(),
        instructions: _instructions.text.trim().isEmpty ? 'as directed' : _instructions.text.trim(),
        times: times!,
        daysOn: on!,
        daysOff: off!,
        startDate: dateOnly(DateTime.now()),
      ));
      for (final c in [_name, _dose, _instructions]) {
        c.clear();
      }
    });
  }

  Future<void> _save() async {
    if (_items.isEmpty) {
      setState(() => _error = 'A prescription needs at least one medicine.');
      return;
    }
    setState(() => _saving = true);
    final rx = Prescription(
      id: _rx?.id ?? 'RX-${DateTime.now().millisecondsSinceEpoch}',
      prescriber: widget.staff,
      issuedAt: DateTime.now(),
      items: _items,
    );
    await widget.patientRef.update({
      'prescription': rx.toJson(),
      'medicines': [for (final i in rx.items) i.drugName],
      'drugIds': [for (final i in rx.items) i.drugId],
      'schedule': [for (final i in rx.items) '${i.drugName}: ${i.dose}, ${i.times.join(' & ')}'],
      'rxUpdatedAt': DateTime.now().toIso8601String(),
      'rxUpdatedBy': widget.staff,
    });
    if (mounted) Navigator.of(context).pop();
  }

  String _cycle(PrescriptionItem i) => i.daysOff == 0 ? 'every day' : '${i.daysOn} days on, ${i.daysOff} off';

  @override
  Widget build(BuildContext context) {
    final suggestions = widget.library.search(_name.text, limit: 5);
    final exactMatch = suggestions.any((m) => m.name.toLowerCase() == _name.text.trim().toLowerCase());
    return AlertDialog(
      title: Text('Prescription · ${widget.patient['patientName']}'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_rx == null)
                const Text('No prescription on record yet. The patient needs to sign in on the app first.'),
              for (final i in _items)
                Card(
                  child: ListTile(
                    title: Text('${i.drugName} · ${i.dose}'),
                    subtitle: Text('${i.times.join(' & ')} · ${_cycle(i)} · ${i.instructions}'),
                    trailing: IconButton(
                      tooltip: 'Remove from prescription',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _items.remove(i)),
                    ),
                  ),
                ),
              const Divider(height: 28),
              const Text('Add a medicine', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Medicine', hintText: 'Search, e.g. ondansetron'),
                onChanged: (_) => setState(() {}),
              ),
              if (_name.text.trim().length >= 2 && !exactMatch)
                Wrap(
                  spacing: 6,
                  children: [
                    for (final m in suggestions)
                      ActionChip(
                        label: Text(m.name),
                        onPressed: () => setState(() => _name.text = m.name),
                      ),
                  ],
                ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _dose,
                    decoration: const InputDecoration(labelText: 'Dose', hintText: '1 tablet (8 mg)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _times,
                    decoration: const InputDecoration(labelText: 'Times (24 h)', hintText: '08:00, 20:00'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _daysOn,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Days on'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _daysOff,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Days off (0 = every day)'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: _instructions,
                decoration: const InputDecoration(labelText: 'Instructions', hintText: 'after food'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add to list')),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 8),
              Text('Saving updates the patient\'s app and re-arms their alarms.',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _saving || _rx == null ? null : _save, child: const Text('Save prescription')),
      ],
    );
  }
}
