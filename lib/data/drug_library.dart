import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

/// Curated drug information and interaction data bundled inside the app, so
/// it works with no internet connection.
class DrugLibrary {
  DrugLibrary._(this.drugs, this.interactions, this.source, this.medicines);

  final Map<String, DrugInfo> drugs;
  final List<Interaction> interactions;
  final String source;

  /// Searchable list of medicines (starter list, or DDInter after import).
  final List<MedicineEntry> medicines;

  /// Descriptions written by staff in the portal (Firestore `drugInfo`),
  /// keyed by id. They take priority over the bundled drugs.json.
  Map<String, DrugInfo> remote = {};

  /// Best information for a medicine: portal-written first, then bundled.
  DrugInfo? infoFor(String id, String name) =>
      remote[id] ?? remote[slugify(name)] ?? drugs[id] ?? drugs[slugify(name)];

  static Future<DrugLibrary> load() async {
    final d = jsonDecode(await rootBundle.loadString('assets/data/drugs.json')) as Map<String, dynamic>;
    final i = jsonDecode(await rootBundle.loadString('assets/data/interactions.json')) as Map<String, dynamic>;
    final drugs = {
      for (final e in (d['drugs'] as List))
        (e as Map<String, dynamic>)['id'] as String: DrugInfo.fromJson(e),
    };
    final interactions = (i['interactions'] as List)
        .map((e) => Interaction.fromJson(e as Map<String, dynamic>))
        .toList();
    final m = jsonDecode(await rootBundle.loadString('assets/data/medicines.json')) as Map<String, dynamic>;
    final medicines = (m['medicines'] as List)
        .map((e) => MedicineEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    return DrugLibrary._(drugs, interactions, i['source'] as String? ?? 'DDInter 2.0', medicines);
  }

  /// Medicines whose generic or brand name matches [query]. Names that start
  /// with the query come first.
  List<MedicineEntry> search(String query, {int limit = 8}) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    bool starts(MedicineEntry e) =>
        e.name.toLowerCase().startsWith(q) || e.aliases.any((a) => a.toLowerCase().startsWith(q));
    bool contains(MedicineEntry e) =>
        e.name.toLowerCase().contains(q) || e.aliases.any((a) => a.toLowerCase().contains(q));
    final first = medicines.where(starts).toList();
    final rest = medicines.where((e) => !starts(e) && contains(e)).toList();
    return [...first, ...rest].take(limit).toList();
  }

  MedicineEntry? find(String name) {
    final n = name.trim().toLowerCase();
    for (final m in medicines) {
      if (m.name.toLowerCase() == n || m.aliases.any((a) => a.toLowerCase() == n)) return m;
    }
    return null;
  }

  /// A name plus its ingredients, so "Mara Moja" is checked as paracetamol,
  /// aspirin and caffeine too.
  List<String> ingredientsOf(String name) {
    final entry = find(name);
    return [name.toLowerCase().trim(), ...?entry?.contains.map((c) => c.toLowerCase())];
  }

  /// Interactions between [drugId] and the patient's other medicines.
  /// "Grapefruit juice" matches a "grapefruit" entry, so partial names count.
  List<Interaction> drugAlerts(String drugId, List<String> otherMedicines) {
    final others = otherMedicines.expand(ingredientsOf).toList();
    return interactions
        .where((x) => x.drug == drugId && others.any((o) => o == x.withWhat || o.contains(x.withWhat)))
        .toList();
  }

  List<Interaction> foodAlerts(String drugId) =>
      interactions.where((x) => x.drug == drugId && x.type == 'food').toList();
}
