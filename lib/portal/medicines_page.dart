import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/drug_library.dart';
import '../widgets/common.dart';
import 'portal_widgets.dart';

/// Medicines patients told us about (chemist, other clinic, herbal). The
/// pharmacist sees any interaction with the patient's cancer medicine, then
/// approves it or flags it for a conversation.
class MedicinesPage extends StatelessWidget {
  const MedicinesPage({super.key, required this.library, required this.staff});

  final DrugLibrary library;
  final String staff;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('medicineReports').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Could not load: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs.toList()
          ..sort((a, b) => ((a.data()['status'] == 'pending') ? 0 : 1).compareTo((b.data()['status'] == 'pending') ? 0 : 1));
        final pending = docs.where((d) => d.data()['status'] == 'pending').length;
        final withAlerts = docs.where((d) => d.data()['status'] == 'pending' && _alertsFor(d.data()).isNotEmpty).length;

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(children: [
              StatCard(label: 'Waiting for a pharmacist', value: '$pending'),
              const SizedBox(width: 16),
              StatCard(
                label: 'Waiting, with an interaction',
                value: '$withAlerts',
                color: withAlerts > 0 ? StatusColors.crit : null,
              ),
            ]),
            const SizedBox(height: 24),
            if (docs.isEmpty) const Text('No medicines reported yet. Add one from the Drugs tab in the patient app.'),
            for (final d in docs) _MedicineCard(doc: d, alerts: _alertsFor(d.data()), staff: staff),
          ],
        );
      },
    );
  }

  List<String> _alertsFor(Map<String, dynamic> m) {
    final name = m['name'] as String? ?? '';
    final ids = ((m['drugIds'] as List?) ?? const []).cast<String>();
    return [
      for (final id in ids)
        for (final a in library.drugAlerts(id, [name])) '${a.severity.toUpperCase()}: ${a.advice}',
    ];
  }
}

class _MedicineCard extends StatefulWidget {
  const _MedicineCard({required this.doc, required this.alerts, required this.staff});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final List<String> alerts;
  final String staff;

  @override
  State<_MedicineCard> createState() => _MedicineCardState();
}

class _MedicineCardState extends State<_MedicineCard> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _decide(String status) async {
    final note = _note.text.trim();
    if (status == 'rejected' && note.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a note telling the patient what to do.')),
      );
      return;
    }
    await widget.doc.reference.update({
      'status': status,
      'note': note.isEmpty ? null : note,
      'reviewedBy': widget.staff,
      'reviewedAt': DateTime.now().toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.doc.data();
    final status = m['status'] as String? ?? 'pending';
    final pending = status == 'pending';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('${m['name']}  ·  ${m['patientName']} (${m['patientNumber']})',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              Pill(
                pending ? 'Pending' : (status == 'approved' ? 'Approved' : 'Flagged'),
                color: pending ? StatusColors.warn : (status == 'approved' ? StatusColors.good : StatusColors.crit),
              ),
            ]),
            Text('Reported ${timeAgo(m['createdAt'] as String?)}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            if (widget.alerts.isEmpty)
              const Text('No known interaction with this patient\'s cancer medicine in the bundled data.')
            else
              for (final a in widget.alerts)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: StatusColors.crit.withAlpha(30),
                    border: Border.all(color: StatusColors.crit),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(a),
                ),
            if (!pending) ...[
              const SizedBox(height: 6),
              Text('Decided by ${m['reviewedBy'] ?? ''}${m['note'] != null ? ': "${m['note']}"' : ''}'),
            ],
            if (pending) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Note to the patient (required when flagging)',
                  hintText: 'e.g. Please stop this and call the clinic.',
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                FilledButton(onPressed: () => _decide('approved'), child: const Text('Approve')),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => _decide('rejected'),
                  style: OutlinedButton.styleFrom(foregroundColor: StatusColors.crit),
                  child: const Text('Flag for a conversation'),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
