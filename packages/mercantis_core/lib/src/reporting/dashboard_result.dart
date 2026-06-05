import 'report_result.dart';

/// Resolved output of one [DashboardWidget]. Exactly one of [count], [total],
/// [rows], [route], or [chart] is populated for a successful widget; [error] is
/// set instead when that widget failed to resolve (per-widget isolation, so one
/// bad tile never blanks the whole dashboard). Mirrors the Swift
/// `DashboardWidgetResult`.
class DashboardWidgetResult {
  final String id;
  final String type;
  final String label;

  final int? count;

  /// Aggregated numeric value for a `sum` widget (raw, unformatted).
  final num? total;

  /// Display string for [total], pre-formatted with the widget's `valueType`
  /// (e.g. currency), so the UI can render it without its own formatter.
  final String? display;

  final List<Map<String, String?>>? rows;
  final String? route;
  final ReportResult? chart;
  final String? error;

  const DashboardWidgetResult({
    required this.id,
    required this.type,
    required this.label,
    this.count,
    this.total,
    this.display,
    this.rows,
    this.route,
    this.chart,
    this.error,
  });

  const DashboardWidgetResult.failed({
    required this.id,
    required this.type,
    required this.label,
    required String this.error,
  })  : count = null,
        total = null,
        display = null,
        rows = null,
        route = null,
        chart = null;

  bool get isError => error != null;
}

/// Resolved dashboard: the definition's widgets turned into typed results.
class DashboardResult {
  final String dashboardId;
  final String name;
  final List<DashboardWidgetResult> widgets;

  const DashboardResult({
    required this.dashboardId,
    required this.name,
    required this.widgets,
  });
}
