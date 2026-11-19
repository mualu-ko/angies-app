// Clinician portal (web). Run with:
//   flutter run -d chrome -t lib/portal/main_portal.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../data/drug_library.dart';
import '../firebase_options.dart';
import 'portal_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final library = await DrugLibrary.load();
  runApp(PortalApp(library: library));
}
