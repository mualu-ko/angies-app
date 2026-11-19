import 'package:flutter/material.dart';

import '../models/models.dart';
import 'common.dart';

class DayAdherence {
  const DayAdherence(this.day, this.taken, this.total);

  final DateTime day;
  final int taken;
  final int total;

  double? get ratio => total == 0 ? null : taken / total;
}

/// One bar per day: height = share of that day's doses taken.
/// Green 80% or more, amber 50–79%, red under 50%, grey = no doses due.
/// Used by the patient app (History) and the clinician portal (Patients).
class AdherenceChart extends StatelessWidget {
  const AdherenceChart({super.key, required this.days, this.height = 90});

  final List<DayAdherence> days;
  final double height;

  static Color colorFor(double? r) {
    if (r == null) return Colors.grey.shade300;
    if (r >= 0.8) return StatusColors.good;
    if (r >= 0.5) return StatusColors.warn;
    return StatusColors.crit;
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in days)
                Expanded(
                  child: Tooltip(
                    message: d.total == 0 ? '${formatDay(d.day)}: no doses' : '${formatDay(d.day)}: ${d.taken} of ${d.total} taken',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Container(
                        height: d.ratio == null ? 4 : (height * d.ratio!).clamp(4, height).toDouble(),
                        decoration: BoxDecoration(
                          color: colorFor(d.ratio),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final d in days)
              Expanded(child: Text('${d.day.day}', textAlign: TextAlign.center, style: small?.copyWith(fontSize: 10))),
          ],
        ),
      ],
    );
  }
}
