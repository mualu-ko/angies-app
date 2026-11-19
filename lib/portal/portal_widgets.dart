import 'package:flutter/material.dart';

import '../models/models.dart';

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c?.withAlpha(30),
          border: Border.all(color: c ?? Theme.of(context).colorScheme.outlineVariant, width: c == null ? 1 : 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(36),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

String timeAgo(String? iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  final mins = DateTime.now().difference(d).inMinutes;
  if (mins < 1) return 'just now';
  if (mins < 60) return '$mins min ago';
  if (mins < 60 * 24) return '${mins ~/ 60} h ago';
  return '${formatDay(d)} ${formatTime(d)}';
}

String initials(String name) =>
    name.split(' ').where((p) => p.isNotEmpty).map((p) => p[0].toUpperCase()).join('.');
