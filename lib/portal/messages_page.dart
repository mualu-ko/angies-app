import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/common.dart';
import 'portal_widgets.dart';

/// Conversations with patients. A conversation whose latest message is from
/// the patient is waiting for a reply and is listed first.
class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key, required this.staff});

  final String staff;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  String? _patient;
  final _reply = TextEditingController();

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send(String pn, String name) async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    _reply.clear();
    await FirebaseFirestore.instance.collection('messages').add({
      'patientNumber': pn,
      'patientName': name,
      'from': 'staff',
      'staff': widget.staff,
      'text': text,
      'at': DateTime.now().toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('messages').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Could not load messages: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());

        final threads = <String, List<Map<String, dynamic>>>{};
        for (final d in snap.data!.docs) {
          final m = d.data();
          threads.putIfAbsent(m['patientNumber'] as String? ?? '', () => []).add(m);
        }
        for (final t in threads.values) {
          t.sort((a, b) => (a['at'] as String? ?? '').compareTo(b['at'] as String? ?? ''));
        }
        bool waiting(List<Map<String, dynamic>> t) => t.last['from'] == 'patient';
        final order = threads.keys.toList()
          ..sort((a, b) {
            final w = (waiting(threads[a]!) ? 0 : 1).compareTo(waiting(threads[b]!) ? 0 : 1);
            if (w != 0) return w;
            return (threads[b]!.last['at'] as String).compareTo(threads[a]!.last['at'] as String);
          });

        if (order.isEmpty) {
          return const Center(child: Text('No messages yet. Patients write from the Drugs tab: "Ask a pharmacist".'));
        }
        final selected = threads.containsKey(_patient) ? _patient! : order.first;
        final thread = threads[selected]!;
        final name = thread.first['patientName'] as String? ?? selected;

        return Row(
          children: [
            SizedBox(
              width: 300,
              child: ListView(
                children: [
                  for (final pn in order)
                    ListTile(
                      selected: pn == selected,
                      title: Text('${threads[pn]!.first['patientName'] ?? pn}'),
                      subtitle: Text(threads[pn]!.last['text'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: waiting(threads[pn]!) ? const Pill('Reply', color: StatusColors.warn) : null,
                      onTap: () => setState(() => _patient = pn),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  ListTile(
                    title: Text('$name ($selected)', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Not for emergencies: use the Side effects page actions for urgent care.'),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final m in thread)
                          Align(
                            alignment: m['from'] == 'staff' ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 480),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: m['from'] == 'staff'
                                    ? Theme.of(context).colorScheme.primaryContainer
                                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m['text'] as String? ?? ''),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${m['from'] == 'staff' ? m['staff'] : name} · ${timeAgo(m['at'] as String?)}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _reply,
                            decoration: const InputDecoration(hintText: 'Reply to the patient'),
                            onSubmitted: (_) => _send(selected, name),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(onPressed: () => _send(selected, name), child: const Text('Send')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
