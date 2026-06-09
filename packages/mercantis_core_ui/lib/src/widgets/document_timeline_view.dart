import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../panes/document_timeline_panel.dart';
import '../providers/audit_providers.dart';

/// Renders a document's audit-log history as a timeline (created/updated events
/// with field diffs). Drop into the record chrome's Timeline tab.
class DocumentTimelineView extends ConsumerWidget {
  const DocumentTimelineView({super.key, required this.documentId});

  /// The saved document's id. Null/empty for an unsaved document.
  final String? documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = documentId;
    if (id == null || id.isEmpty) {
      return const Center(child: Text('Save the document to see activity'));
    }
    final async = ref.watch(auditTimelineProvider(id));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load activity: $e')),
      data: (entries) => DocumentTimelinePanel(entries: entries),
    );
  }
}
