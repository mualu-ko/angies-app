import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// Structured side effect (ADR) report. Saved on the phone straight away, so
/// it works offline; SyncService sends it to the clinician portal when online.
class ReportAdrScreen extends StatefulWidget {
  const ReportAdrScreen({super.key, required this.onSent});

  final VoidCallback onSent;

  @override
  State<ReportAdrScreen> createState() => _ReportAdrScreenState();
}

class _ReportAdrScreenState extends State<ReportAdrScreen> {
  String? _drug;
  final Set<String> _symptoms = {};
  final _other = TextEditingController();
  String _onset = 'onsetToday';
  Severity _severity = Severity.mild;
  String _action = 'actNothing';

  static const _onsets = ['onsetToday', 'onsetYesterday', 'onset23', 'onsetMore'];
  static const _actions = ['actNothing', 'actStopped', 'actOther', 'actHospital'];

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _symptoms.clear();
      _other.clear();
      _onset = 'onsetToday';
      _severity = Severity.mild;
      _action = 'actNothing';
    });
  }

  Future<void> _send(String drugName) async {
    final scope = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    if (_symptoms.isEmpty && _other.text.trim().isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(context.tr('pickSymptom'))));
      return;
    }
    final lang = scope.store.language;
    final report = AdrReport(
      id: 'ADR-${DateTime.now().millisecondsSinceEpoch}',
      drugName: drugName,
      symptoms: _symptoms.toList(),
      otherSymptom: _other.text.trim().isEmpty ? null : _other.text.trim(),
      // Stored in English so clinicians read the same words.
      onset: Strings.get('en', _onset),
      severity: _severity,
      actionTaken: Strings.get('en', _action),
      createdAt: DateTime.now(),
    );
    final severe = _severity == Severity.severe;
    await scope.store.addReport(report);
    if (!mounted) return;
    if (severe) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: StatusColors.crit, size: 36),
          title: Text(Strings.get(lang, 'severeTitle')),
          content: Text(Strings.get(lang, 'severeBody')),
          actions: [
            FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(Strings.get(lang, 'ok'))),
          ],
        ),
      );
    } else {
      messenger.showSnackBar(SnackBar(content: Text(Strings.get(lang, 'reportSent'))));
    }
    _reset();
    widget.onSent();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final rx = scope.store.prescription!;
    // The prescription can change remotely; fall back to the first drug.
    final names = rx.items.map((i) => i.drugName).toList();
    final drugName = (_drug != null && names.contains(_drug)) ? _drug! : names.first;
    final item = rx.items.firstWhere((i) => i.drugName == drugName, orElse: () => rx.items.first);
    final info = scope.library.drugs[item.drugId];
    final symptomOptions = info?.sideEffects ?? const <String>[];
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(context.tr('reportSideEffect'),
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: drugName,
          decoration: InputDecoration(labelText: context.tr('medicine')),
          items: [for (final i in rx.items) DropdownMenuItem(value: i.drugName, child: Text(i.drugName))],
          onChanged: (v) => setState(() {
            _drug = v;
            _symptoms.clear();
          }),
        ),
        SectionTitle(context.tr('whatFeeling')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in symptomOptions)
              FilterChip(
                label: Text(s),
                selected: _symptoms.contains(s),
                onSelected: (on) => setState(() => on ? _symptoms.add(s) : _symptoms.remove(s)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(controller: _other, decoration: InputDecoration(labelText: context.tr('otherSymptom'))),
        SectionTitle(context.tr('whenStarted')),
        DropdownButtonFormField<String>(
          value: _onset,
          items: [for (final o in _onsets) DropdownMenuItem(value: o, child: Text(context.tr(o)))],
          onChanged: (v) => setState(() => _onset = v ?? _onset),
        ),
        SectionTitle(context.tr('howBad')),
        SegmentedButton<Severity>(
          segments: [
            ButtonSegment(value: Severity.mild, label: Text(context.tr('mild'))),
            ButtonSegment(value: Severity.moderate, label: Text(context.tr('moderate'))),
            ButtonSegment(value: Severity.severe, label: Text(context.tr('severe'))),
          ],
          selected: {_severity},
          onSelectionChanged: (s) => setState(() => _severity = s.first),
        ),
        SectionTitle(context.tr('actionTaken')),
        DropdownButtonFormField<String>(
          value: _action,
          items: [for (final a in _actions) DropdownMenuItem(value: a, child: Text(context.tr(a)))],
          onChanged: (v) => setState(() => _action = v ?? _action),
        ),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: null, child: Text(context.tr('addPhoto'))),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => _send(drugName),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: _severity == Severity.severe ? StatusColors.crit : null,
          ),
          child: Text(context.tr('send')),
        ),
      ],
    );
  }
}
