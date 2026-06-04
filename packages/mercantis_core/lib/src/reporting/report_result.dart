import '../app_runtime/app_manifest.dart' show ReportColumn;

/// The typed output of executing a [ReportDefinition] — mirrors the Swift
/// `ReportResult`. Columns carry their definitions (label + type) and rows are
/// pre-formatted string cells aligned positionally to [columns].
class ReportResult {
  final String reportId;
  final String name;
  final List<ReportColumn> columns;

  /// One entry per row; each inner list aligns positionally to [columns].
  /// A `null` cell denotes an absent value (distinct from an empty string).
  final List<List<String?>> rows;

  const ReportResult({
    required this.reportId,
    required this.name,
    required this.columns,
    required this.rows,
  });

  const ReportResult.empty(this.reportId, this.name)
      : columns = const [],
        rows = const [];

  List<String> get columnLabels => columns.map((c) => c.label).toList();

  bool get isEmpty => rows.isEmpty;
  int get rowCount => rows.length;

  /// Serialises to RFC-4180-ish CSV with quote escaping, matching the Swift
  /// `ReportResult.csvString()` export used by the report viewer.
  String toCsv() {
    final buffer = StringBuffer();
    buffer.writeln(columnLabels.map(_escapeCsv).join(','));
    for (final row in rows) {
      buffer.writeln(row.map((c) => _escapeCsv(c ?? '')).join(','));
    }
    return buffer.toString();
  }

  static String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
