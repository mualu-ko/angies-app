import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/common.dart';
import 'portal_widgets.dart';

/// Side effect (ADR) review queue. Severe, unreviewed reports come first.
class AdrPage extends StatelessWidget {
  const AdrPage({super.key, required this.staff});

  final String staff;

  static int _rank(Map<String, dynamic> r) {
    final isNew = (r['status'] ?? 'new') == 'new';
    if (isNew && r['severity'] == 'severe') return 0;
    if (isNew) return 1;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('adrReports').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Could not load reports: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs.toList()
          ..sort((a, b) => _rank(a.data()).compareTo(_rank(b.data())));
        final urgent = docs.where((d) => _rank(d.data()) == 0).length;
        final waiting = docs.where((d) => (d.data()['status'] ?? 'new') == 'new').length;
        final forwarded = docs.where((d) => d.data()['status'] == 'forwarded').length;

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(children: [
              StatCard(label: 'Urgent (severe, not reviewed)', value: '$urgent', color: urgent > 0 ? StatusColors.crit : null),
              const SizedBox(width: 16),
              StatCard(label: 'Awaiting review', value: '$waiting'),
              const SizedBox(width: 16),
              StatCard(label: 'Reported to PPB', value: '$forwarded'),
            ]),
            const SizedBox(height: 24),
            if (docs.isEmpty) const Text('No side effect reports yet. Send one from the patient app.'),
            for (final d in docs) _ReportRow(doc: d, staff: staff),
          ],
        );
      },
    );
  }
}

Color severityColor(String? s) => s == 'severe'
    ? StatusColors.crit
    : s == 'moderate'
        ? StatusColors.warn
        : StatusColors.good;

String statusLabel(String? s) {
  switch (s) {
    case 'reviewed':
      return 'Reviewed';
    case 'confirmed':
      return 'Confirmed ADR';
    case 'forwarded':
      return 'Reported to PPB';
    default:
      return 'New';
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.doc, required this.staff});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String staff;

  @override
  Widget build(BuildContext context) {
    final r = doc.data();
    final symptoms = [
      ...((r['symptoms'] as List?) ?? const []).cast<String>(),
      if ((r['otherSymptom'] as String?)?.isNotEmpty == true) r['otherSymptom'] as String,
    ].join(', ');
    final isNew = (r['status'] ?? 'new') == 'new';
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Text('${r['patientName'] ?? ''} · ${r['drugName'] ?? ''}',
            style: TextStyle(fontWeight: isNew ? FontWeight.w700 : FontWeight.w500)),
        subtitle: Text('$symptoms\nReported ${timeAgo(r['createdAt'] as String?)} · ${statusLabel(r['status'] as String?)}'),
        isThreeLine: true,
        trailing: Pill((r['severity'] as String? ?? '').toUpperCase(), color: severityColor(r['severity'] as String?)),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => _ReportDialog(ref: doc.reference, data: r, staff: staff),
        ),
      ),
    );
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.ref, required this.data, required this.staff});

  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic> data;
  final String staff;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  late final TextEditingController _reply = TextEditingController(text: widget.data['reply'] as String? ?? '');
  late String _status = widget.data['status'] as String? ?? 'new';
  bool _saving = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _save(String status) async {
    setState(() => _saving = true);
    final now = DateTime.now().toIso8601String();
    await widget.ref.update({
      'status': status,
      'reply': _reply.text.trim().isEmpty ? null : _reply.text.trim(),
      'reviewedBy': widget.staff,
      'reviewedAt': now,
      if (status == 'forwarded') 'forwardedAt': now,
    });
    if (!mounted) return;
    setState(() {
      _status = status;
      _saving = false;
    });
    if (status == 'forwarded') await _showPpbExport();
  }

  static const _careLabels = {
    'call': 'Call the patient now',
    'clinic': 'Ask to come to clinic today',
    'emergency': 'Go to emergency now',
    'ambulance': 'Request ambulance',
  };

  /// Sends an urgent instruction: the patient's phone rings with it and
  /// shows a full-screen message until they tap "I understand".
  Future<void> _sendCare(String type) async {
    if (type == 'ambulance') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Request an ambulance?'),
          content: const Text(
              'The patient will be told an ambulance has been requested and to stay where they are.\n\n'
              'Demo: this is NOT connected to a dispatch service. Call the ambulance provider yourself.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: StatusColors.crit),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Request ambulance'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final now = DateTime.now().toIso8601String();
    await widget.ref.update({
      'careAction': {
        'id': 'CA-${DateTime.now().millisecondsSinceEpoch}',
        'type': type,
        'label': _careLabels[type],
        'by': widget.staff,
        'at': now,
        'ackAt': null,
      },
      'careHistory': FieldValue.arrayUnion([
        {'type': type, 'by': widget.staff, 'at': now},
      ]),
      if (_status == 'new') 'status': 'reviewed',
      if (_status == 'new') 'reviewedBy': widget.staff,
      if (_status == 'new') 'reviewedAt': now,
    });
    if (mounted && _status == 'new') setState(() => _status = 'reviewed');
  }

  Widget _careSection(Map<String, dynamic> r) {
    final care = r['careAction'];
    final phone = r['patientPhone'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 28),
        const Text('Action to take', style: TextStyle(fontWeight: FontWeight.w700)),
        if (phone != null) Text('Patient phone: $phone'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in _careLabels.entries)
            (e.key == 'emergency' || e.key == 'ambulance')
                ? FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: StatusColors.crit),
                    onPressed: () => _sendCare(e.key),
                    icon: Icon(e.key == 'ambulance' ? Icons.emergency_share : Icons.local_hospital, size: 18),
                    label: Text(e.value),
                  )
                : OutlinedButton.icon(
                    onPressed: () => _sendCare(e.key),
                    icon: Icon(e.key == 'call' ? Icons.phone : Icons.event_available, size: 18),
                    label: Text(e.value),
                  ),
        ]),
        if (care is Map) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (care['ackAt'] == null ? StatusColors.warn : StatusColors.good).withAlpha(30),
              border: Border.all(color: care['ackAt'] == null ? StatusColors.warn : StatusColors.good),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${care['label']} · sent by ${care['by']} ${timeAgo(care['at'] as String?)}\n'
              '${care['ackAt'] == null ? 'Waiting for the patient to acknowledge' : 'Patient acknowledged ${timeAgo(care['ackAt'] as String?)}'}'
              '${care['type'] == 'ambulance' ? '\nDemo: no dispatch service connected.' : ''}',
            ),
          ),
        ],
      ],
    );
  }

  /// Plain-text summary for the PPB's online reporting form. Patient is
  /// identified by initials only.
  String get _ppbText {
    final r = widget.data;
    final symptoms = [
      ...((r['symptoms'] as List?) ?? const []).cast<String>(),
      if ((r['otherSymptom'] as String?)?.isNotEmpty == true) r['otherSymptom'] as String,
    ].join(', ');
    return [
      'SUSPECTED ADVERSE DRUG REACTION',
      'Patient: ${initials(r['patientName'] as String? ?? '')} (${r['patientNumber']})',
      'Suspected medicine: ${r['drugName']}',
      'Reaction: $symptoms',
      'Onset: ${r['onset']}',
      'Severity: ${r['severity']}',
      'Action taken by patient: ${r['actionTaken']}',
      'Reported by patient: ${r['createdAt']}',
      'Confirmed by: ${widget.staff}',
    ].join('\n');
  }

  Future<void> _showPpbExport() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('PPB report'),
          content: SizedBox(width: 480, child: SelectableText(_ppbText)),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: _ppbText)),
              child: const Text('Copy'),
            ),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Done')),
          ],
        ),
      );

  Widget _field(String label, Object? value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 150, child: Text(label, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text('${value ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    // Live copy, so the acknowledgement appears as soon as the patient taps OK.
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: widget.ref.snapshots(),
      builder: (context, snap) => _dialog(snap.data?.data() ?? widget.data),
    );
  }

  Widget _dialog(Map<String, dynamic> r) {
    final symptoms = [
      ...((r['symptoms'] as List?) ?? const []).cast<String>(),
      if ((r['otherSymptom'] as String?)?.isNotEmpty == true) r['otherSymptom'] as String,
    ].join(', ');
    return AlertDialog(
      title: Row(children: [
        Expanded(child: Text('Side effect report · ${r['patientName']}')),
        Pill(statusLabel(_status), color: _status == 'new' ? StatusColors.warn : StatusColors.good),
      ]),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (r['severity'] == 'severe')
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: StatusColors.crit.withAlpha(30),
                    border: Border.all(color: StatusColors.crit),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Severe reaction: the patient was told to seek urgent care. Choose an action below.'),
                ),
              _field('Patient number', r['patientNumber']),
              _field('Medicine', r['drugName']),
              _field('Symptoms', symptoms),
              _field('Started', r['onset']),
              _field('Severity', r['severity']),
              _field('Patient action', r['actionTaken']),
              _field('Reported', timeAgo(r['createdAt'] as String?)),
              if (r['reviewedBy'] != null) _field('Last reviewed by', r['reviewedBy']),
              const SizedBox(height: 12),
              TextField(
                controller: _reply,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reply to the patient',
                  hintText: 'e.g. Please come to clinic tomorrow so we can check your hands.',
                ),
              ),
              _careSection(r),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        OutlinedButton(onPressed: _saving ? null : () => _save('reviewed'), child: const Text('Send reply · Reviewed')),
        OutlinedButton(onPressed: _saving ? null : () => _save('confirmed'), child: const Text('Confirm ADR')),
        FilledButton(
          onPressed: _saving || (_status != 'confirmed' && _status != 'forwarded') ? null : () => _save('forwarded'),
          child: const Text('Forward to PPB'),
        ),
      ],
    );
  }
}
