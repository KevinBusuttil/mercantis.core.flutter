import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';

import '../panes/document_timeline_panel.dart';
import 'core_providers.dart';

/// A document's change history (the `audit_log`), newest first, mapped to
/// ready-to-render [TimelineEntry]s — `created`/`updated` events with their
/// field diffs.
final auditTimelineProvider =
    FutureProvider.family<List<TimelineEntry>, String>((ref, documentId) async {
  final db = (await ref.watch(mercantisDatabaseProvider.future)).db;
  final rows = await db.query(
    'audit_log',
    where: 'document_id = ?',
    whereArgs: [documentId],
    orderBy: 'timestamp DESC',
  );
  return [for (final r in rows) _toEntry(r)];
});

TimelineEntry _toEntry(Map<String, Object?> row) {
  final action = (row['action'] as String?) ?? 'updated';
  final created = action == 'created';
  final ts = DateTime.fromMillisecondsSinceEpoch((row['timestamp'] as int?) ?? 0);
  final user = (row['user_id'] as String?) ?? '';

  String? subtitle;
  final payload = row['payload'] as String?;
  if (payload != null && payload.isNotEmpty) {
    try {
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      final diffs = (decoded['diffs'] as List?)
              ?.map((d) => FieldDiff.fromJson(Map<String, dynamic>.from(d as Map)))
              .toList() ??
          const <FieldDiff>[];
      if (diffs.isNotEmpty) {
        final shown = diffs.take(6).map((d) => '${d.fieldKey}: ${_v(d.oldValue)} → ${_v(d.newValue)}');
        subtitle = shown.join('\n');
        if (diffs.length > 6) subtitle = '$subtitle\n… ${diffs.length - 6} more';
      }
    } catch (_) {
      // Tolerate a malformed payload — still show the event.
    }
  }

  return TimelineEntry(
    title: created ? 'Created' : 'Updated',
    timestamp: _fmt(ts),
    actor: user.isEmpty ? null : user,
    subtitle: subtitle,
    icon: created ? Icons.add_circle_outline : Icons.edit_outlined,
  );
}

String _v(dynamic value) {
  if (value == null) return '∅';
  final s = value.toString();
  return s.length > 40 ? '${s.substring(0, 40)}…' : s;
}

String _fmt(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')} '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
