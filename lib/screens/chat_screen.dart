import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../l10n/strings.dart';
import '../models/models.dart';

/// Patient <-> care team messages. Stored in Firestore `messages`; written
/// offline they are queued by Firestore and sent when the phone reconnects.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final p = AppScope.read(context).store.patient;
    final text = _text.text.trim();
    if (p == null || text.isEmpty) return;
    _text.clear();
    // Not awaited: offline, Firestore keeps it queued and sends later.
    FirebaseFirestore.instance.collection('messages').add({
      'patientNumber': p.patientNumber,
      'patientName': p.name,
      'from': 'patient',
      'text': text,
      'at': DateTime.now().toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = AppScope.of(context).store.patient!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('askPharmacist'))),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('messages')
                  .where('patientNumber', isEqualTo: p.patientNumber)
                  .snapshots(),
              builder: (context, snap) {
                final docs = [...?snap.data?.docs]
                  ..sort((a, b) => (a.data()['at'] as String? ?? '').compareTo(b.data()['at'] as String? ?? ''));
                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(context.tr('chatEmpty'), textAlign: TextAlign.center),
                    ),
                  );
                }
                return ListView(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final d in docs.reversed)
                      _Bubble(
                        text: d.data()['text'] as String? ?? '',
                        mine: d.data()['from'] == 'patient',
                        meta: [
                          if (d.data()['from'] != 'patient') d.data()['staff'] as String? ?? context.tr('careTeam'),
                          _time(d.data()['at'] as String?),
                          if (d.metadata.hasPendingWrites) context.tr('waitingSync'),
                        ].join(' · '),
                      ),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(hintText: context.tr('chatHint')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(context.tr('chatNotEmergency'), style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  static String _time(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso);
    return d == null ? '' : '${formatDay(d)} ${formatTime(d)}';
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.mine, required this.meta});

  final String text;
  final bool mine;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text),
            const SizedBox(height: 4),
            Text(meta, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
