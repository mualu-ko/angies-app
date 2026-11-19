import 'package:flutter/widgets.dart';

import 'data/drug_library.dart';
import 'data/local_store.dart';
import 'data/mock_hospital_api.dart';
import 'services/alarm_service.dart';
import 'services/sync_service.dart';

/// Gives every screen access to the shared services.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.store,
    required this.alarms,
    required this.library,
    required this.api,
    required this.sync,
    required this.revision,
    required super.child,
  });

  final LocalStore store;
  final AlarmService alarms;
  final DrugLibrary library;
  final MockHospitalApi api;
  final SyncService sync;

  /// Bumped on every store change so screens rebuild.
  final int revision;

  /// Use in build methods: the widget rebuilds when the store changes.
  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!;
  }

  /// Use in initState and callbacks: no rebuild dependency.
  static AppScope read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => revision != oldWidget.revision;
}
