import '../app_runtime/app_manifest.dart' show ReportColumn, ReportDefinition;
import '../document_engine/document.dart';
import '../document_engine/list_filter.dart';
import '../metadata/doc_type.dart';
import '../metadata/metadata_registry.dart';
import 'report_result.dart';
import 'report_value_formatter.dart';
import 'saved_report_definition.dart';

/// Subset of `DocumentEngine.list` the saved-report engine needs. Declaring it
/// as a typedef (rather than depending on `DocumentEngine`) keeps the engine
/// unit-testable with an in-memory lister, mirroring `ReportEngine`. The real
/// `DocumentEngine.list` is assignable to it (its extra named params are
/// optional), so callers pass `engine.list` directly — and because queries go
/// through it, DocType `rowAccessExpression` and role-based row filtering still
/// apply: saved reports can't widen access beyond what the user could see.
typedef SavedReportListFn = Future<List<Document>> Function(
  String docType, {
  List<ListFilter>? predicates,
  List<({String field, bool ascending})>? sortBy,
  Set<String>? userRoles,
});

/// Raised when a [SavedReportDefinition] cannot be executed.
class SavedReportException implements Exception {
  final String message;
  const SavedReportException(this.message);

  factory SavedReportException.docTypeNotRegistered(String docType) =>
      SavedReportException(
          'The report\'s source type "$docType" isn\'t registered. Its app '
          'manifest may not have finished installing.');

  factory SavedReportException.unknownField(String fieldKey, String docType) =>
      SavedReportException(
          'Field "$fieldKey" doesn\'t exist on "$docType", so it can\'t be '
          'used in a saved report.');

  factory SavedReportException.noVisibleColumns(String savedReportId) =>
      const SavedReportException(
          'This saved report has no visible columns. Show at least one column '
          'before running it.');

  factory SavedReportException.missingRequiredFilter(String fieldKey) =>
      SavedReportException(
          'The required filter "$fieldKey" needs a value before this report '
          'can run.');

  factory SavedReportException.notAuthorized(String userId) =>
      SavedReportException(
          'User "$userId" isn\'t allowed to open this private saved report.');

  @override
  String toString() => 'SavedReportException: $message';
}

/// Executes [SavedReportDefinition]s (ADR-050) against the document store and
/// returns the same [ReportResult] the built-in `ReportEngine` produces.
///
/// The engine also offers a small in-memory registry (mirroring `ReportEngine`)
/// so hosts can register saved reports, list the ones a user may access, and
/// clone built-in reports into saved configuration.
///
/// Safety properties: only fields that exist in the source DocType metadata (or
/// are well-known system columns) may be referenced; filters map onto the typed
/// [ListFilter] surface (no arbitrary SQL or scripts); and queries go through
/// the document lister so row-level access still applies.
class SavedReportEngine {
  final SavedReportListFn _list;
  final MetadataRegistry _registry;
  final ReportValueFormatter _formatter;
  final Map<String, SavedReportDefinition> _saved = {};

  SavedReportEngine(
    this._list,
    this._registry, {
    ReportValueFormatter? formatter,
  }) : _formatter = formatter ?? const ReportValueFormatter();

  /// Document system columns that may be referenced by a saved report even
  /// though they aren't user-declared fields. Mirrors `ReportEngine`.
  static const Set<String> systemFieldKeys = {
    'id',
    'name',
    'docstatus',
    'status',
    'company',
    'created_at',
    'modified_at',
    'amended_from',
  };

  // MARK: registry

  void register(SavedReportDefinition savedReport) {
    _saved[savedReport.id] = savedReport;
  }

  void remove(String id) => _saved.remove(id);

  SavedReportDefinition? get(String id) => _saved[id];

  /// All registered saved reports, sorted by name for deterministic ordering.
  List<SavedReportDefinition> all() =>
      _saved.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  /// Saved reports the given user may access — every `shared` report plus the
  /// user's own `private` reports — sorted by name.
  List<SavedReportDefinition> accessibleSavedReports(String userId) =>
      _saved.values.where((r) => r.canBeAccessed(userId)).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  /// Clone a built-in [ReportDefinition] into a saved report and register it.
  SavedReportDefinition convert(
    ReportDefinition report, {
    String? id,
    String? name,
    required String ownerUserId,
    SavedReportVisibility visibility = SavedReportVisibility.private,
    DateTime? now,
  }) {
    final saved = SavedReportDefinition.fromReport(
      report,
      id: id,
      name: name,
      ownerUserId: ownerUserId,
      visibility: visibility,
      now: now,
    );
    register(saved);
    return saved;
  }

  // MARK: execute

  /// Execute a saved report and return its [ReportResult].
  ///
  /// When [requestingUserId] is supplied the ownership/visibility gate is
  /// enforced and the id is used as the document-access subject.
  /// [runtimeFilterValues] override each filter's stored `value`/`defaultValue`
  /// by `fieldKey`. [userRoles] feed DocType row-level access filtering.
  Future<ReportResult> execute(
    SavedReportDefinition savedReport, {
    String? requestingUserId,
    Map<String, Object?> runtimeFilterValues = const {},
    Set<String> userRoles = const {},
  }) async {
    if (requestingUserId != null &&
        !savedReport.canBeAccessed(requestingUserId)) {
      throw SavedReportException.notAuthorized(requestingUserId);
    }

    final docType = await _registry.get(savedReport.sourceDocType);
    if (docType == null) {
      throw SavedReportException.docTypeNotRegistered(savedReport.sourceDocType);
    }
    final allowedFields = allowedFieldKeys(docType);

    final visibleColumns = savedReport.visibleColumnsInOrder;
    if (visibleColumns.isEmpty) {
      throw SavedReportException.noVisibleColumns(savedReport.id);
    }

    // Reject any reference to a field that isn't part of the DocType metadata
    // (or a known system column) — the guard that keeps a saved report from
    // reaching beyond its declared surface.
    _validateFields(savedReport, visibleColumns, allowedFields);

    // Typed predicates from the stored filters.
    final predicates = <ListFilter>[];
    for (final filter in savedReport.filters) {
      final effective = runtimeFilterValues.containsKey(filter.fieldKey)
          ? runtimeFilterValues[filter.fieldKey]
          : (filter.value ?? filter.defaultValue);
      final predicate = _makePredicate(filter, effective);
      if (predicate != null) predicates.add(predicate);
    }

    final sortBy = savedReport.sorts
        .map((s) => (
              field: s.fieldKey,
              ascending: s.direction == SavedReportSortDirection.ascending,
            ))
        .toList();

    final documents = await _list(
      savedReport.sourceDocType,
      predicates: predicates.isEmpty ? null : predicates,
      sortBy: sortBy.isEmpty ? null : sortBy,
      userRoles: userRoles,
    );

    // Project onto the visible columns, deriving each column's type from the
    // DocType field metadata so values format exactly like a built-in report.
    final columns = visibleColumns
        .map((c) => ReportColumn(
              fieldKey: c.fieldKey,
              label: c.resolvedLabel,
              type: _typeFor(docType, c.fieldKey),
            ))
        .toList();

    final rows = documents
        .map((doc) => columns
            .map((c) => _formatter.format(_valueFor(doc, c.fieldKey),
                type: c.type))
            .toList())
        .toList();

    return ReportResult(
      reportId: savedReport.id,
      name: savedReport.name,
      columns: columns,
      rows: rows,
    );
  }

  // MARK: validation

  /// The set of field keys a saved report on [docType] may legally reference.
  static Set<String> allowedFieldKeys(DocType docType) =>
      {...systemFieldKeys, ...docType.fields.map((f) => f.key)};

  void _validateFields(
    SavedReportDefinition savedReport,
    List<SavedReportColumn> visibleColumns,
    Set<String> allowedFields,
  ) {
    void check(String key) {
      if (!allowedFields.contains(key)) {
        throw SavedReportException.unknownField(
            key, savedReport.sourceDocType);
      }
    }

    for (final c in visibleColumns) {
      check(c.fieldKey);
    }
    for (final f in savedReport.filters) {
      check(f.fieldKey);
    }
    for (final s in savedReport.sorts) {
      check(s.fieldKey);
    }
  }

  // MARK: predicate construction

  ListFilter? _makePredicate(SavedReportFilter filter, Object? effective) {
    final key = filter.fieldKey;
    switch (filter.op) {
      case SavedReportFilterOperator.isNull:
        return ListFilter.isNull(key);
      case SavedReportFilterOperator.isNotNull:
        return ListFilter.isNotNull(key);
      default:
        if (effective == null) {
          if (filter.required) {
            throw SavedReportException.missingRequiredFilter(key);
          }
          return null; // optional, unset → simply skipped
        }
        switch (filter.op) {
          case SavedReportFilterOperator.equals:
            return ListFilter.eq(key, effective);
          case SavedReportFilterOperator.notEquals:
            return ListFilter.ne(key, effective);
          case SavedReportFilterOperator.greaterThan:
            return ListFilter.gt(key, effective);
          case SavedReportFilterOperator.greaterThanOrEqual:
            return ListFilter.gte(key, effective);
          case SavedReportFilterOperator.lessThan:
            return ListFilter.lt(key, effective);
          case SavedReportFilterOperator.lessThanOrEqual:
            return ListFilter.lte(key, effective);
          case SavedReportFilterOperator.contains:
            final fragment = _formatter.format(effective) ?? '';
            return ListFilter.like(key, '%$fragment%');
          case SavedReportFilterOperator.isNull:
          case SavedReportFilterOperator.isNotNull:
            return null; // handled above
        }
    }
  }

  // MARK: value resolution (mirrors ReportEngine._valueFor)

  String? _typeFor(DocType docType, String fieldKey) {
    for (final f in docType.fields) {
      if (f.key == fieldKey) return f.type.name;
    }
    if (fieldKey == 'created_at' || fieldKey == 'modified_at') {
      return 'dateTime';
    }
    return null;
  }

  dynamic _valueFor(Document doc, String fieldKey) {
    if (systemFieldKeys.contains(fieldKey)) {
      switch (fieldKey) {
        case 'id':
        case 'name':
          return doc.id;
        case 'docstatus':
        case 'status':
          return _docStatusLabel(doc.docStatus);
        case 'company':
          return doc.company;
        case 'created_at':
          return doc.createdAt;
        case 'modified_at':
          return doc.modifiedAt;
        case 'amended_from':
          return doc.amendedFrom;
      }
    }
    return doc.payload[fieldKey];
  }

  String _docStatusLabel(int docStatus) {
    switch (docStatus) {
      case 1:
        return 'Submitted';
      case 2:
        return 'Cancelled';
      default:
        return 'Draft';
    }
  }
}
