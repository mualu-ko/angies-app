import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../l10n/strings.dart';
import '../services/permission_service.dart';

/// Asks for the settings that let alarms ring reliably, then arms them.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> with WidgetsBindingObserver {
  bool _notif = false;
  bool _exact = false;
  bool _battery = false;
  bool _busy = false;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Some permissions open the phone's settings; re-check when the user returns.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final n = await PermissionService.notificationsGranted();
    final e = await PermissionService.exactAlarmsGranted();
    final b = await PermissionService.batteryExempt();
    if (!mounted) return;
    setState(() {
      _notif = n;
      _exact = e;
      _battery = b;
    });
  }

  Future<void> _finish() async {
    final scope = AppScope.read(context);
    setState(() => _busy = true);
    // The home screen arms the alarms as soon as it opens.
    await scope.store.completeOnboarding();
  }

  Widget _tile(String title, String body, bool granted, Future<bool> Function() request) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(body),
        trailing: granted
            ? Chip(label: Text(context.tr('allowed')), avatar: const Icon(Icons.check, size: 18))
            : FilledButton.tonal(
                // Android allows one permission request at a time.
                onPressed: _requesting
                    ? null
                    : () async {
                        setState(() => _requesting = true);
                        try {
                          await request();
                        } catch (_) {
                          // Ignore; the tile simply stays on "Allow".
                        }
                        if (mounted) setState(() => _requesting = false);
                        await _refresh();
                      },
                child: Text(context.tr('allow')),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 16),
            Text(context.tr('permTitle'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(context.tr('permBody')),
            const SizedBox(height: 24),
            _tile(context.tr('permNotif'), context.tr('permNotifBody'), _notif,
                PermissionService.requestNotifications),
            _tile(context.tr('permExact'), context.tr('permExactBody'), _exact,
                PermissionService.requestExactAlarms),
            _tile(context.tr('permBattery'), context.tr('permBatteryBody'), _battery,
                PermissionService.requestBatteryExemption),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _finish,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text(context.tr('continue')),
            ),
          ],
        ),
      ),
    );
  }
}
