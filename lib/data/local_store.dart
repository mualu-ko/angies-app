import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Everything the app needs, saved on the phone. This is what makes the app
/// work offline: the schedule, dose log and reports live here first, and are
/// marked `synced: false` until Firebase receives them (see SyncService).
class LocalStore extends ChangeNotifier {
  LocalStore._(this._prefs);

  final SharedPreferences _prefs;

  Patient? patient;
  Prescription? prescription;
  /// Other medicines on the hospital record. Read-only for the patient.
  List<String> otherMedicines = [];

  /// Medicines the patient told us about (chemist, other clinic, herbal).
  /// Unverified until a pharmacist approves them in the clinician portal.
  List<ReportedMedicine> reportedMedicines = [];

  /// Everything the interaction check should look at.
  List<String> get allOtherMedicines => [...otherMedicines, for (final m in reportedMedicines) m.name];
  List<DoseEvent> doseEvents = [];
  List<AdrReport> reports = [];

  /// doseKey -> time the snoozed alarm will ring again.
  Map<String, DateTime> snoozes = {};

  /// Messages that would go to the caregiver by SMS once the backend exists.
  List<String> caregiverOutbox = [];

  String language = 'en';

  /// When the hospital record's prescription last changed (from Firebase).
  String? rxUpdatedAt;

  /// Show "your prescription was updated" on the Today screen.
  bool rxChanged = false;

  /// Drug descriptions from the portal, cached so they work offline.
  Map<String, Map<String, dynamic>> drugInfoCache = {};

  /// Increases on every change; screens rebuild when it does.
  int revision = 0;
  bool consentGiven = false;
  DateTime? onboardedAt;

  bool get signedIn => patient != null && prescription != null;
  bool get onboarded => onboardedAt != null;

  static Future<LocalStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    final store = LocalStore._(prefs);
    store._load();
    return store;
  }

  dynamic _read(String key) {
    final s = _prefs.getString(key);
    return s == null ? null : jsonDecode(s);
  }

  void _load() {
    final p = _read('patient');
    if (p != null) patient = Patient.fromJson(p as Map<String, dynamic>);
    final rx = _read('prescription');
    if (rx != null) prescription = Prescription.fromJson(rx as Map<String, dynamic>);
    otherMedicines = ((_read('otherMedicines') as List?) ?? []).cast<String>();
    reportedMedicines = ((_read('reportedMedicines') as List?) ?? []).map((e) {
      // Older versions stored plain names.
      if (e is String) return ReportedMedicine(id: 'MED-$e', name: e, createdAt: DateTime.now());
      return ReportedMedicine.fromJson(e as Map<String, dynamic>);
    }).toList();
    doseEvents = ((_read('doseEvents') as List?) ?? [])
        .map((e) => DoseEvent.fromJson(e as Map<String, dynamic>))
        .toList();
    reports = ((_read('reports') as List?) ?? [])
        .map((e) => AdrReport.fromJson(e as Map<String, dynamic>))
        .toList();
    final sn = (_read('snoozes') as Map<String, dynamic>?) ?? {};
    snoozes = sn.map((k, v) => MapEntry(k, DateTime.parse(v as String)));
    caregiverOutbox = ((_read('caregiverOutbox') as List?) ?? []).cast<String>();
    language = _prefs.getString('language') ?? 'en';
    rxUpdatedAt = _prefs.getString('rxUpdatedAt');
    final di = (_read('drugInfoCache') as Map<String, dynamic>?) ?? {};
    drugInfoCache = di.map((k, v) => MapEntry(k, v as Map<String, dynamic>));
    rxChanged = _prefs.getBool('rxChanged') ?? false;
    consentGiven = _prefs.getBool('consentGiven') ?? false;
    final ob = _prefs.getString('onboardedAt');
    onboardedAt = ob == null ? null : DateTime.parse(ob);
  }

  Future<void> _save() async {
    await _prefs.setString('patient', jsonEncode(patient?.toJson()));
    await _prefs.setString('prescription', jsonEncode(prescription?.toJson()));
    await _prefs.setString('otherMedicines', jsonEncode(otherMedicines));
    await _prefs.setString('reportedMedicines', jsonEncode(reportedMedicines.map((m) => m.toJson()).toList()));
    await _prefs.setString('doseEvents', jsonEncode(doseEvents.map((e) => e.toJson()).toList()));
    await _prefs.setString('reports', jsonEncode(reports.map((e) => e.toJson()).toList()));
    await _prefs.setString(
        'snoozes', jsonEncode(snoozes.map((k, v) => MapEntry(k, v.toIso8601String()))));
    await _prefs.setString('caregiverOutbox', jsonEncode(caregiverOutbox));
    await _prefs.setString('language', language);
    if (rxUpdatedAt != null) await _prefs.setString('rxUpdatedAt', rxUpdatedAt!);
    await _prefs.setBool('rxChanged', rxChanged);
    await _prefs.setString('drugInfoCache', jsonEncode(drugInfoCache));
    await _prefs.setBool('consentGiven', consentGiven);
    if (onboardedAt != null) {
      await _prefs.setString('onboardedAt', onboardedAt!.toIso8601String());
    } else {
      await _prefs.remove('onboardedAt');
    }
    revision++;
    notifyListeners();
  }

  Future<void> saveRecord(HospitalRecord r, {required String lang, required bool consent}) async {
    patient = r.patient;
    prescription = r.prescription;
    otherMedicines = [...r.otherMedicines];
    language = lang;
    consentGiven = consent;
    await _save();
  }

  /// The hospital record changed (a clinician edited the prescription).
  Future<void> updatePrescription(Prescription rx, String updatedAt, {required bool notify}) async {
    prescription = rx;
    rxUpdatedAt = updatedAt;
    if (notify) rxChanged = true;
    await _save();
  }

  Future<void> setRxUpdatedAt(String updatedAt) async {
    rxUpdatedAt = updatedAt;
    await _save();
  }

  Future<void> setDrugInfoCache(Map<String, Map<String, dynamic>> cache) async {
    drugInfoCache = cache;
    await _save();
  }

  Future<void> dismissRxNotice() async {
    rxChanged = false;
    await _save();
  }

  Future<void> setLanguage(String lang) async {
    language = lang;
    await _save();
  }

  Future<void> completeOnboarding() async {
    onboardedAt = DateTime.now();
    await _save();
  }

  /// Whether a dose belongs in adherence numbers: due after sign-up, or
  /// logged by the patient (e.g. this morning's dose, logged after sign-up).
  bool counts(String doseKey, DateTime at) {
    final since = onboardedAt;
    if (since == null) return false;
    return !at.isBefore(since) || eventFor(doseKey) != null;
  }

  DoseEvent? eventFor(String doseKey) {
    for (final e in doseEvents) {
      if (e.doseKey == doseKey) return e;
    }
    return null;
  }

  Future<void> recordDose(DoseEvent e) async {
    doseEvents.removeWhere((x) => x.doseKey == e.doseKey);
    doseEvents.add(e);
    snoozes.remove(e.doseKey);
    await _save();
  }

  Future<void> setSnooze(String doseKey, DateTime until) async {
    snoozes[doseKey] = until;
    await _save();
  }

  Future<void> queueCaregiverAlert(String message) async {
    caregiverOutbox.add(message);
    await _save();
  }

  Future<void> addReport(AdrReport r) async {
    reports.insert(0, r);
    await _save();
  }

  Future<void> addReportedMedicine(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    if (allOtherMedicines.any((m) => m.toLowerCase() == n.toLowerCase())) return;
    reportedMedicines.add(ReportedMedicine(
      id: 'MED-${DateTime.now().millisecondsSinceEpoch}',
      name: n,
      createdAt: DateTime.now(),
    ));
    await _save();
  }

  Future<void> removeReportedMedicine(String id) async {
    reportedMedicines.removeWhere((m) => m.id == id);
    await _save();
  }

  // ---- Sync bookkeeping (see services/sync_service.dart) ----

  Future<void> markDoseSynced(String doseKey) async {
    doseEvents = [for (final e in doseEvents) e.doseKey == doseKey ? e.markSynced() : e];
    await _save();
  }

  Future<void> markReportSynced(String id) async {
    reports = [for (final r in reports) r.id == id ? r.copyWith(synced: true) : r];
    await _save();
  }

  Future<void> markMedicineSynced(String id) async {
    reportedMedicines = [for (final m in reportedMedicines) m.id == id ? m.copyWith(synced: true) : m];
    await _save();
  }

  /// A clinician changed a report (status, reply or urgent care action).
  /// Returns true when an urgent instruction arrived that the patient has
  /// not acknowledged yet, so the app can ring for it.
  Future<bool> applyReportUpdate(String id, Map<String, dynamic> data) async {
    final i = reports.indexWhere((r) => r.id == id);
    if (i < 0) return false;
    final r = reports[i];
    final status = (data['status'] as String?) ?? 'new';
    final reply = data['reply'] as String?;
    final care = data['careAction'];
    final careId = care is Map ? care['id'] as String? : null;
    final careType = care is Map ? care['type'] as String? : null;
    final careAck = care is Map ? care['ackAt'] as String? : null;
    final isNewCare = careId != null && careId != r.careActionId && careAck == null;
    if (r.status == status && r.reply == reply && r.careActionId == careId && r.careAckAt == careAck) {
      return false;
    }
    reports[i] = r.copyWith(
      status: status,
      reply: reply,
      careActionId: careId,
      careActionType: careType,
      careAckAt: careAck,
    );
    await _save();
    return isNewCare;
  }

  Future<void> acknowledgeCare(String reportId) async {
    final i = reports.indexWhere((r) => r.id == reportId);
    if (i < 0) return;
    reports[i] = reports[i].copyWith(careAckAt: DateTime.now().toIso8601String());
    await _save();
  }

  AdrReport? reportById(String id) {
    for (final r in reports) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// A pharmacist approved or rejected a reported medicine.
  Future<void> applyMedicineUpdate(String id, String status, String? note) async {
    final i = reportedMedicines.indexWhere((m) => m.id == id);
    if (i < 0) return;
    final m = reportedMedicines[i];
    if (m.status == status && m.note == note) return;
    reportedMedicines[i] = m.copyWith(status: status, note: note);
    await _save();
  }

  int get unsyncedCount =>
      doseEvents.where((e) => !e.synced).length +
      reports.where((r) => !r.synced).length +
      reportedMedicines.where((m) => !m.synced).length;

  Future<void> signOut() async {
    await _prefs.clear();
    patient = null;
    prescription = null;
    otherMedicines = [];
    reportedMedicines = [];
    doseEvents = [];
    reports = [];
    snoozes = {};
    caregiverOutbox = [];
    language = 'en';
    rxUpdatedAt = null;
    rxChanged = false;
    consentGiven = false;
    onboardedAt = null;
    revision++;
    notifyListeners();
  }
}
