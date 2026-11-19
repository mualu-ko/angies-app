import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/drug_library.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'portal_widgets.dart';

/// Staff write the patient-friendly description of a medicine here. The app
/// shows it on the Drugs page (and keeps a copy for offline use). Entries
/// written here replace the bundled sample text.
class DrugLibraryPage extends StatelessWidget {
  const DrugLibraryPage({super.key, required this.library, required this.staff});

  final DrugLibrary library;
  final String staff;

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('drugInfo').snapshots(),
      builder: (context, infoSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('patients').snapshots(),
          builder: (context, pSnap) {
            if (infoSnap.hasError) return Center(child: Text('Could not load: ${infoSnap.error}'));
            if (!infoSnap.hasData) return const Center(child: CircularProgressIndicator());
            final written = {for (final d in infoSnap.data!.docs) d.id: d.data()};

            // Medicines patients actually have, so staff know what to write first.
            final inUse = <String, String>{}; // id -> name
            for (final d in pSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
              final p = d.data();
              for (final n in [
                ...((p['medicines'] as List?) ?? const []),
                ...((p['otherMedicines'] as List?) ?? const []),
              ]) {
                inUse[slugify('$n')] = '$n';
              }
            }
            final missing = inUse.entries.where((e) => !written.containsKey(e.key)).toList()
              ..sort((a, b) => a.value.compareTo(b.value));
            final entries = written.values.toList()
              ..sort((a, b) => (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));

            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(children: [
                  Expanded(
                    child: Text('Drug library', style: Theme.of(context).textTheme.headlineSmall),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add a medicine'),
                    onPressed: () => _edit(context, null),
                  ),
                ]),
                const SizedBox(height: 4),
                const Text('What you write here appears on the patient\'s Drugs page. Plain words, short lines.'),
                if (missing.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('Patients take these, but they have no description yet',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final m in missing)
                      ActionChip(
                        avatar: const Icon(Icons.edit, size: 16, color: StatusColors.warn),
                        label: Text(m.value),
                        onPressed: () => _edit(context, null, name: m.value),
                      ),
                  ]),
                ],
                const SizedBox(height: 20),
                if (entries.isEmpty) const Text('No descriptions yet. The app is using the bundled sample text.'),
                for (final e in entries)
                  Card(
                    child: ListTile(
                      title: Text('${e['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text([
                        if ((e['class'] as String?)?.isNotEmpty == true) e['class'],
                        if ((e['uses'] as String?)?.isNotEmpty == true) e['uses'],
                        'Last edited by ${e['updatedBy'] ?? '?'} ${timeAgo(e['updatedAt'] as String?)}',
                      ].join('\n')),
                      isThreeLine: true,
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _edit(context, e),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _edit(BuildContext context, Map<String, dynamic>? existing, {String? name}) {
    showDialog<void>(
      context: context,
      builder: (_) => _DrugEditor(library: library, staff: staff, existing: existing, name: name),
    );
  }
}

class _DrugEditor extends StatefulWidget {
  const _DrugEditor({required this.library, required this.staff, this.existing, this.name});

  final DrugLibrary library;
  final String staff;
  final Map<String, dynamic>? existing;
  final String? name;

  @override
  State<_DrugEditor> createState() => _DrugEditorState();
}

class _DrugEditorState extends State<_DrugEditor> {
  final _name = TextEditingController();
  final _class = TextEditingController();
  final _uses = TextEditingController();
  final _how = TextEditingController();
  final _side = TextEditingController();
  final _help = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _fill(DrugInfo.fromJson({...e, 'id': e['id'] ?? slugify(e['name'] as String? ?? '')}));
    } else if (widget.name != null) {
      _name.text = widget.name!;
      _prefillFromBundled();
    }
  }

  void _fill(DrugInfo i) {
    _name.text = i.name;
    _class.text = i.drugClass;
    _uses.text = i.uses;
    _how.text = i.howToTake.join('\n');
    _side.text = i.sideEffects.join('\n');
    _help.text = i.getHelpIf.join('\n');
  }

  /// Start from the bundled sample text when there is one (e.g. capecitabine).
  void _prefillFromBundled() {
    final bundled = widget.library.drugs[slugify(_name.text)];
    if (bundled != null) _fill(bundled);
  }

  @override
  void dispose() {
    for (final c in [_name, _class, _uses, _how, _side, _help]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _lines(TextEditingController c) =>
      c.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter the medicine name.');
      return;
    }
    setState(() => _saving = true);
    final id = slugify(name);
    await FirebaseFirestore.instance.collection('drugInfo').doc(id).set({
      'id': id,
      'name': name,
      'class': _class.text.trim(),
      'uses': _uses.text.trim(),
      'howToTake': _lines(_how),
      'sideEffects': _lines(_side),
      'getHelpIf': _lines(_help),
      'cancerTypes': widget.library.drugs[id]?.cancerTypes ?? const <String>[],
      'updatedBy': widget.staff,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    if (mounted) Navigator.of(context).pop();
  }

  Widget _field(TextEditingController c, String label, {String? hint, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          minLines: lines,
          maxLines: lines == 1 ? 1 : 8,
          decoration: InputDecoration(labelText: label, hintText: hint, alignLabelWithHint: lines > 1),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final suggestions = widget.existing == null ? widget.library.search(_name.text, limit: 5) : const <MedicineEntry>[];
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add a medicine description' : 'Edit ${_name.text}'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                enabled: widget.existing == null,
                decoration: const InputDecoration(labelText: 'Medicine', hintText: 'Search, e.g. azithromycin'),
                onChanged: (_) => setState(() {}),
              ),
              if (suggestions.isNotEmpty && suggestions.every((m) => m.name.toLowerCase() != _name.text.trim().toLowerCase()))
                Wrap(spacing: 6, children: [
                  for (final m in suggestions)
                    ActionChip(
                      label: Text(m.name),
                      onPressed: () => setState(() {
                        _name.text = m.name;
                        _prefillFromBundled();
                      }),
                    ),
                ]),
              const SizedBox(height: 12),
              _field(_class, 'Type of medicine', hint: 'Antibiotic (macrolide)'),
              _field(_uses, 'What it is for', hint: 'Treats some bacterial infections, like chest infections.', lines: 2),
              _field(_how, 'How to take it (one per line)', hint: 'Once a day for 3 days\nWith or without food', lines: 3),
              _field(_side, 'Common side effects (one per line)', hint: 'Diarrhoea\nNausea\nStomach pain', lines: 3),
              _field(_help, 'Contact your care team if (one per line)', hint: 'Severe diarrhoea\nRash or swelling of the face', lines: 3),
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
