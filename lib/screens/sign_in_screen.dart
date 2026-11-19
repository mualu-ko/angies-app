import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/mock_hospital_api.dart';
import '../l10n/strings.dart';
import 'otp_screen.dart';

/// Patients sign in with the patient number on their clinic card plus the
/// phone number the hospital has on record.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _number = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final scope = AppScope.read(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await scope.api.requestOtp(_number.text, _phone.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      setState(() => _error = context.tr('notFound'));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('demoCode', {'code': MockHospitalApi.demoOtp}))),
    );
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => OtpScreen(patientNumber: _number.text, phone: _phone.text),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 32),
            Center(
              child: CircleAvatar(
                radius: 36,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(Icons.medication_outlined, size: 36, color: theme.colorScheme.primary),
              ),
            ),
            const SizedBox(height: 16),
            Text(context.tr('appName'),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text(context.tr('tagline'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 32),
            TextField(
              controller: _number,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: context.tr('patientNumber'),
                helperText: context.tr('patientNumberHint'),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: context.tr('phoneNumber'), hintText: '0712 345 678'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(context.tr('sendCode')),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(onPressed: () => store.setLanguage('en'), child: const Text('English')),
                const Text('|'),
                TextButton(onPressed: () => store.setLanguage('sw'), child: const Text('Kiswahili')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
