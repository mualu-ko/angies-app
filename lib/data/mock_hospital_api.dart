import '../models/models.dart';

/// Stands in for the hospital / pharmacy system during the demo.
/// Phase 2 replaces this with a real API (shaped like a FHIR
/// MedicationRequest) behind the same three methods.
class MockHospitalApi {
  /// In the demo no SMS is sent; the app shows this code on screen.
  static const demoOtp = '123456';

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  /// Last 9 digits, so "0712 345 678" and "+254712345678" match.
  static String _phoneKey(String s) {
    final d = _digits(s);
    return d.length <= 9 ? d : d.substring(d.length - 9);
  }

  static HospitalRecord _amina() {
    final today = dateOnly(DateTime.now());
    final start = today.subtract(const Duration(days: 4)); // today = Day 5 of 14
    return HospitalRecord(
      patient: const Patient(
        patientNumber: 'ONC-104517',
        name: 'Amina Wanjiru',
        phone: '+254712345678',
        clinic: 'Oncology clinic',
        diagnosis: 'Breast cancer',
        caregiverName: 'Joseph Wanjiru',
        caregiverPhone: '+254722000111',
        caregiverConsent: true,
      ),
      prescription: Prescription(
        id: 'RX-58211',
        prescriber: 'Dr. Otieno',
        issuedAt: start,
        items: [
          PrescriptionItem(
            drugId: 'capecitabine',
            drugName: 'Capecitabine',
            dose: '3 tablets',
            instructions: 'within 30 minutes after a meal',
            times: const ['08:00', '20:00'],
            daysOn: 14,
            daysOff: 7,
            startDate: start,
          ),
        ],
      ),
      otherMedicines: const ['Warfarin'],
    );
  }

  static HospitalRecord _john() {
    final start = dateOnly(DateTime.now()).subtract(const Duration(days: 30));
    return HospitalRecord(
      patient: const Patient(
        patientNumber: 'ONC-200318',
        name: 'John Kamau',
        phone: '+254733456789',
        clinic: 'Oncology clinic',
        diagnosis: 'Leukaemia (CML)',
      ),
      prescription: Prescription(
        id: 'RX-60102',
        prescriber: 'Dr. Achieng',
        issuedAt: start,
        items: [
          PrescriptionItem(
            drugId: 'imatinib',
            drugName: 'Imatinib',
            dose: '1 tablet (400 mg)',
            instructions: 'with food and a large glass of water',
            times: const ['09:00'],
            daysOn: 1,
            daysOff: 0,
            startDate: start,
          ),
        ],
      ),
      otherMedicines: const [],
    );
  }

  static HospitalRecord? _find(String patientNumber, String phone) {
    final pn = patientNumber.trim().toUpperCase();
    for (final r in [_amina(), _john()]) {
      if (r.patient.patientNumber == pn && _phoneKey(r.patient.phone) == _phoneKey(phone)) {
        return r;
      }
    }
    return null;
  }

  /// Step 1: check the patient number matches the phone on record, then
  /// "send" an SMS code. Returns false if no matching record.
  Future<bool> requestOtp(String patientNumber, String phone) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return _find(patientNumber, phone) != null;
  }

  /// Step 2: verify the code and return the hospital record.
  Future<HospitalRecord?> verifyOtp(String patientNumber, String phone, String code) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (code.trim() != demoOtp) return null;
    return _find(patientNumber, phone);
  }
}
