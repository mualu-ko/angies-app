import 'package:flutter/material.dart';

import '../models/models.dart';

/// Colours used for dose status across the app.
class StatusColors {
  static const good = Color(0xFF1E8E3E);
  static const warn = Color(0xFFE8A317);
  static const crit = Color(0xFFD93025);
}

class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.child, this.color, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final Color? color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = color;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: c == null ? null : c.withAlpha(30),
        border: Border.all(color: c ?? Theme.of(context).colorScheme.outlineVariant, width: c == null ? 1 : 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

Color colorFor(DoseStatus? s) {
  switch (s) {
    case DoseStatus.taken:
      return StatusColors.good;
    case DoseStatus.missed:
    case DoseStatus.noResponse:
      return StatusColors.warn;
    case null:
      return Colors.grey;
  }
}

String statusKey(DoseStatus? s) {
  switch (s) {
    case DoseStatus.taken:
      return 'taken';
    case DoseStatus.missed:
      return 'missed';
    case DoseStatus.noResponse:
      return 'noResponse';
    case null:
      return 'due';
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      );
}
