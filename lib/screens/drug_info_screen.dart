import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

/// Pick any of your medicines from the dropdown to see its information:
/// your cancer medicine, others on your hospital record, and ones your
/// pharmacist has approved. Interaction alerts are checked against all of
/// them. Everything is bundled, so it works offline.
class DrugInfoScreen extends StatefulWidget {
  const DrugInfoScreen({super.key});

  @override
  State<DrugInfoScreen> createState() => _DrugInfoScreenState();
}

class _Choice {
  const _Choice(this.key, this.name, this.groupKey, {this.item, this.note});
  final String key;
  final String name;
  final String groupKey;
  final PrescriptionItem? item;
  final String? note;
}

class _DrugInfoScreenState extends State<DrugInfoScreen> {
  String? _selected;

  Future<void> _addMedicine(BuildContext context) async {
    final store = AppScope.read(context).store;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _AddMedicineDialog(),
    );
    if (name != null && name.trim().isNotEmpty) await store.addReportedMedicine(name);
  }

  List<_Choice> _choices(BuildContext context) {
    final store = AppScope.of(context).store;
    return [
      for (final i in store.prescription!.items) _Choice('rx:${i.drugId}', i.drugName, 'yourCancerMedicine', item: i),
      for (final m in store.otherMedicines) _Choice('other:$m', m, 'onHospitalRecord'),
      for (final m in store.reportedMedicines)
        if (m.status == 'approved') _Choice('rep:${m.id}', m.name, 'approvedByPharmacist', note: m.note),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final store = scope.store;
    final theme = Theme.of(context);
    final choices = _choices(context);
    final current = choices.firstWhere((c) => c.key == _selected, orElse: () => choices.first);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        DropdownButtonFormField<String>(
          // Key forces a rebuild when the list changes (e.g. a new approval).
          key: ValueKey(choices.map((c) => c.key).join('|')),
          value: current.key,
          isExpanded: true,
          decoration: InputDecoration(labelText: context.tr('chooseDrug')),
          items: [
            for (final c in choices)
              DropdownMenuItem(
                value: c.key,
                child: Text('${c.name}  ·  ${context.tr(c.groupKey)}', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _selected = v),
        ),
        const SizedBox(height: 20),
        if (current.item != null) ..._drugSection(context, current.item!) else ..._otherSection(context, current),
        SectionTitle(context.tr('fromHospital')),
        if (store.otherMedicines.isEmpty)
          Text(context.tr('noneOnRecord'), style: theme.textTheme.bodyMedium)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final m in store.otherMedicines) Chip(label: Text(m))],
          ),
        SectionTitle(context.tr('youReported')),
        Text(context.tr('reportedNote'), style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        for (final m in store.reportedMedicines)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
              m.status == 'approved'
                  ? Icons.verified_outlined
                  : m.status == 'rejected'
                      ? Icons.warning_amber_rounded
                      : Icons.hourglass_empty,
              color: m.status == 'approved'
                  ? StatusColors.good
                  : m.status == 'rejected'
                      ? StatusColors.crit
                      : null,
            ),
            title: Text(m.name),
            subtitle: Text([
              context.tr(m.status == 'approved'
                  ? 'medApproved'
                  : m.status == 'rejected'
                      ? 'medRejected'
                      : 'pendingCheck'),
              if (m.note != null && m.note!.isNotEmpty) m.note!,
            ].join('\n')),
            onTap: m.status == 'approved' ? () => setState(() => _selected = 'rep:${m.id}') : null,
            trailing: m.status == 'pending'
                ? IconButton(icon: const Icon(Icons.close), onPressed: () => store.removeReportedMedicine(m.id))
                : null,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add),
            label: Text(context.tr('addOther')),
            onPressed: () => _addMedicine(context),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.chat_outlined),
          label: Text(context.tr('askPharmacist')),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChatScreen())),
        ),
        const SizedBox(height: 8),
        Text(context.tr('notAdvice'), style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
      ],
    );
  }

  Widget _alertCard(BuildContext context, String title, String body, Color color, {String? source}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InfoCard(
          color: color,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(body),
              if (source != null) ...[
                const SizedBox(height: 6),
                Text('Source: $source', style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      );

  /// A cancer medicine on the prescription: full information.
  List<Widget> _drugSection(BuildContext context, PrescriptionItem item) {
    final scope = AppScope.of(context);
    final lib = scope.library;
    final info = lib.infoFor(item.drugId, item.drugName);
    final theme = Theme.of(context);
    final drugAlerts = lib.drugAlerts(item.drugId, scope.store.allOtherMedicines);
    final foodAlerts = lib.foodAlerts(item.drugId);

    return [
      Text(item.drugName, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      if (info != null && info.drugClass.isNotEmpty) Text(info.drugClass, style: theme.textTheme.bodyMedium),
      if (info != null && info.uses.isNotEmpty) ...[
        SectionTitle(context.tr('whatFor')),
        Text(info.uses),
      ],
      SectionTitle(context.tr('yourDose')),
      Text('${item.dose}, ${item.times.join(' & ')} · ${item.instructions}'),
      if (info != null) ..._infoBody(context, info) else ...[
        const SizedBox(height: 8),
        Text(context.tr('noInfoYet')),
      ],
      const SizedBox(height: 16),
      for (final a in drugAlerts) _alertCard(context, context.tr('interactionAlert'), a.advice, StatusColors.crit, source: lib.source),
      if (drugAlerts.isEmpty && scope.store.allOtherMedicines.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(context.tr('noInteractions'), style: theme.textTheme.bodySmall),
        ),
      for (final a in foodAlerts) _alertCard(context, context.tr('foodAlert'), a.advice, StatusColors.warn),
      const Divider(height: 32),
    ];
  }

  /// Any other medicine: what the bundled list knows, plus interactions with
  /// the patient's cancer medicines.
  List<Widget> _otherSection(BuildContext context, _Choice c) {
    final scope = AppScope.of(context);
    final lib = scope.library;
    final theme = Theme.of(context);
    final entry = lib.find(c.name);
    final info = lib.infoFor(slugify(c.name), c.name);
    final alerts = [
      for (final i in scope.store.prescription!.items) ...lib.drugAlerts(i.drugId, [c.name]),
    ];
    return [
      Text(c.name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      Text(context.tr(c.groupKey), style: theme.textTheme.bodyMedium),
      if (info != null && info.drugClass.isNotEmpty) Text(info.drugClass, style: theme.textTheme.bodySmall)
      else if (entry != null && entry.category.isNotEmpty) Text(entry.category, style: theme.textTheme.bodySmall),
      if (info != null && info.uses.isNotEmpty) ...[
        SectionTitle(context.tr('whatFor')),
        Text(info.uses),
      ],
      if (entry != null && entry.contains.isNotEmpty) ...[
        SectionTitle(context.tr('contains')),
        Text(entry.contains.join(', ')),
      ],
      if (entry != null && entry.aliases.isNotEmpty) ...[
        SectionTitle(context.tr('alsoKnownAs')),
        Text(entry.aliases.join(', ')),
      ],
      if (info != null) ..._infoBody(context, info),
      if (c.note != null && c.note!.isNotEmpty) ...[
        SectionTitle(context.tr('medApproved')),
        Text(c.note!),
      ],
      SectionTitle(context.tr('interactionsWithYours')),
      if (alerts.isEmpty) Text(context.tr('noInteractions')),
      for (final a in alerts) _alertCard(context, context.tr('interactionAlert'), a.advice, StatusColors.crit, source: lib.source),
      if (info == null) ...[
        const SizedBox(height: 8),
        Text(context.tr('noInfoYet'), style: theme.textTheme.bodySmall),
      ],
      const Divider(height: 32),
    ];
  }

  List<Widget> _infoBody(BuildContext context, DrugInfo info) => [
        if (info.howToTake.isNotEmpty) ...[
          SectionTitle(context.tr('howToTake')),
          for (final s in info.howToTake) _bullet(s),
        ],
        if (info.sideEffects.isNotEmpty) ...[
          SectionTitle(context.tr('sideEffects')),
          Text(info.sideEffects.join(', ')),
        ],
        if (info.getHelpIf.isNotEmpty) ...[
          SectionTitle(context.tr('getHelpIf')),
          for (final s in info.getHelpIf) _bullet(s),
        ],
        if (info.updatedBy != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(context.tr('writtenBy', {'name': info.updatedBy!}), style: Theme.of(context).textTheme.bodySmall),
          ),
      ];

  Widget _bullet(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [const Text('•  '), Expanded(child: Text(s))],
        ),
      );
}

/// Search the bundled medicine list; free text is still allowed for things
/// not in the list (local herbal remedies, unusual brands).
class _AddMedicineDialog extends StatefulWidget {
  const _AddMedicineDialog();

  @override
  State<_AddMedicineDialog> createState() => _AddMedicineDialogState();
}

class _AddMedicineDialogState extends State<_AddMedicineDialog> {
  // Owned by this widget so it is disposed only after the dialog closes.
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = AppScope.read(context).library;
    final query = _controller.text.trim();
    final results = library.search(query);
    final exact = results.any((r) => r.name.toLowerCase() == query.toLowerCase());

    return AlertDialog(
      title: Text(context.tr('addOther')),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: context.tr('medicineName'),
                hintText: context.tr('searchMedicine'),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in results)
                    ListTile(
                      dense: true,
                      title: Text(r.name),
                      subtitle: Text([
                        if (r.contains.isNotEmpty) r.contains.join(' + '),
                        if (r.aliases.isNotEmpty) r.aliases.join(', '),
                        r.category,
                      ].where((x) => x.isNotEmpty).join(' · ')),
                      onTap: () => Navigator.of(context).pop(r.name),
                    ),
                  if (query.length >= 2 && !exact)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.add),
                      title: Text(context.tr('notInList', {'name': query})),
                      onTap: () => Navigator.of(context).pop(query),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('cancel'))),
      ],
    );
  }
}
