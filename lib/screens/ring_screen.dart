import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/alarm_service.dart';
import '../services/schedule_service.dart';
import '../widgets/common.dart';

/// Full-screen dose alarm. Opens by itself when an alarm rings, or from the
/// Today list. The patient must choose Taken, Snooze or Missed.
class RingScreen extends StatefulWidget {
  const RingScreen({super.key, this.alarm, this.doseKey});

  /// Set when opened by a ringing alarm.
  final AlarmSettings? alarm;

  /// Set when opened from the Today list.
  final String? doseKey;

  @override
  State<RingScreen> createState() => _RingScreenState();
}

class _RingScreenState extends State<RingScreen> {
  StreamSubscription<dynamic>? _sub;
  ScheduledDose? _dose;
  bool _closing = false;
  bool _loaded = false;

  String? get _key =>
      widget.doseKey ?? (widget.alarm == null ? null : AlarmService.doseKeyOf(widget.alarm!));

  bool get _isTest => _key == 'test';

  @override
  void initState() {
    super.initState();
    final alarm = widget.alarm;
    if (alarm != null) {
      // Close this screen if the alarm is stopped some other way.
      _sub = Alarm.ringing.listen((set) {
        final stillRinging = set.alarms.any((AlarmSettings a) => a.id == alarm.id);
        if (!stillRinging && !_closing && mounted) {
          _closing = true;
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final key = _key;
    if (key != null && !_isTest) _dose = AppScope.of(context).alarms.findDose(key);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _close(Future<void> Function() action) async {
    if (_closing) return;
    _closing = true;
    final nav = Navigator.of(context);
    await action();
    // Real doses: the action already stopped (or, for snooze, re-armed) the
    // alarms. Only the test alarm or an unknown dose needs stopping here.
    final alarm = widget.alarm;
    if (alarm != null && _dose == null) await Alarm.stop(alarm.id);
    if (mounted) nav.pop();
  }

  Future<void> _taken() {
    final alarms = AppScope.read(context).alarms;
    final d = _dose;
    return _close(() async {
      if (d != null) await alarms.markTaken(d);
    });
  }

  Future<void> _snooze() {
    final alarms = AppScope.read(context).alarms;
    final d = _dose;
    return _close(() async {
      if (d != null) await alarms.snooze(d);
    });
  }

  Future<void> _missed() async {
    final alarms = AppScope.read(context).alarms;
    final reasons = [
      context.tr('reasonSick'),
      context.tr('reasonRanOut'),
      context.tr('reasonAway'),
      context.tr('reasonOther'),
    ];
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(context.tr('whyMissed')),
        children: [
          for (final r in reasons)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(r),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(r)),
            ),
        ],
      ),
    );
    if (reason == null) return;
    final d = _dose;
    await _close(() async {
      if (d != null) await alarms.markMissed(d, reason);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = AppScope.of(context).store;
    final d = _dose;
    final item = d?.item ?? (store.prescription?.items.isNotEmpty == true ? store.prescription!.items.first : null);
    final at = d?.at ?? DateTime.now();
    final info = item == null ? null : ScheduleService.cycleInfo(item, at);

    return PopScope(
      canPop: widget.alarm == null,
      child: Scaffold(
        backgroundColor: theme.colorScheme.primaryContainer.withAlpha(110),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                Text(context.tr('alarmTitle'), style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(formatTime(at),
                    style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 24),
                InfoCard(
                  child: Column(
                    children: [
                      Text(item?.drugName ?? '',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      if (item != null) Text('${item.dose} · ${item.instructions}', textAlign: TextAlign.center),
                      if (info != null && info.day <= info.length)
                        Text(context.tr('cycleDay', {'c': info.cycle, 'd': info.day, 'n': info.length}),
                            style: theme.textTheme.bodySmall),
                      if (_isTest) Text(context.tr('testAlarmBody'), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _taken,
                  style: FilledButton.styleFrom(
                    backgroundColor: StatusColors.good,
                    minimumSize: const Size.fromHeight(60),
                  ),
                  child: Text(context.tr('taken'), style: const TextStyle(fontSize: 18)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _snooze,
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        child: Text(context.tr('snooze10')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _missed,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          side: const BorderSide(color: StatusColors.warn, width: 1.5),
                        ),
                        child: Text(context.tr('missed')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(context.tr('keepsRinging'), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
