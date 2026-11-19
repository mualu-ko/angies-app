import 'dart:io' show Platform;

import 'package:permission_handler/permission_handler.dart';

/// The three settings that decide whether an alarm actually rings on a real
/// Android phone. Without them, many phones delay or silence the alarm.
class PermissionService {
  static Future<bool> notificationsGranted() => Permission.notification.isGranted;

  static Future<bool> exactAlarmsGranted() async {
    if (!Platform.isAndroid) return true;
    return Permission.scheduleExactAlarm.isGranted;
  }

  static Future<bool> batteryExempt() async {
    if (!Platform.isAndroid) return true;
    return Permission.ignoreBatteryOptimizations.isGranted;
  }

  static Future<bool> requestNotifications() async =>
      (await Permission.notification.request()).isGranted;

  static Future<bool> requestExactAlarms() async {
    if (!Platform.isAndroid) return true;
    return (await Permission.scheduleExactAlarm.request()).isGranted;
  }

  static Future<bool> requestBatteryExemption() async {
    if (!Platform.isAndroid) return true;
    return (await Permission.ignoreBatteryOptimizations.request()).isGranted;
  }
}
