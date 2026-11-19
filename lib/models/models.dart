// Plain data classes. Everything is stored on the phone as JSON so the app
// works fully offline; a sync flag marks what still has to reach the backend.

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String two(int n) => n.toString().padLeft(2, '0');

String formatDate(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

String formatTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  return '$h:${two(d.minute)} $ampm';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Stable id from a medicine name: "St John's wort" -> "st-john-s-wort".
/// No underscores, because dose keys use "_" as a separator.
String slugify(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');

String formatDay(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

class Patient {
  const Patient({
    required this.patientNumber,
    required this.name,
    required this.phone,
    required this.clinic,
    required this.diagnosis,
    this.caregiverName,
    this.caregiverPhone,
    this.caregiverConsent = false,
  });

  final String patientNumber;
  final String name;
  final String phone;
  final String clinic;
  final String diagnosis;
  final String? caregiverName;
  final String? caregiverPhone;
  final bool caregiverConsent;

  String get firstName => name.split(' ').first;

  Map<String, dynamic> toJson() => {
        'patientNumber': patientNumber,
        'name': name,
        'phone': phone,
        'clinic': clinic,
        'diagnosis': diagnosis,
        'caregiverName': caregiverName,
        'caregiverPhone': caregiverPhone,
        'caregiverConsent': caregiverConsent,
      };

  factory Patient.fromJson(Map<String, dynamic> j) => Patient(
        patientNumber: j['patientNumber'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String,
        clinic: j['clinic'] as String,
        diagnosis: j['diagnosis'] as String,
        caregiverName: j['caregiverName'] as String?,
        caregiverPhone: j['caregiverPhone'] as String?,
        caregiverConsent: (j['caregiverConsent'] as bool?) ?? false,
      );
}

/// One medicine on a prescription. [times] are "HH:mm" in 24-hour time.
/// A cycle of [daysOn] days taking it then [daysOff] rest days; daysOff = 0
/// means take it every day.
class PrescriptionItem {
  const PrescriptionItem({
    required this.drugId,
    required this.drugName,
    required this.dose,
    required this.instructions,
    required this.times,
    required this.daysOn,
    required this.daysOff,
    required this.startDate,
  });

  final String drugId;
  final String drugName;
  final String dose;
  final String instructions;
  final List<String> times;
  final int daysOn;
  final int daysOff;
  final DateTime startDate;

  Map<String, dynamic> toJson() => {
        'drugId': drugId,
        'drugName': drugName,
        'dose': dose,
        'instructions': instructions,
        'times': times,
        'daysOn': daysOn,
        'daysOff': daysOff,
        'startDate': startDate.toIso8601String(),
      };

  factory PrescriptionItem.fromJson(Map<String, dynamic> j) => PrescriptionItem(
        drugId: j['drugId'] as String,
        drugName: j['drugName'] as String,
        dose: j['dose'] as String,
        instructions: j['instructions'] as String,
        times: (j['times'] as List).cast<String>(),
        daysOn: j['daysOn'] as int,
        daysOff: j['daysOff'] as int,
        startDate: DateTime.parse(j['startDate'] as String),
      );
}

class Prescription {
  const Prescription({
    required this.id,
    required this.prescriber,
    required this.issuedAt,
    required this.items,
  });

  final String id;
  final String prescriber;
  final DateTime issuedAt;
  final List<PrescriptionItem> items;

  Map<String, dynamic> toJson() => {
        'id': id,
        'prescriber': prescriber,
        'issuedAt': issuedAt.toIso8601String(),
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory Prescription.fromJson(Map<String, dynamic> j) => Prescription(
        id: j['id'] as String,
        prescriber: j['prescriber'] as String,
        issuedAt: DateTime.parse(j['issuedAt'] as String),
        items: (j['items'] as List)
            .map((e) => PrescriptionItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// What the hospital system sends back for a verified patient.
class HospitalRecord {
  const HospitalRecord({
    required this.patient,
    required this.prescription,
    required this.otherMedicines,
  });

  final Patient patient;
  final Prescription prescription;
  final List<String> otherMedicines;
}

enum DoseStatus { taken, missed, noResponse }

class DoseEvent {
  const DoseEvent({
    required this.doseKey,
    required this.drugName,
    required this.scheduledAt,
    required this.status,
    required this.recordedAt,
    this.reason,
    this.synced = false,
  });

  final String doseKey;
  final String drugName;
  final DateTime scheduledAt;
  final DoseStatus status;
  final DateTime recordedAt;
  final String? reason;
  final bool synced;

  DoseEvent markSynced() => DoseEvent(
        doseKey: doseKey,
        drugName: drugName,
        scheduledAt: scheduledAt,
        status: status,
        recordedAt: recordedAt,
        reason: reason,
        synced: true,
      );

  Map<String, dynamic> toJson() => {
        'doseKey': doseKey,
        'drugName': drugName,
        'scheduledAt': scheduledAt.toIso8601String(),
        'status': status.name,
        'recordedAt': recordedAt.toIso8601String(),
        'reason': reason,
        'synced': synced,
      };

  factory DoseEvent.fromJson(Map<String, dynamic> j) => DoseEvent(
        doseKey: j['doseKey'] as String,
        drugName: j['drugName'] as String,
        scheduledAt: DateTime.parse(j['scheduledAt'] as String),
        status: DoseStatus.values.byName(j['status'] as String),
        recordedAt: DateTime.parse(j['recordedAt'] as String),
        reason: j['reason'] as String?,
        synced: (j['synced'] as bool?) ?? false,
      );
}

enum Severity { mild, moderate, severe }

class AdrReport {
  const AdrReport({
    required this.id,
    required this.drugName,
    required this.symptoms,
    required this.onset,
    required this.severity,
    required this.actionTaken,
    required this.createdAt,
    this.otherSymptom,
    this.status = 'new',
    this.reply,
    this.careActionId,
    this.careActionType,
    this.careAckAt,
    this.synced = false,
  });

  final String id;
  final String drugName;
  final List<String> symptoms;
  final String? otherSymptom;
  final String onset;
  final Severity severity;
  final String actionTaken;
  final DateTime createdAt;

  /// new -> reviewed -> confirmed -> forwarded (to the PPB). Set by clinicians.
  final String status;

  /// Clinician's reply to the patient, if any.
  final String? reply;

  /// Latest urgent instruction from the care team: call | clinic |
  /// emergency | ambulance. careAckAt is set when the patient taps OK.
  final String? careActionId;
  final String? careActionType;
  final String? careAckAt;
  final bool synced;

  AdrReport copyWith({
    String? status,
    String? reply,
    String? careActionId,
    String? careActionType,
    String? careAckAt,
    bool? synced,
  }) =>
      AdrReport(
        id: id,
        drugName: drugName,
        symptoms: symptoms,
        otherSymptom: otherSymptom,
        onset: onset,
        severity: severity,
        actionTaken: actionTaken,
        createdAt: createdAt,
        status: status ?? this.status,
        reply: reply ?? this.reply,
        careActionId: careActionId ?? this.careActionId,
        careActionType: careActionType ?? this.careActionType,
        careAckAt: careAckAt ?? this.careAckAt,
        synced: synced ?? this.synced,
      );

  String get summary {
    final all = [...symptoms, if (otherSymptom != null && otherSymptom!.isNotEmpty) otherSymptom!];
    return all.join(', ');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'drugName': drugName,
        'symptoms': symptoms,
        'otherSymptom': otherSymptom,
        'onset': onset,
        'severity': severity.name,
        'actionTaken': actionTaken,
        'createdAt': createdAt.toIso8601String(),
        'status': status,
        'reply': reply,
        'careActionId': careActionId,
        'careActionType': careActionType,
        'careAckAt': careAckAt,
        'synced': synced,
      };

  factory AdrReport.fromJson(Map<String, dynamic> j) => AdrReport(
        id: j['id'] as String,
        drugName: j['drugName'] as String,
        symptoms: (j['symptoms'] as List).cast<String>(),
        otherSymptom: j['otherSymptom'] as String?,
        onset: j['onset'] as String,
        severity: Severity.values.byName(j['severity'] as String),
        actionTaken: j['actionTaken'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        status: (j['status'] as String?) ?? 'new',
        reply: j['reply'] as String?,
        careActionId: j['careActionId'] as String?,
        careActionType: j['careActionType'] as String?,
        careAckAt: j['careAckAt'] as String?,
        synced: (j['synced'] as bool?) ?? false,
      );
}

/// A medicine the patient told us about. A pharmacist approves or rejects it.
class ReportedMedicine {
  const ReportedMedicine({
    required this.id,
    required this.name,
    required this.createdAt,
    this.status = 'pending',
    this.note,
    this.synced = false,
  });

  final String id;
  final String name;
  final DateTime createdAt;

  /// pending | approved | rejected
  final String status;

  /// Pharmacist's note to the patient.
  final String? note;
  final bool synced;

  ReportedMedicine copyWith({String? status, String? note, bool? synced}) => ReportedMedicine(
        id: id,
        name: name,
        createdAt: createdAt,
        status: status ?? this.status,
        note: note ?? this.note,
        synced: synced ?? this.synced,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'status': status,
        'note': note,
        'synced': synced,
      };

  factory ReportedMedicine.fromJson(Map<String, dynamic> j) => ReportedMedicine(
        id: j['id'] as String,
        name: j['name'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        status: (j['status'] as String?) ?? 'pending',
        note: j['note'] as String?,
        synced: (j['synced'] as bool?) ?? false,
      );
}

/// An entry in the searchable medicine list.
class MedicineEntry {
  const MedicineEntry({
    required this.name,
    required this.category,
    required this.aliases,
    this.contains = const [],
    this.verify = false,
  });

  final String name;
  final String category;
  final List<String> aliases;

  /// Ingredients of a brand or combination product, e.g. Mara Moja.
  /// Interaction checks look at these.
  final List<String> contains;

  /// True when the entry still needs checking by a pharmacist.
  final bool verify;

  factory MedicineEntry.fromJson(Map<String, dynamic> j) => MedicineEntry(
        name: j['name'] as String,
        category: (j['category'] as String?) ?? '',
        aliases: ((j['aliases'] as List?) ?? const []).cast<String>(),
        contains: ((j['contains'] as List?) ?? const []).cast<String>(),
        verify: (j['verify'] as bool?) ?? false,
      );
}

class DrugInfo {
  const DrugInfo({
    required this.id,
    required this.name,
    required this.drugClass,
    required this.cancerTypes,
    required this.howToTake,
    required this.sideEffects,
    required this.getHelpIf,
    this.uses = '',
    this.updatedBy,
  });

  final String id;
  final String name;
  final String drugClass;
  final List<String> cancerTypes;

  /// What the medicine is for, in plain words.
  final String uses;
  final List<String> howToTake;
  final List<String> sideEffects;
  final List<String> getHelpIf;

  /// Staff member who last edited it in the portal (null = bundled data).
  final String? updatedBy;

  static List<String> _list(Object? v) => ((v as List?) ?? const []).map((e) => '$e').toList();

  factory DrugInfo.fromJson(Map<String, dynamic> j) => DrugInfo(
        id: j['id'] as String,
        name: j['name'] as String,
        drugClass: (j['class'] as String?) ?? '',
        cancerTypes: _list(j['cancerTypes']),
        uses: (j['uses'] as String?) ?? '',
        howToTake: _list(j['howToTake']),
        sideEffects: _list(j['sideEffects']),
        getHelpIf: _list(j['getHelpIf']),
        updatedBy: j['updatedBy'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'class': drugClass,
        'cancerTypes': cancerTypes,
        'uses': uses,
        'howToTake': howToTake,
        'sideEffects': sideEffects,
        'getHelpIf': getHelpIf,
        'updatedBy': updatedBy,
      };
}

class Interaction {
  const Interaction({
    required this.drug,
    required this.withWhat,
    required this.type,
    required this.severity,
    required this.advice,
  });

  final String drug;
  final String withWhat;
  final String type;
  final String severity;
  final String advice;

  factory Interaction.fromJson(Map<String, dynamic> j) => Interaction(
        drug: j['drug'] as String,
        withWhat: j['with'] as String,
        type: j['type'] as String,
        severity: j['severity'] as String,
        advice: j['advice'] as String,
      );
}
