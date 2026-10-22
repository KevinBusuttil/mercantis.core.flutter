import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Words for a document's lifecycle as the operator sees them. The engine
/// transitions (submit / cancel / amend) and their gating never change — only
/// the button text, status chips and confirmations do, so a host can say
/// "Post invoice" to an owner and "Submit" to an ERP specialist.
class LifecycleLabels {
  const LifecycleLabels({
    this.draft = 'Draft',
    this.submit = 'Submit',
    this.submitted = 'Submitted',
    this.cancel = 'Cancel',
    this.cancelled = 'Cancelled',
    this.amend = 'Amend',
    this.savedMessage = 'Saved',
    this.submittedMessage = 'Submitted',
    this.cancelledMessage = 'Cancelled',
  });

  final String draft;

  /// The submit button (e.g. "Post invoice").
  final String submit;

  /// Status chip / filter for docStatus 1 (e.g. "Posted").
  final String submitted;

  /// The cancel button on a submitted document (e.g. "Reverse").
  final String cancel;

  /// Status chip / filter for docStatus 2.
  final String cancelled;

  /// The amend button on a cancelled document (e.g. "Correct").
  final String amend;

  /// Confirmation shown after each successful step, so the operator is never
  /// left unsure whether the work was kept. Null shows nothing.
  final String? savedMessage;
  final String? submittedMessage;
  final String? cancelledMessage;

  /// The engine vocabulary — the default for every DocType.
  static const engine = LifecycleLabels();

  String statusLabel(int docStatus) => switch (docStatus) {
        0 => draft,
        1 => submitted,
        2 => cancelled,
        _ => 'Unknown',
      };
}

/// How one DocType is named and introduced on operator surfaces: its list
/// title, the "New …" action, the empty-state copy and its lifecycle words.
/// Every field is optional; null falls back to the engine's own name.
class DocTypePresentation {
  const DocTypePresentation({
    this.label,
    this.singular,
    this.emptyTitle,
    this.emptyMessage,
    this.lifecycle = LifecycleLabels.engine,
  });

  /// Plural list title (e.g. "Invoices" for Sales Invoice).
  final String? label;

  /// Singular noun for "New …" and confirmations (e.g. "invoice").
  final String? singular;

  /// Empty list headline (e.g. "No invoices yet").
  final String? emptyTitle;

  /// Empty list guidance — what to do next (e.g. "Create one, or convert an
  /// accepted quote.").
  final String? emptyMessage;

  final LifecycleLabels lifecycle;

  static const engine = DocTypePresentation();
}

typedef DocTypePresentationResolver = DocTypePresentation Function(
    String docType);

/// Resolves a DocType's [DocTypePresentation]. The default is the engine
/// vocabulary everywhere; hosts override it (e.g. per Owner/Accountant mode).
/// Presentation only — it must never be used to gate an operation.
final docTypePresentationProvider = Provider<DocTypePresentationResolver>(
  (_) => (_) => DocTypePresentation.engine,
);
