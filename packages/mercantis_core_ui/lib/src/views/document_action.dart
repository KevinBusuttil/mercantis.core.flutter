import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import '../widgets/workflow_action_button.dart';

/// Performs a document action. Given the [BuildContext] (for navigation /
/// snackbars), a [WidgetRef] (to reach the engine and other providers), and the
/// current [Document], it does the work — typically building a downstream draft,
/// saving it, and navigating to it. Async so it can hit the engine.
typedef DocumentActionInvoke = Future<void> Function(
  BuildContext context,
  WidgetRef ref,
  Document document,
);

/// Returns the custom actions a host app wants to offer for [document] of
/// [docType] — evaluated synchronously from the document's own fields (status,
/// links) so gating ("only on a submitted order") needs no I/O. The heavy
/// lifting happens later in [DocumentAction.invoke].
typedef DocumentActionBuilder = List<DocumentAction> Function(
  Document document,
  DocType docType,
);

/// A host-contributed action offered on a document's command bar, alongside the
/// built-in Save / Submit / Cancel / Amend. Lets a module add domain flows —
/// e.g. document conversion ("Create Sales Order") — without the generic form
/// depending on that module. Contributed via [documentActionRegistryProvider].
class DocumentAction {
  const DocumentAction({
    required this.id,
    required this.label,
    required this.invoke,
    this.icon,
    this.style = WorkflowActionStyle.secondary,
  });

  /// Stable identifier (used as a widget key) — unique within a document's
  /// resolved action set.
  final String id;
  final String label;
  final IconData? icon;
  final WorkflowActionStyle style;
  final DocumentActionInvoke invoke;
}

/// Collects [DocumentActionBuilder]s contributed by host apps and resolves the
/// flattened action list for a given document. A singleton per app (see
/// [documentActionRegistryProvider]); the host registers its builders once at
/// boot, before any form is opened.
class DocumentActionRegistry {
  DocumentActionRegistry();

  final List<DocumentActionBuilder> _builders = [];

  void register(DocumentActionBuilder builder) => _builders.add(builder);

  /// Every contributed action for [document] of [docType], in registration
  /// order. Returns an empty list when nothing applies.
  List<DocumentAction> actionsFor(Document document, DocType docType) =>
      [for (final b in _builders) ...b(document, docType)];
}

final documentActionRegistryProvider = Provider<DocumentActionRegistry>(
  (_) => DocumentActionRegistry(),
);
