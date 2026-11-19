import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/schedule_service.dart';
import '../widgets/common.dart';
import 'ring_screen.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, required this.onReport});

  final VoidCallback onReport;

  String _cycleLine(BuildContext context, Prescription rx) {
    final item = rx.items.first;
    final info = ScheduleService.cycleInfo(item, DateTime.now());
    if (info == null) return context.tr('everyDay');
    if (info.day > info.length) return context.tr('restDay', {'c': info.cycle});
    return context.tr('cycleDay', {'c': info.cycle, 'd': info.day, 'n': info.length});
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final store = scope.store;
    final rx = store.prescription!;
    final patient = store.patient!;
    final theme = Theme.of(context);
    final now = DateTime.now();

    // This week (Monday to Sunday), counting every dose from sign-up on,
    // including ones still to come, so a new patient sees "0 of 7", not "0 of 0".
    final monday = dateOnly(now).subtract(Duration(days: now.weekday - 1));
    final nextMonday = DateTime(monday.year, monday.month, monday.day + 7);
    final weekDoses = ScheduleService.dosesBetween(rx, monday, nextMonday)
        .where((d) => store.counts(d.key, d.at))
        .toList();
    final weekTaken = weekDoses.where((d) => store.eventFor(d.key)?.status == DoseStatus.taken).length;

    final today = ScheduleService.dosesOnDay(rx, now);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('${context.tr('hello')}, ${patient.firstName}',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () => store.setLanguage(store.language == 'en' ? 'sw' : 'en'),
              child: Text(store.language == 'en' ? 'EN | sw' : 'en | SW'),
            ),
            PopupMenuButton<String>(
              tooltip: context.tr('account'),
              icon: const Icon(Icons.account_circle_outlined),
              onSelected: (v) async {
                if (v == 'signOut') {
                  await scope.alarms.stopAll();
                  await store.signOut();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text('${context.tr('signedInAs', {'name': patient.name})}\n${patient.patientNumber}'),
                ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(value: 'signOut', child: Text(context.tr('signOut'))),
              ],
            ),
          ],
        ),
        Text(_cycleLine(context, rx), style: theme.textTheme.bodyMedium),
        if (store.rxChanged) ...[
          const SizedBox(height: 12),
          InfoCard(
            color: StatusColors.warn,
            child: Row(
              children: [
                const Icon(Icons.medication_outlined),
                const SizedBox(width: 12),
                Expanded(child: Text(context.tr('rxUpdated'))),
                TextButton(onPressed: store.dismissRxNotice, child: Text(context.tr('dismiss'))),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('thisWeek'), style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(context.tr('dosesTaken', {'a': weekTaken, 'b': weekDoses.length}),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: weekDoses.isEmpty ? 0 : weekTaken / weekDoses.length,
                  minHeight: 6,
                  color: StatusColors.good,
                ),
              ),
            ],
          ),
        ),
        SectionTitle(context.tr('todaysDoses')),
        if (today.isEmpty) Text(context.tr('noDosesToday')),
        for (final d in today) _DoseTile(dose: d),
        const SizedBox(height: 20),
        FilledButton.tonal(
          onPressed: onReport,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: Text(context.tr('reportSideEffect')),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          icon: const Icon(Icons.alarm),
          label: Text(context.tr('testAlarm')),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final msg = context.tr('testAlarmSet');
            await scope.alarms.setTestAlarm();
            messenger.showSnackBar(SnackBar(content: Text(msg)));
          },
        ),
      ],
    );
  }
}

class _DoseTile extends StatelessWidget {
  const _DoseTile({required this.dose});

  final ScheduledDose dose;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    final event = store.eventFor(dose.key);
    final snoozed = event == null && store.snoozes.containsKey(dose.key);
    final label = snoozed ? context.tr('snoozed') : context.tr(statusKey(event?.status));
    final color = snoozed ? StatusColors.warn : colorFor(event?.status);
    final canAnswer = event == null && dose.at.isBefore(DateTime.now().add(const Duration(hours: 1)));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // A patient who silenced the alarm can still log the dose here.
        onTap: canAnswer
            ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => RingScreen(doseKey: dose.key),
                ))
            : null,
        child: InfoCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dose.item.drugName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    Text('${formatTime(dose.at)} · ${dose.item.dose}'),
                  ],
                ),
              ),
              StatusChip(label: label, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
