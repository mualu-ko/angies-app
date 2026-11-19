import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// Details come from the hospital record; the patient only confirms them,
/// picks a language and gives consent. Nothing is typed in.
class ConfirmDetailsScreen extends StatefulWidget {
  const ConfirmDetailsScreen({super.key, required this.record});

  final HospitalRecord record;

  @override
  State<ConfirmDetailsScreen> createState() => _ConfirmDetailsScreenState();
}

class _ConfirmDetailsScreenState extends State<ConfirmDetailsScreen> {
  late String _lang;
  bool _consent = false;

  @override
  void initState() {
    super.initState();
    _lang = AppScope.read(context).store.language;
  }

  Future<void> _confirm() async {
    final store = AppScope.read(context).store;
    final nav = Navigator.of(context);
    await store.saveRecord(widget.record, lang: _lang, consent: _consent);
    nav.popUntil((r) => r.isFirst);
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: Colors.black54))),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.record.patient;
    final rx = widget.record.prescription;
    String t(String k) => Strings.get(_lang, k);
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(t('isThisYou'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          Text(t('fromRecords')),
          const SizedBox(height: 16),
          InfoCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                _row(t('name'), p.name),
                const Divider(height: 1),
                _row(t('clinic'), p.clinic),
                const Divider(height: 1),
                _row(t('treatment'), p.diagnosis),
                const Divider(height: 1),
                _row(t('medicine'), rx.items.map((i) => i.drugName).join(', ')),
                const Divider(height: 1),
                _row(t('started'), formatDay(rx.items.first.startDate)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(t('language')),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'en', label: Text('English')),
              ButtonSegment(value: 'sw', label: Text('Kiswahili')),
            ],
            selected: {_lang},
            onSelectionChanged: (s) => setState(() => _lang = s.first),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(t('consent')),
          ),
          Text(t('wrongDetails'), style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _consent ? _confirm : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(t('yesThisIsMe')),
          ),
        ],
      ),
    );
  }
}
