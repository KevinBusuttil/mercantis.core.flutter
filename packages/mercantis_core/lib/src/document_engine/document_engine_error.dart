import 'validation_pipeline.dart';

/// Structured error type emitted by [DocumentEngine] operations.
///
/// Every case carries the contextual data needed for the UI to render a
/// friendly explanation via [humanMessage] — see the Swift counterpart
/// (`DocumentEngine.DocumentEngineError: LocalizedError`). Call sites
/// should prefer `humanMessage` over `toString()` when surfacing the
/// error to end users; `toString()` is kept developer-flavoured for
/// logs and stack traces.
sealed class DocumentEngineError implements Exception {
  const DocumentEngineError();

  /// User-facing explanation. Localised in spirit only — copy lives
  /// in source for now (the Swift side is the same).
  String get humanMessage;

  /// The structured, per-field validation errors carried by a
  /// [DocumentEngineError.validationFailed]; empty for every other case.
  ///
  /// Lets the form distribute messages onto the fields / child rows that
  /// caused them (`fieldKey`s like `items[2].rate`) instead of only surfacing
  /// the collapsed [humanMessage] banner.
  List<ValidationError> get validationErrors => const [];

  /// A stored row couldn't be deserialised — usually means the payload
  /// was written by an incompatible schema version.
  const factory DocumentEngineError.malformedRow(String details) =
      _MalformedRow;

  factory DocumentEngineError.docTypeNotFound(String id) = _DocTypeNotFound;

  factory DocumentEngineError.notSubmittable(String docType) = _NotSubmittable;

  factory DocumentEngineError.invalidDocStatusTransition({
    required int from,
    required int to,
    required String id,
  }) = _InvalidDocStatusTransition;

  factory DocumentEngineError.fieldImmutableAfterSubmit({
    required String fieldKey,
    required String docType,
  }) = _FieldImmutableAfterSubmit;

  factory DocumentEngineError.cancelBlockedByLinks({
    required String id,
    required List<String> blockingIds,
  }) = _CancelBlockedByLinks;

  factory DocumentEngineError.cannotDeleteSubmitted(String id) =
      _CannotDeleteSubmitted;

  factory DocumentEngineError.validationFailed(List<ValidationError> errors) =
      _ValidationFailed;

  factory DocumentEngineError.concurrencyConflict(String id) =
      _ConcurrencyConflict;

  factory DocumentEngineError.permissionDenied({
    required String operation,
    required String docType,
  }) = _PermissionDenied;
}

String _humanStatus(int docStatus) {
  switch (docStatus) {
    case 0:
      return 'Draft';
    case 1:
      return 'Submitted';
    case 2:
      return 'Cancelled';
    default:
      return 'status $docStatus';
  }
}

/// Compose a single user-facing string from a list of stage errors.
/// One-message lists collapse to that message verbatim so the form
/// reads naturally ("Customer Type is required."); larger lists are
/// joined into a short bulleted summary.
String _humanValidationMessage(List<ValidationError> errors) {
  if (errors.isEmpty) {
    return "The record couldn't be saved because validation failed.";
  }
  if (errors.length == 1) {
    return errors.first.message;
  }
  final shown = errors.take(4).map((e) => '• ${e.message}').join('\n');
  if (errors.length > 4) {
    return '${errors.length} problems prevented the save:\n$shown\n• …';
  }
  return "Couldn't save:\n$shown";
}

class _MalformedRow extends DocumentEngineError {
  const _MalformedRow(this.details);
  final String details;
  @override
  String get humanMessage =>
      "A stored record couldn't be read — its payload may be from an incompatible version.";
  @override
  String toString() => 'DocumentEngineError.malformedRow($details)';
}

class _DocTypeNotFound extends DocumentEngineError {
  _DocTypeNotFound(this.id);
  final String id;
  @override
  String get humanMessage =>
      'DocType "$id" isn\'t registered. The app\'s manifest may not have finished installing.';
  @override
  String toString() => 'DocumentEngineError.docTypeNotFound($id)';
}

class _NotSubmittable extends DocumentEngineError {
  _NotSubmittable(this.docType);
  final String docType;
  @override
  String get humanMessage =>
      '"$docType" records can\'t be submitted because the DocType isn\'t marked submittable.';
  @override
  String toString() => 'DocumentEngineError.notSubmittable($docType)';
}

class _InvalidDocStatusTransition extends DocumentEngineError {
  _InvalidDocStatusTransition({
    required this.from,
    required this.to,
    required this.id,
  });
  final int from;
  final int to;
  final String id;
  @override
  String get humanMessage =>
      'Record $id can\'t move from status ${_humanStatus(from)} to ${_humanStatus(to)}.';
  @override
  String toString() =>
      'DocumentEngineError.invalidDocStatusTransition(from=$from, to=$to, id=$id)';
}

class _FieldImmutableAfterSubmit extends DocumentEngineError {
  _FieldImmutableAfterSubmit({required this.fieldKey, required this.docType});
  final String fieldKey;
  final String docType;
  @override
  String get humanMessage =>
      'Field "$fieldKey" can\'t be changed after the record is submitted.';
  @override
  String toString() =>
      'DocumentEngineError.fieldImmutableAfterSubmit($fieldKey on $docType)';
}

class _CancelBlockedByLinks extends DocumentEngineError {
  _CancelBlockedByLinks({required this.id, required this.blockingIds});
  final String id;
  final List<String> blockingIds;
  @override
  String get humanMessage {
    final preview = blockingIds.take(3).join(', ');
    final more =
        blockingIds.length > 3 ? ' (and ${blockingIds.length - 3} more)' : '';
    return 'Record $id is referenced by submitted records: $preview$more. '
        'Cancel those first.';
  }

  @override
  String toString() =>
      'DocumentEngineError.cancelBlockedByLinks($id, blocked by ${blockingIds.length})';
}

class _CannotDeleteSubmitted extends DocumentEngineError {
  _CannotDeleteSubmitted(this.id);
  final String id;
  @override
  String get humanMessage =>
      'Record $id is submitted and can\'t be deleted directly. '
      'Cancel it first, then delete.';
  @override
  String toString() => 'DocumentEngineError.cannotDeleteSubmitted($id)';
}

class _ValidationFailed extends DocumentEngineError {
  _ValidationFailed(this.errors);
  final List<ValidationError> errors;
  @override
  String get humanMessage => _humanValidationMessage(errors);
  @override
  List<ValidationError> get validationErrors => errors;
  @override
  String toString() =>
      'DocumentEngineError.validationFailed(${errors.length} errors)';
}

class _ConcurrencyConflict extends DocumentEngineError {
  _ConcurrencyConflict(this.id);
  final String id;
  @override
  String get humanMessage =>
      'Record $id was changed elsewhere since you opened it. '
      'Reload to pick up the latest version, then re-apply your edit.';
  @override
  String toString() => 'DocumentEngineError.concurrencyConflict($id)';
}

class _PermissionDenied extends DocumentEngineError {
  _PermissionDenied({required this.operation, required this.docType});
  final String operation;
  final String docType;
  @override
  String get humanMessage =>
      'You don\'t have permission to $operation records of type "$docType".';
  @override
  String toString() =>
      'DocumentEngineError.permissionDenied($operation on $docType)';
}
