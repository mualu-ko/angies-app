import '../models/models.dart';

/// One dose the patient is due to take.
class ScheduledDose {
  const ScheduledDose(this.item, this.at);

  final PrescriptionItem item;
  final DateTime at;

  /// Stable key, e.g. "capecitabine_2026-11-19_08:00".
  String get key => '${item.drugId}_${formatDate(at)}_${two(at.hour)}:${two(at.minute)}';
}

class CycleInfo {
  const CycleInfo(this.cycle, this.day, this.length);
  final int cycle;
  final int day;
  final int length;
}

/// Turns a prescription into concrete dose times, following on/off cycles.
class ScheduleService {
  static int _dayIndex(PrescriptionItem item, DateTime day) {
    final a = DateTime.utc(item.startDate.year, item.startDate.month, item.startDate.day);
    final b = DateTime.utc(day.year, day.month, day.day);
    return b.difference(a).inDays;
  }

  /// True if the medicine should be taken on [day].
  static bool isOnDay(PrescriptionItem item, DateTime day) {
    final i = _dayIndex(item, day);
    if (i < 0) return false;
    if (item.daysOff <= 0) return true;
    return i % (item.daysOn + item.daysOff) < item.daysOn;
  }

  /// Cycle number and day within the "on" part, or null for continuous
  /// medicines and before the start date.
  static CycleInfo? cycleInfo(PrescriptionItem item, DateTime day) {
    final i = _dayIndex(item, day);
    if (i < 0 || item.daysOff <= 0) return null;
    final length = item.daysOn + item.daysOff;
    return CycleInfo(i ~/ length + 1, i % length + 1, item.daysOn);
  }

  static List<ScheduledDose> dosesOnDay(Prescription p, DateTime day) {
    final result = <ScheduledDose>[];
    for (final item in p.items) {
      if (!isOnDay(item, day)) continue;
      for (final t in item.times) {
        final parts = t.split(':');
        final at = DateTime(day.year, day.month, day.day, int.parse(parts[0]), int.parse(parts[1]));
        result.add(ScheduledDose(item, at));
      }
    }
    result.sort((a, b) => a.at.compareTo(b.at));
    return result;
  }

  /// All doses with a time in [from, to).
  static List<ScheduledDose> dosesBetween(Prescription p, DateTime from, DateTime to) {
    final result = <ScheduledDose>[];
    var day = dateOnly(from);
    while (!day.isAfter(to)) {
      for (final d in dosesOnDay(p, day)) {
        if (!d.at.isBefore(from) && d.at.isBefore(to)) result.add(d);
      }
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return result;
  }
}
