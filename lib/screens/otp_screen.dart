import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../l10n/strings.dart';
import 'confirm_details_screen.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.patientNumber, required this.phone});

  final String patientNumber;
  final String phone;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String get _maskedPhone {
    final d = widget.phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length < 3) return widget.phone;
    return '•••• ••• ${d.substring(d.length - 3)}';
  }

  Future<void> _verify() async {
    final api = AppScope.read(context).api;
    setState(() {
      _busy = true;
      _error = null;
    });
    final record = await api.verifyOtp(widget.patientNumber, widget.phone, _code.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (record == null) {
      setState(() => _error = context.tr('wrongCode'));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ConfirmDetailsScreen(record: record),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(context.tr('enterCode'), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('${context.tr('codeSentTo')} $_maskedPhone'),
          const SizedBox(height: 24),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofocus: true,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, letterSpacing: 12, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(counterText: ''),
            onSubmitted: (_) => _verify(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _verify,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.tr('verify')),
          ),
        ],
      ),
    );
  }
}
