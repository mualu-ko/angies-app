import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'data/drug_library.dart';
import 'data/local_store.dart';
import 'data/mock_hospital_api.dart';
import 'screens/care_action_screen.dart';
import 'screens/home_shell.dart';
import 'screens/permissions_screen.dart';
import 'screens/ring_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/alarm_service.dart';
import 'services/sync_service.dart';

class AngiesApp extends StatefulWidget {
  const AngiesApp({
    super.key,
    required this.store,
    required this.alarms,
    required this.library,
    required this.api,
    required this.sync,
  });

  final LocalStore store;
  final AlarmService alarms;
  final DrugLibrary library;
  final MockHospitalApi api;
  final SyncService sync;

  @override
  State<AngiesApp> createState() => _AngiesAppState();
}

class _AngiesAppState extends State<AngiesApp> {
  final _navKey = GlobalKey<NavigatorState>();
  StreamSubscription<dynamic>? _ringSub;
  final Set<int> _openRingScreens = {};

  @override
  void initState() {
    super.initState();
    // Fires when an alarm starts ringing, including when the alarm itself
    // launched the app from the lock screen.
    _ringSub = Alarm.ringing.listen((set) {
      for (final AlarmSettings a in set.alarms) {
        _showRingScreen(a);
      }
    });
  }

  void _showRingScreen(AlarmSettings a) {
    if (_openRingScreens.contains(a.id)) return;
    final nav = _navKey.currentState;
    if (nav == null) {
      // App still starting: try again on the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => _showRingScreen(a));
      return;
    }
    _openRingScreens.add(a.id);
    final careReport = AlarmService.careReportOf(a);
    nav
        .push(MaterialPageRoute<void>(
          builder: (_) => careReport != null
              ? CareActionScreen(reportId: careReport, alarm: a)
              : RingScreen(alarm: a),
        ))
        .then((_) => _openRingScreens.remove(a.id));
  }

  @override
  void dispose() {
    _ringSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, child) => AppScope(
        store: widget.store,
        alarms: widget.alarms,
        library: widget.library,
        api: widget.api,
        sync: widget.sync,
        revision: widget.store.revision,
        child: child!,
      ),
      child: MaterialApp(
        navigatorKey: _navKey,
        title: "Angie's App",
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6FB0)),
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        ),
        home: const StartGate(),
      ),
    );
  }
}

/// Picks the first screen: sign in, permissions, or the main app.
class StartGate extends StatelessWidget {
  const StartGate({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    if (!store.signedIn) return const SignInScreen();
    if (!store.onboarded) return const PermissionsScreen();
    return const HomeShell();
  }
}
