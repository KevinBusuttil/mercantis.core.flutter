import '../app_runtime/app_manifest.dart' show ReportColumn;

/// A chart derived from a grouped report (C7): one point per category, aligned
/// positionally so `categories[i]` has value `values[i]`. [type] is the chart
/// kind name (`bar` / `line` / `pie`); [valueLabel] names the plotted series.
class ReportChart {
  final String type;
  final String categoryLabel;
  final String valueLabel;
  final List<String> categories;
  final List<num?> values;

  const ReportChart({
    required this.type,
    required this.categoryLabel,
    required this.valueLabel,
    required this.categories,
    required this.values,
  });
}

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

  /// Optional chart accompanying a grouped report (C7). Null for plain tabular
  /// reports.
  final ReportChart? chart;

  const ReportResult({
    required this.reportId,
    required this.name,
    required this.columns,
    required this.rows,
    this.chart,
  });

  const ReportResult.empty(this.reportId, this.name)
      : columns = const [],
        rows = const [],
        chart = null;

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
