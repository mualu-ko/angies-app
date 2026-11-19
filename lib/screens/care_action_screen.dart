import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../l10n/strings.dart';
import '../widgets/common.dart';

/// Full-screen urgent instruction from a clinician (call, come to clinic,
/// go to emergency, ambulance requested). Rings like a dose alarm until the
/// patient taps "I understand"; the clinician sees the acknowledgement.
class CareActionScreen extends StatefulWidget {
  const CareActionScreen({super.key, required this.reportId, this.alarm});

  final String reportId;
  final AlarmSettings? alarm;

  @override
  State<CareActionScreen> createState() => _CareActionScreenState();
}

class _CareActionScreenState extends State<CareActionScreen> {
  bool _closing = false;

  static IconData _icon(String type) {
    switch (type) {
      case 'ambulance':
        return Icons.emergency_share;
      case 'emergency':
        return Icons.local_hospital;
      case 'clinic':
        return Icons.event_available;
      default:
        return Icons.phone_in_talk;
    }
  }

  Future<void> _ack() async {
    if (_closing) return;
    _closing = true;
    final scope = AppScope.read(context);
    final nav = Navigator.of(context);
    final alarm = widget.alarm;
    if (alarm != null) await Alarm.stop(alarm.id);
    await scope.sync.acknowledgeCare(widget.reportId);
    if (mounted) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    final report = store.reportById(widget.reportId);
    final type = report?.careActionType ?? 'call';
    final urgent = type == 'emergency' || type == 'ambulance';
    final color = urgent ? StatusColors.crit : StatusColors.warn;
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: color.withAlpha(40),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                Icon(_icon(type), size: 72, color: color),
                const SizedBox(height: 16),
                Text(context.tr('careTitle'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                InfoCard(
                  color: color,
                  child: Text(context.tr('care_$type'),
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, height: 1.4)),
                ),
                if (report != null) ...[
                  const SizedBox(height: 12),
                  Text('${report.drugName} · ${report.summary}',
                      textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                ],
                const Spacer(),
                FilledButton(
                  onPressed: _ack,
                  style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size.fromHeight(60)),
                  child: Text(context.tr('iUnderstand'), style: const TextStyle(fontSize: 18)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
