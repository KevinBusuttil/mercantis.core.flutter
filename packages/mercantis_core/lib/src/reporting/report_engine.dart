import '../app_runtime/app_manifest.dart';
import '../document_engine/document.dart';
import 'report_result.dart';
import 'report_value_formatter.dart';

/// Signature compatible with `DocumentEngine.list`, so callers can pass
/// `engine.list` directly. Declaring it as a typedef (rather than depending on
/// `DocumentEngine`) keeps [ReportEngine] unit-testable with an in-memory
/// lister and avoids a hard dependency cycle through the document engine.
typedef DocumentListFn = Future<List<Document>> Function(
  String docType, {
  Map<String, dynamic>? filters,
  String? whereExpression,
  List<({String field, bool ascending})>? sortBy,
  int? limit,
  int? offset,
  Set<String>? userRoles,
});

/// Executes [ReportDefinition]s against the document store and renders the
/// rows into a typed [ReportResult]. Mirrors the Swift `ReportEngine`:
/// flat list-and-format reports read straight from `DocumentEngine.list()`.
///
/// Aggregating reports (Customer Aging, Trial Balance, statements) are
/// computed app-side in Hub by post-processing the documents this engine
/// returns; this class owns registration, role-gating, and the column
/// projection / value formatting shared by every report.
class ReportEngine {
  final DocumentListFn _list;
  final ReportValueFormatter _formatter;
  final Map<String, ReportDefinition> _reports = {};

  ReportEngine(this._list, {ReportValueFormatter? formatter})
      : _formatter = formatter ?? const ReportValueFormatter();

  /// System columns that resolve from a [Document]'s envelope rather than its
  /// JSON payload. Anything else is read from `document.payload[fieldKey]`.
  static const _systemColumns = {
    'id',
    'name',
    'docstatus',
    'status',
    'company',
    'created_at',
    'modified_at',
    'amended_from',
  };

  void register(ReportDefinition definition) {
    _reports[definition.id] = definition;
  }

  void registerAll(Iterable<ReportDefinition> definitions) {
    for (final d in definitions) {
      register(d);
    }
  }

  void unregister(String reportId) => _reports.remove(reportId);

  ReportDefinition? definition(String reportId) => _reports[reportId];

  /// Reports the given roles may run. An empty `roles` list on a definition
  /// means "available to everyone"; otherwise the role sets must intersect.
  List<ReportDefinition> availableReports(Set<String> userRoles) {
    return _reports.values.where((r) {
      if (r.roles.isEmpty) return true;
      return r.roles.any(userRoles.contains);
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Runs the report named [reportId] and projects its rows. [filters] are
  /// payload-equality predicates merged on top of the definition's own
  /// `filterExpression`.
  Future<ReportResult> execute(
    String reportId, {
    Map<String, dynamic>? filters,
    Set<String>? userRoles,
  }) async {
    final definition = _reports[reportId];
    if (definition == null) {
      throw ArgumentError.value(reportId, 'reportId', 'No such report');
    }
    final docs = await _list(
      definition.docType,
      filters: filters,
      whereExpression: definition.filterExpression,
      userRoles: userRoles,
    );
    return project(definition, docs);
  }

  /// Pure projection of [documents] onto a report's columns — exposed
  /// separately so app-side aggregating reports and tests can reuse the exact
  /// same formatting without touching the database.
  ReportResult project(ReportDefinition definition, List<Document> documents) {
    final rows = documents.map((doc) {
      return definition.columns.map((col) {
        final raw = _valueFor(doc, col.fieldKey);
        return _formatter.format(raw, type: col.type);
      }).toList();
    }).toList();

    return ReportResult(
      reportId: definition.id,
      name: definition.name,
      columns: definition.columns,
      rows: rows,
    );
  }

  dynamic _valueFor(Document doc, String fieldKey) {
    if (_systemColumns.contains(fieldKey)) {
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
