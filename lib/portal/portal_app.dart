import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/drug_library.dart';
import 'adherence_page.dart';
import 'adr_page.dart';
import 'drug_library_page.dart';
import 'medicines_page.dart';
import 'messages_page.dart';

class PortalApp extends StatelessWidget {
  const PortalApp({super.key, required this.library});

  final DrugLibrary library;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clinician portal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6FB0)),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snap) {
          final user = snap.data;
          // Patients sign in anonymously; only staff accounts get the portal.
          if (user == null || user.isAnonymous) return const PortalSignIn();
          return PortalHome(library: library, user: user);
        },
      ),
    );
  }
}

/// Staff accounts are created by the clinic admin in the Firebase console.
class PortalSignIn extends StatefulWidget {
  const PortalSignIn({super.key});

  @override
  State<PortalSignIn> createState() => _PortalSignInState();
}

class _PortalSignInState extends State<PortalSignIn> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Sign-in failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Staff sign-in',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const Text('Oncology clinic portal', textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Staff email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                    onSubmitted: (_) => _signIn(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _signIn,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: const Text('Sign in'),
                  ),
                  const SizedBox(height: 16),
                  Text('Accounts are created by the clinic admin, not self sign-up.',
                      textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PortalHome extends StatefulWidget {
  const PortalHome({super.key, required this.library, required this.user});

  final DrugLibrary library;
  final User user;

  @override
  State<PortalHome> createState() => _PortalHomeState();
}

class _PortalHomeState extends State<PortalHome> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final staff = widget.user.email ?? 'staff';
    final pages = [
      AdrPage(staff: staff),
      MedicinesPage(library: widget.library, staff: staff),
      AdherencePage(library: widget.library, staff: staff),
      MessagesPage(staff: staff),
      DrugLibraryPage(library: widget.library, staff: staff),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinician portal · Oncology clinic'),
        actions: [
          Center(child: Text(staff)),
          const SizedBox(width: 8),
          TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Sign out')),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _page,
            onDestinationSelected: (i) => setState(() => _page = i),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.report_outlined), label: Text('Side effects')),
              NavigationRailDestination(icon: Icon(Icons.medication_outlined), label: Text('Medicine checks')),
              NavigationRailDestination(icon: Icon(Icons.people_outline), label: Text('Patients')),
              NavigationRailDestination(icon: Icon(Icons.chat_outlined), label: Text('Messages')),
              NavigationRailDestination(icon: Icon(Icons.menu_book_outlined), label: Text('Drug library')),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: pages[_page]),
        ],
      ),
    );
  }
}
