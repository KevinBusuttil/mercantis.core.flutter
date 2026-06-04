import '../app_runtime/app_manifest.dart';
import 'dashboard_result.dart';
import 'report_engine.dart';
import 'report_value_formatter.dart';

/// Resolves [DashboardDefinition]s into typed [DashboardResult]s by executing
/// each widget against the document store / report engine. Mirrors the Swift
/// `DashboardEngine` (ADR-045): four widget kinds, each isolated so a single
/// failing tile surfaces an error instead of breaking the whole dashboard.
///
/// Widget `config` contract (read from [DashboardWidget.config]):
/// * `count`    — `{ docType, filters?, whereExpression? }`
/// * `list`     — `{ docType, columns: [fieldKey...], limit?, filters?, sortBy? }`
/// * `shortcut` — `{ route }`
/// * `chart`    — `{ reportId, filters? }`
class DashboardEngine {
  final DocumentListFn _list;
  final ReportEngine _reportEngine;
  final ReportValueFormatter _formatter;
  final Map<String, DashboardDefinition> _dashboards = {};

  DashboardEngine(
    this._list,
    this._reportEngine, {
    ReportValueFormatter? formatter,
  }) : _formatter = formatter ?? const ReportValueFormatter();

  void register(DashboardDefinition definition) {
    _dashboards[definition.id] = definition;
  }

  void registerAll(Iterable<DashboardDefinition> definitions) {
    for (final d in definitions) {
      register(d);
    }
  }

  DashboardDefinition? definition(String dashboardId) =>
      _dashboards[dashboardId];

  List<DashboardDefinition> availableDashboards(Set<String> userRoles) {
    return _dashboards.values.where((d) {
      if (d.roles.isEmpty) return true;
      return d.roles.any(userRoles.contains);
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<DashboardResult> resolve(
    String dashboardId, {
    Set<String>? userRoles,
  }) async {
    final definition = _dashboards[dashboardId];
    if (definition == null) {
      throw ArgumentError.value(dashboardId, 'dashboardId', 'No such dashboard');
    }
    final widgets = <DashboardWidgetResult>[];
    for (final widget in definition.widgets) {
      widgets.add(await _resolveWidget(widget, userRoles));
    }
    return DashboardResult(
      dashboardId: definition.id,
      name: definition.name,
      widgets: widgets,
    );
  }

  Future<DashboardWidgetResult> _resolveWidget(
    DashboardWidget widget,
    Set<String>? userRoles,
  ) async {
    try {
      switch (widget.type) {
        case 'count':
          return await _count(widget, userRoles);
        case 'list':
          return await _listWidget(widget, userRoles);
        case 'shortcut':
          return _shortcut(widget);
        case 'chart':
          return await _chart(widget, userRoles);
        default:
          return DashboardWidgetResult.failed(
            id: widget.id,
            type: widget.type,
            label: widget.label,
            error: 'Unknown widget type "${widget.type}"',
          );
      }
    } catch (e) {
      return DashboardWidgetResult.failed(
        id: widget.id,
        type: widget.type,
        label: widget.label,
        error: e.toString(),
      );
    }
  }

  Future<DashboardWidgetResult> _count(
    DashboardWidget widget,
    Set<String>? userRoles,
  ) async {
    final docType = _requireString(widget, 'docType');
    final docs = await _list(
      docType,
      filters: _filters(widget),
      whereExpression: widget.config['whereExpression'] as String?,
      userRoles: userRoles,
    );
    return DashboardWidgetResult(
      id: widget.id,
      type: widget.type,
      label: widget.label,
      count: docs.length,
    );
  }

  Future<DashboardWidgetResult> _listWidget(
    DashboardWidget widget,
    Set<String>? userRoles,
  ) async {
    final docType = _requireString(widget, 'docType');
    final columns =
        (widget.config['columns'] as List<dynamic>? ?? const []).cast<String>();
    final limit = (widget.config['limit'] as num?)?.toInt() ?? 5;
    final docs = await _list(
      docType,
      filters: _filters(widget),
      whereExpression: widget.config['whereExpression'] as String?,
      sortBy: _sortBy(widget),
      limit: limit,
      userRoles: userRoles,
    );
    final rows = docs.map((doc) {
      final row = <String, String?>{};
      if (columns.isEmpty) {
        row['name'] = doc.id;
      } else {
        for (final key in columns) {
          final raw = key == 'id' || key == 'name'
              ? doc.id
              : doc.payload[key];
          row[key] = _formatter.format(raw);
        }
      }
      return row;
    }).toList();
    return DashboardWidgetResult(
      id: widget.id,
      type: widget.type,
      label: widget.label,
      rows: rows,
    );
  }

  DashboardWidgetResult _shortcut(DashboardWidget widget) {
    return DashboardWidgetResult(
      id: widget.id,
      type: widget.type,
      label: widget.label,
      route: _requireString(widget, 'route'),
    );
  }

  Future<DashboardWidgetResult> _chart(
    DashboardWidget widget,
    Set<String>? userRoles,
  ) async {
    final reportId = _requireString(widget, 'reportId');
    final result = await _reportEngine.execute(
      reportId,
      filters: _filters(widget),
      userRoles: userRoles,
    );
    return DashboardWidgetResult(
      id: widget.id,
      type: widget.type,
      label: widget.label,
      chart: result,
    );
  }

  Map<String, dynamic>? _filters(DashboardWidget widget) {
    final raw = widget.config['filters'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  List<({String field, bool ascending})>? _sortBy(DashboardWidget widget) {
    final raw = widget.config['sortBy'];
    if (raw is! List) return null;
    return raw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return (
        field: m['field'] as String,
        ascending: (m['ascending'] as bool?) ?? true,
      );
    }).toList();
  }

  String _requireString(DashboardWidget widget, String key) {
    final value = widget.config[key];
    if (value is! String || value.isEmpty) {
      throw ArgumentError('Widget "${widget.id}" is missing config "$key"');
    }
    return value;
  }
}
