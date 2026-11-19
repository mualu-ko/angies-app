import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../l10n/strings.dart';
import 'drug_info_screen.dart';
import 'history_screen.dart';
import 'report_adr_screen.dart';
import 'today_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  /// Re-arms the next 7 days of alarms and logs unanswered doses.
  /// Runs offline; nothing here needs the network.
  Future<void> _sync() async {
    if (!mounted) return;
    final scope = AppScope.read(context);
    await scope.alarms.sync();
    await scope.sync.retry();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayScreen(onReport: () => setState(() => _tab = 2)),
      const DrugInfoScreen(),
      ReportAdrScreen(onSent: () => setState(() => _tab = 3)),
      const HistoryScreen(),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.today_outlined), label: context.tr('navToday')),
          NavigationDestination(icon: const Icon(Icons.medication_outlined), label: context.tr('navDrugs')),
          NavigationDestination(icon: const Icon(Icons.report_outlined), label: context.tr('navReport')),
          NavigationDestination(icon: const Icon(Icons.history), label: context.tr('navHistory')),
        ],
      ),
    );
  }
}
