import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/local_store.dart';
import '../models/models.dart';

/// Sends what the patient records to Firebase and brings back clinician
/// replies and pharmacist decisions.
///
/// Offline first: everything is saved on the phone before this runs. If there
/// is no connection, items stay "waiting to sync" and are sent next time.
/// Alarms never depend on this.
///
/// Firestore layout (shared with the clinician portal):
///   patients/{patientNumber}
///   doseEvents/{patientNumber}_{doseKey}
///   adrReports/{patientNumber}_{reportId}       status, reply set by clinicians
///   medicineReports/{patientNumber}_{medId}     status, note set by pharmacists
class SyncService {
  SyncService(this.store);

  final LocalStore store;

  /// Called after a clinician changes the prescription, to re-arm alarms.
  Future<void> Function()? onPrescriptionChanged;

  /// Called when a clinician sends an urgent care instruction (reportId).
  Future<void> Function(String reportId)? onCareAction;

  static const _timeout = Duration(seconds: 20);

  bool _authed = false;
  bool _pushing = false;
  bool _pushAgain = false;
  bool _patientWritten = false;
  String? _listeningFor;
  Timer? _debounce;
  StreamSubscription<dynamic>? _adrSub;
  StreamSubscription<dynamic>? _medSub;
  StreamSubscription<dynamic>? _patientSub;
  StreamSubscription<dynamic>? _drugInfoSub;

  /// Called with fresh portal drug descriptions (id -> json).
  void Function(Map<String, Map<String, dynamic>>)? onDrugInfo;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<void> start() async {
    store.addListener(_onStoreChanged);
    await _ensureAuth();
    _onStoreChanged();
  }

  /// Called when the app comes back to the foreground.
  Future<void> retry() async {
    await _ensureAuth();
    _onStoreChanged();
  }

  Future<void> _ensureAuth() async {
    if (_authed) return;
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously().timeout(_timeout);
      }
      _authed = true;
    } catch (_) {
      _authed = false; // offline; try again later
    }
  }

  void _onStoreChanged() {
    final pn = store.patient?.patientNumber;
    if (pn != _listeningFor) {
      _adrSub?.cancel();
      _medSub?.cancel();
      _patientSub?.cancel();
      _listeningFor = null;
      _patientWritten = false;
      if (pn != null && _authed) _listen(pn);
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), push);
  }

  void _listen(String pn) {
    _listeningFor = pn;
    _drugInfoSub?.cancel();
    _drugInfoSub = _db.collection('drugInfo').snapshots().listen(
      (snap) async {
        final cache = <String, Map<String, dynamic>>{
          for (final d in snap.docs) d.id: jsonDecode(jsonEncode(d.data())) as Map<String, dynamic>,
        };
        onDrugInfo?.call(cache); // update the library first, then rebuild screens
        await store.setDrugInfoCache(cache);
      },
      onError: (Object _) {},
    );
    // The patient's hospital record: picks up prescription changes made by
    // clinicians, as they happen and every time the app opens.
    _patientSub = _db.collection('patients').doc(pn).snapshots().listen(
      (doc) async {
        final data = doc.data();
        if (data == null) return;
        final updatedAt = data['rxUpdatedAt'] as String?;
        final rx = data['prescription'];
        if (updatedAt == null || rx is! Map) return;
        if (updatedAt == store.rxUpdatedAt) return;
        final hadOne = store.rxUpdatedAt != null;
        try {
          // Firestore can hand back nested maps/lists with loose types (and
          // numbers as doubles); a JSON round trip gives the plain types the
          // model expects.
          final plain = jsonDecode(jsonEncode(rx)) as Map<String, dynamic>;
          for (final item in (plain['items'] as List)) {
            final m = item as Map<String, dynamic>;
            m['daysOn'] = (m['daysOn'] as num).toInt();
            m['daysOff'] = (m['daysOff'] as num).toInt();
          }
          final parsed = Prescription.fromJson(plain);
          debugPrint('Prescription updated from hospital record: '
              '${parsed.items.map((i) => i.drugName).join(', ')}');
          await store.updatePrescription(parsed, updatedAt, notify: hadOne);
          await onPrescriptionChanged?.call();
        } catch (e, st) {
          debugPrint('Prescription update failed: $e\n$st');
        }
      },
      onError: (Object _) {},
    );
    _adrSub = _db.collection('adrReports').where('patientNumber', isEqualTo: pn).snapshots().listen(
      (snap) {
        for (final d in snap.docs) {
          final data = d.data();
          final id = data['id'] as String?;
          if (id == null) continue;
          store.applyReportUpdate(id, data).then((isNew) {
            if (isNew) onCareAction?.call(id);
          });
        }
      },
      onError: (Object _) {},
    );
    _medSub = _db.collection('medicineReports').where('patientNumber', isEqualTo: pn).snapshots().listen(
      (snap) {
        for (final d in snap.docs) {
          final data = d.data();
          final id = data['id'] as String?;
          if (id == null) continue;
          store.applyMedicineUpdate(id, (data['status'] as String?) ?? 'pending', data['note'] as String?);
        }
      },
      onError: (Object _) {},
    );
  }

  /// The patient tapped "I understand" on an urgent instruction.
  Future<void> acknowledgeCare(String reportId) async {
    await store.acknowledgeCare(reportId);
    final pn = store.patient?.patientNumber;
    if (pn == null || !_authed) return;
    try {
      await _db
          .collection('adrReports')
          .doc('${pn}_$reportId')
          .update({'careAction.ackAt': DateTime.now().toIso8601String()})
          .timeout(_timeout);
    } catch (_) {
      // Firestore keeps the update queued and sends it when back online.
    }
  }

  Future<void> push() async {
    final p = store.patient;
    final rx = store.prescription;
    if (p == null || rx == null || !store.consentGiven) return;
    if (_pushing) {
      _pushAgain = true;
      return;
    }
    await _ensureAuth();
    if (!_authed) return;
    if (_listeningFor != p.patientNumber) _listen(p.patientNumber);

    _pushing = true;
    final pn = p.patientNumber;
    final who = {'patientNumber': pn, 'patientName': p.name, 'patientPhone': p.phone};
    try {
      if (!_patientWritten) {
        final ref = _db.collection('patients').doc(pn);
        final existing = await ref.get().timeout(_timeout);
        final summary = <String, dynamic>{
          ...who,
          'phone': p.phone,
          'clinic': p.clinic,
          'diagnosis': p.diagnosis,
          'otherMedicines': store.otherMedicines,
          'caregiverConsent': p.caregiverConsent,
          'lastSeen': DateTime.now().toIso8601String(),
        };
        // First time this patient is seen: copy the hospital prescription up.
        // After that the Firebase record is the source of truth, so clinician
        // edits are never overwritten by the phone.
        if (!existing.exists || existing.data()?['prescription'] == null) {
          final now = DateTime.now().toIso8601String();
          summary.addAll(prescriptionFields(rx));
          summary['rxUpdatedAt'] = now;
          await store.setRxUpdatedAt(now);
        }
        await ref.set(summary, SetOptions(merge: true)).timeout(_timeout);
        _patientWritten = true;
      }

      for (final e in store.doseEvents.where((e) => !e.synced).toList()) {
        final data = e.toJson()..remove('synced');
        await _db.collection('doseEvents').doc('${pn}_${e.doseKey}').set({...data, ...who}).timeout(_timeout);
        await store.markDoseSynced(e.doseKey);
      }

      for (final r in store.reports.where((r) => !r.synced).toList()) {
        final data = r.toJson()
          ..remove('synced')
          ..remove('reply');
        await _db
            .collection('adrReports')
            .doc('${pn}_${r.id}')
            .set({...data, ...who, 'status': 'new'}, SetOptions(merge: true))
            .timeout(_timeout);
        await store.markReportSynced(r.id);
      }

      for (final m in store.reportedMedicines.where((m) => !m.synced).toList()) {
        await _db.collection('medicineReports').doc('${pn}_${m.id}').set({
          'id': m.id,
          'name': m.name,
          'createdAt': m.createdAt.toIso8601String(),
          'status': 'pending',
          'drugIds': [for (final i in rx.items) i.drugId],
          ...who,
        }, SetOptions(merge: true)).timeout(_timeout);
        await store.markMedicineSynced(m.id);
      }
    } catch (_) {
      // Offline or timed out: items stay unsynced and go next time.
    } finally {
      _pushing = false;
      if (_pushAgain) {
        _pushAgain = false;
        unawaited(push());
      }
    }
  }
}

/// Prescription plus the summary fields the portal lists.
Map<String, dynamic> prescriptionFields(Prescription rx) => {
      'prescription': rx.toJson(),
      'medicines': [for (final i in rx.items) i.drugName],
      'drugIds': [for (final i in rx.items) i.drugId],
      'schedule': [for (final i in rx.items) '${i.drugName}: ${i.dose}, ${i.times.join(' & ')}'],
    };
