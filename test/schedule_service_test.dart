import 'package:angies_app/models/models.dart';
import 'package:angies_app/services/schedule_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 11, 1);
  final cyclic = PrescriptionItem(
    drugId: 'capecitabine',
    drugName: 'Capecitabine',
    dose: '3 tablets',
    instructions: 'after a meal',
    times: const ['08:00', '20:00'],
    daysOn: 14,
    daysOff: 7,
    startDate: start,
  );
  final rx = Prescription(id: 'RX', prescriber: 'Dr', issuedAt: start, items: [cyclic]);

  test('14 days on, 7 days off', () {
    expect(ScheduleService.isOnDay(cyclic, DateTime(2026, 11, 1)), isTrue); // day 1
    expect(ScheduleService.isOnDay(cyclic, DateTime(2026, 11, 14)), isTrue); // day 14
    expect(ScheduleService.isOnDay(cyclic, DateTime(2026, 11, 15)), isFalse); // rest
    expect(ScheduleService.isOnDay(cyclic, DateTime(2026, 11, 21)), isFalse); // rest
    expect(ScheduleService.isOnDay(cyclic, DateTime(2026, 11, 22)), isTrue); // cycle 2 day 1
    expect(ScheduleService.isOnDay(cyclic, DateTime(2026, 10, 31)), isFalse); // before start
  });

  test('cycle info', () {
    final info = ScheduleService.cycleInfo(cyclic, DateTime(2026, 11, 26))!;
    expect(info.cycle, 2);
    expect(info.day, 5);
    expect(info.length, 14);
  });

  test('two doses a day, in order', () {
    final doses = ScheduleService.dosesOnDay(rx, DateTime(2026, 11, 5));
    expect(doses.length, 2);
    expect(doses.first.at.hour, 8);
    expect(doses.last.at.hour, 20);
    expect(doses.first.key, 'capecitabine_2026-11-05_08:00');
  });

  test('a full 21-day cycle has 28 doses', () {
    final doses = ScheduleService.dosesBetween(rx, DateTime(2026, 11, 1), DateTime(2026, 11, 22));
    expect(doses.length, 28);
  });
}
