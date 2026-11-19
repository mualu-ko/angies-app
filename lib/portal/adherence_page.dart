import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/drug_library.dart';
import '../models/models.dart';
import '../widgets/adherence_chart.dart';
import '../widgets/common.dart';
import 'portal_widgets.dart';
import 'prescription_dialog.dart';

/// Adherence per patient over the last 14 days, from the dose log the
/// patient app sends. Three misses in a row raise an alert.
class AdherencePage extends StatelessWidget {
  const AdherencePage({super.key, required this.library, required this.staff});

  final DrugLibrary library;
  final String staff;

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('patients').snapshots(),
      builder: (context, pSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('doseEvents').snapshots(),
          builder: (context, dSnap) {
            if (pSnap.hasError || dSnap.hasError) {
              return Center(child: Text('Could not load: ${pSnap.error ?? dSnap.error}'));
            }
            if (!pSnap.hasData || !dSnap.hasData) return const Center(child: CircularProgressIndicator());

            final since = DateTime.now().subtract(const Duration(days: 14));
            final byPatient = <String, List<Map<String, dynamic>>>{};
            for (final d in dSnap.data!.docs) {
              final e = d.data();
              final at = DateTime.tryParse(e['scheduledAt'] as String? ?? '');
              if (at == null || at.isBefore(since)) continue;
              byPatient.putIfAbsent(e['patientNumber'] as String? ?? '', () => []).add(e);
            }
            final patients = pSnap.data!.docs;
            if (patients.isEmpty) {
              return const Center(child: Text('No patients yet. Sign in on the patient app first.'));
            }

            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                for (final p in patients)
                  _PatientCard(
                    doc: p,
                    events: byPatient[p.data()['patientNumber']] ?? const [],
                    library: library,
                    staff: staff,
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.doc, required this.events, required this.library, required this.staff});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final List<Map<String, dynamic>> events;
  final DrugLibrary library;
  final String staff;

  /// Doses logged per day for the last 14 days, oldest first.
  List<DayAdherence> _days() {
    final today = dateOnly(DateTime.now());
    final result = <DayAdherence>[];
    for (var i = 13; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      final onDay = events.where((e) {
        final at = DateTime.tryParse(e['scheduledAt'] as String? ?? '');
        return at != null && dateOnly(at) == day;
      }).toList();
      result.add(DayAdherence(day, onDay.where((e) => e['status'] == 'taken').length, onDay.length));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final patient = doc.data();
    final sorted = [...events]..sort((a, b) => (b['scheduledAt'] as String).compareTo(a['scheduledAt'] as String));
    final taken = sorted.where((e) => e['status'] == 'taken').length;
    final pct = sorted.isEmpty ? null : (taken * 100 / sorted.length).round();

    // Misses in a row, counting back from the latest dose.
    var streak = 0;
    for (final e in sorted) {
      if (e['status'] == 'taken') break;
      streak++;
    }
    final misses = sorted.where((e) => e['status'] != 'taken').take(5).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('${patient['patientName']} (${patient['patientNumber']})',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              Text(pct == null ? 'No doses logged' : '$pct% taken · 14 days',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text('Prescription'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => PrescriptionDialog(
                    patientRef: doc.reference,
                    patient: patient,
                    library: library,
                    staff: staff,
                  ),
                ),
              ),
            ]),
            Text([
              ...((patient['schedule'] as List?) ?? const []).cast<String>(),
              if ((patient['otherMedicines'] as List?)?.isNotEmpty == true)
                'Also on: ${((patient['otherMedicines'] as List).cast<String>()).join(', ')}',
            ].join(' · ')),
            const SizedBox(height: 12),
            AdherenceChart(days: _days()),
            if (patient['rxUpdatedBy'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Prescription last changed by ${patient['rxUpdatedBy']} ${timeAgo(patient['rxUpdatedAt'] as String?)}',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            if (streak >= 3)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: StatusColors.warn.withAlpha(40),
                  border: Border.all(color: StatusColors.warn),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Adherence alert: $streak doses in a row not taken. Consider calling the patient.'),
              ),
            if (misses.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Recent missed doses', style: TextStyle(fontWeight: FontWeight.w600)),
              for (final e in misses)
                Text('${_fmt(e['scheduledAt'] as String?)} · ${e['drugName']} · '
                    '${e['status'] == 'noResponse' ? 'no response' : 'missed'}'
                    '${e['reason'] != null ? ' (${e['reason']})' : ''}'),
            ],
            const SizedBox(height: 6),
            Text('Last seen ${timeAgo(patient['lastSeen'] as String?)}', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  static String _fmt(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso);
    return d == null ? '' : '${formatDay(d)} ${formatTime(d)}';
  }
}
