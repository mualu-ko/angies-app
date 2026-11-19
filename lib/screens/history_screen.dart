import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/schedule_service.dart';
import '../widgets/adherence_chart.dart';
import '../widgets/common.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final store = scope.store;
    final rx = store.prescription!;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final since = store.onboardedAt ?? now;

    // Adherence over the last 14 days (only counting since sign-up).
    final windowStart = dateOnly(now).subtract(const Duration(days: 13));
    final from = since.isAfter(windowStart) ? dateOnly(since) : windowStart;
    final past = ScheduleService.dosesBetween(rx, from, now).where((d) => store.counts(d.key, d.at)).toList();
    final taken = past.where((d) => store.eventFor(d.key)?.status == DoseStatus.taken).length;
    final pct = past.isEmpty ? null : (taken * 100 / past.length).round();

    // Last 7 days, one dot per day.
    final days = [for (var i = 6; i >= 0; i--) dateOnly(now).subtract(Duration(days: i))];

    // 14-day chart: share of each day's due doses that were taken.
    final chart = <DayAdherence>[];
    for (var i = 13; i >= 0; i--) {
      final day = dateOnly(now).subtract(Duration(days: i));
      final due = ScheduleService.dosesOnDay(rx, day)
          .where((d) => d.at.isBefore(now) && store.counts(d.key, d.at))
          .toList();
      final ok = due.where((d) => store.eventFor(d.key)?.status == DoseStatus.taken).length;
      chart.add(DayAdherence(day, ok, due.length));
    }
    final events = [...store.doseEvents]..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(context.tr('myDoses'), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(pct == null ? '–' : '$pct%',
                style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(context.tr('takenThisCycle'))),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [for (final d in days) _DayDot(day: d)],
        ),
        SectionTitle(context.tr('last14')),
        AdherenceChart(days: chart, height: 70),
        SectionTitle(context.tr('myReports')),
        if (store.reports.isEmpty) Text(context.tr('noReports')),
        for (final r in store.reports)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InfoCard(
              color: r.severity == Severity.severe ? StatusColors.crit : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.summary, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${r.drugName} · ${context.tr(r.severity.name)} · ${formatDay(r.createdAt)}'),
                  const SizedBox(height: 4),
                  Text(
                    r.synced ? context.tr(_adrStatusKey(r.status)) : context.tr('waitingSync'),
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (r.reply != null && r.reply!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(context.tr('replyFrom'), style: theme.textTheme.bodySmall),
                    Text(r.reply!),
                  ],
                  if (r.careActionType != null) ...[
                    const SizedBox(height: 8),
                    Text(context.tr('careTitle'), style: theme.textTheme.bodySmall),
                    Text(context.tr('care_${r.careActionType}'), style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (r.careAckAt != null) Text(context.tr('careSentAck'), style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
        SectionTitle(context.tr('recentDoses')),
        for (final e in events.take(20))
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text('${e.drugName} · ${formatDay(e.scheduledAt)} ${formatTime(e.scheduledAt)}'),
            subtitle: e.reason == null ? null : Text(e.reason!),
            trailing: StatusChip(label: context.tr(statusKey(e.status)), color: colorFor(e.status)),
          ),
        if (store.caregiverOutbox.isNotEmpty) ...[
          SectionTitle(context.tr('caregiverAlerts')),
          for (final m in store.caregiverOutbox.reversed.take(5))
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(m, style: theme.textTheme.bodySmall)),
        ],
        const SizedBox(height: 24),
        TextButton(
          onPressed: () async {
            await scope.alarms.stopAll();
            await store.signOut();
          },
          child: Text(context.tr('signOut')),
        ),
      ],
    );
  }
}

String _adrStatusKey(String status) {
  switch (status) {
    case 'reviewed':
      return 'adrReviewed';
    case 'confirmed':
      return 'adrConfirmed';
    case 'forwarded':
      return 'adrForwarded';
    default:
      return 'adrNew';
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.day});

  final DateTime day;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    final doses = ScheduleService.dosesOnDay(store.prescription!, day)
        .where((d) => d.at.isBefore(DateTime.now()) && store.counts(d.key, d.at))
        .toList();
    final events = doses.map((d) => store.eventFor(d.key)).toList();
    Color color;
    if (doses.isEmpty || events.every((e) => e == null)) {
      color = Colors.grey.shade300;
    } else if (events.every((e) => e?.status == DoseStatus.taken)) {
      color = StatusColors.good;
    } else {
      color = StatusColors.warn;
    }
    return Column(
      children: [
        Text(_letters[day.weekday - 1], style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        CircleAvatar(radius: 14, backgroundColor: color),
      ],
    );
  }
}
