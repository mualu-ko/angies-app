import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/drug_library.dart';
import 'data/local_store.dart';
import 'data/mock_hospital_api.dart';
import 'firebase_options.dart';
import 'models/models.dart';
import 'services/alarm_service.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Alarm.init();
  // Works offline: Firebase starts without a connection and syncs later.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final store = await LocalStore.open();
  final library = await DrugLibrary.load();
  final alarms = AlarmService(store);
  // Portal-written drug descriptions saved on the phone from last time.
  void applyDrugInfo(Map<String, Map<String, dynamic>> cache) {
    library.remote = {
      for (final e in cache.entries)
        if (e.value['id'] is String && e.value['name'] is String) e.key: DrugInfo.fromJson(e.value),
    };
  }

  applyDrugInfo(store.drugInfoCache);
  final sync = SyncService(store)
    ..onPrescriptionChanged = alarms.sync
    ..onCareAction = alarms.ringCareAction
    ..onDrugInfo = applyDrugInfo;

  runApp(AngiesApp(
    store: store,
    alarms: alarms,
    library: library,
    api: MockHospitalApi(),
    sync: sync,
  ));
  unawaited(sync.start());
}
