import 'dart:convert';

import 'package:alarm/alarm.dart';

import '../data/local_store.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import 'schedule_service.dart';

/// Schedules real alarms on the phone with Android's AlarmManager (through
/// the `alarm` package). Alarms are stored by the operating system, so they
/// ring with no internet, with the app closed, and after a reboot.
class AlarmService {
  AlarmService(this.store);

  final LocalStore store;

  /// How far ahead alarms are kept armed. Re-armed every time the app opens.
  static const window = Duration(days: 7);

  /// If the patient doesn't respond, ring again after this long.
  static const repeatAfter = Duration(minutes: 15);

  static const snoozeFor = Duration(minutes: 10);

  /// After this long with no answer the dose is logged as "no response"
  /// and a caregiver alert is queued (if the patient consented).
  static const noResponseAfter = Duration(minutes: 30);

  static const testAlarmId = 7;

  // FNV-1a hash so a dose always maps to the same alarm id.
  static int _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  static int primaryId(String doseKey) => (_hash(doseKey) & 0x3FFFFFFF) | 0x100;
  static int repeatId(String doseKey) => primaryId(doseKey) | 0x40000000;

  static String? doseKeyOf(AlarmSettings a) {
    final p = a.payload;
    if (p == null) return null;
    try {
      return (jsonDecode(p) as Map<String, dynamic>)['doseKey'] as String?;
    } catch (_) {
      return null;
    }
  }

  AlarmSettings _settings({
    required int id,
    required DateTime at,
    required ScheduledDose dose,
    required bool repeat,
    String? payload,
  }) {
    final lang = store.language;
    return AlarmSettings(
      id: id,
      dateTime: at,
      loopAudio: true,
      vibrate: true,
      androidFullScreenIntent: true,
      warningNotificationOnKill: false,
      volumeSettings: VolumeSettings.fade(
        volume: 0.9,
        fadeDuration: const Duration(seconds: 5),
      ),
      // Privacy: show the drug only, never the diagnosis.
      notificationSettings: NotificationSettings(
        title: Strings.get(lang, repeat ? 'alarmRepeatTitle' : 'alarmTitle'),
        body: '${dose.item.drugName} · ${dose.item.dose}',
      ),
      payload: payload ?? jsonEncode({'doseKey': dose.key, 'repeat': repeat}),
    );
  }

  ScheduledDose? findDose(String doseKey) {
    final p = store.prescription;
    if (p == null) return null;
    final parts = doseKey.split('_');
    if (parts.length < 3) return null;
    final day = DateTime.tryParse(parts[1]);
    if (day == null) return null;
    for (final d in ScheduleService.dosesOnDay(p, day)) {
      if (d.key == doseKey) return d;
    }
    return null;
  }

  /// Log doses nobody answered, then make the armed alarms match the
  /// schedule for the next [window].
  Future<void> sync() async {
    final p = store.prescription;
    if (p == null || !store.onboarded) return;
    await reconcile();

    final now = DateTime.now();
    final doses = ScheduleService.dosesBetween(p, now.subtract(const Duration(hours: 2)), now.add(window));
    final wanted = <int, AlarmSettings>{};
    for (final d in doses) {
      if (store.eventFor(d.key) != null) continue;
      final primaryAt = store.snoozes[d.key] ?? d.at;
      if (primaryAt.isAfter(now)) {
        wanted[primaryId(d.key)] = _settings(id: primaryId(d.key), at: primaryAt, dose: d, repeat: false);
      }
      final repeatAt = primaryAt.add(repeatAfter);
      if (repeatAt.isAfter(now)) {
        wanted[repeatId(d.key)] = _settings(id: repeatId(d.key), at: repeatAt, dose: d, repeat: true);
      }
    }

    final existing = await Alarm.getAlarms();
    final existingTimes = <int, DateTime>{for (final a in existing) a.id: a.dateTime};
    for (final a in existing) {
      // Only manage dose alarms here; leave test and care-team alarms alone.
      final k = doseKeyOf(a);
      if (a.id == testAlarmId || k == null || k == 'test') continue;
      if (!wanted.containsKey(a.id) && !await Alarm.isRinging(a.id)) {
        await Alarm.stop(a.id);
      }
    }
    for (final e in wanted.entries) {
      final had = existingTimes[e.key];
      if (had != null && had.difference(e.value.dateTime).inSeconds.abs() < 60) continue;
      try {
        await Alarm.set(alarmSettings: e.value);
      } catch (_) {
        // A failed arm is retried on the next sync.
      }
    }
  }

  /// Mark doses with no answer after [noResponseAfter] and queue a
  /// caregiver alert. Runs whenever the app opens; the backend will do this
  /// in real time in phase 2.
  Future<void> reconcile() async {
    final p = store.prescription;
    final since = store.onboardedAt;
    if (p == null || since == null) return;
    final now = DateTime.now();
    final from = since.isAfter(now.subtract(const Duration(days: 3)))
        ? since
        : now.subtract(const Duration(days: 3));
    for (final d in ScheduleService.dosesBetween(p, from, now)) {
      if (store.eventFor(d.key) != null) continue;
      final due = store.snoozes[d.key] ?? d.at;
      if (due.add(noResponseAfter).isAfter(now)) continue;
      await store.recordDose(DoseEvent(
        doseKey: d.key,
        drugName: d.item.drugName,
        scheduledAt: d.at,
        status: DoseStatus.noResponse,
        recordedAt: now,
      ));
      final pt = store.patient;
      if (pt != null && pt.caregiverConsent && pt.caregiverName != null) {
        await store.queueCaregiverAlert(
          '${pt.caregiverName}: ${pt.firstName} has not confirmed the '
          '${formatTime(d.at)} dose of ${d.item.drugName} on ${formatDay(d.at)}.',
        );
      }
    }
  }

  Future<void> _stopDoseAlarms(String doseKey) async {
    await Alarm.stop(primaryId(doseKey));
    await Alarm.stop(repeatId(doseKey));
  }

  Future<void> markTaken(ScheduledDose d) async {
    await _stopDoseAlarms(d.key);
    await store.recordDose(DoseEvent(
      doseKey: d.key,
      drugName: d.item.drugName,
      scheduledAt: d.at,
      status: DoseStatus.taken,
      recordedAt: DateTime.now(),
    ));
  }

  Future<void> markMissed(ScheduledDose d, String reason) async {
    await _stopDoseAlarms(d.key);
    await store.recordDose(DoseEvent(
      doseKey: d.key,
      drugName: d.item.drugName,
      scheduledAt: d.at,
      status: DoseStatus.missed,
      recordedAt: DateTime.now(),
      reason: reason,
    ));
  }

  Future<void> snooze(ScheduledDose d) async {
    await _stopDoseAlarms(d.key);
    final until = DateTime.now().add(snoozeFor);
    await store.setSnooze(d.key, until);
    try {
      await Alarm.set(alarmSettings: _settings(id: primaryId(d.key), at: until, dose: d, repeat: false));
      await Alarm.set(
          alarmSettings: _settings(id: repeatId(d.key), at: until.add(repeatAfter), dose: d, repeat: true));
    } catch (_) {}
  }

  static String? careReportOf(AlarmSettings a) {
    final p = a.payload;
    if (p == null) return null;
    try {
      return (jsonDecode(p) as Map<String, dynamic>)['careAction'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Rings straight away with an urgent instruction from the care team.
  Future<void> ringCareAction(String reportId) async {
    final r = store.reportById(reportId);
    final lang = store.language;
    final type = r?.careActionType ?? 'call';
    await Alarm.set(
      alarmSettings: AlarmSettings(
        id: 0x200 + (_hash('care_$reportId') & 0xFF),
        dateTime: DateTime.now().add(const Duration(seconds: 3)),
        loopAudio: true,
        vibrate: true,
        androidFullScreenIntent: true,
        warningNotificationOnKill: false,
        volumeSettings: VolumeSettings.fade(volume: 1.0, fadeDuration: const Duration(seconds: 2)),
        notificationSettings: NotificationSettings(
          title: Strings.get(lang, 'careTitle'),
          body: Strings.get(lang, 'care_$type'),
        ),
        payload: jsonEncode({'careAction': reportId}),
      ),
    );
  }

  /// Demo helper: rings in one minute so the alarm can be shown live.
  Future<void> setTestAlarm() async {
    final p = store.prescription;
    if (p == null || p.items.isEmpty) return;
    final item = p.items.first;
    final at = DateTime.now().add(const Duration(minutes: 1));
    final dose = ScheduledDose(item, at);
    await Alarm.set(
      alarmSettings: _settings(
        id: testAlarmId,
        at: at,
        dose: dose,
        repeat: false,
        payload: jsonEncode({'doseKey': 'test', 'repeat': false}),
      ),
    );
  }

  Future<void> stopAll() => Alarm.stopAll();
}
