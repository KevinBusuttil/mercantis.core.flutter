import 'package:uuid/uuid.dart';

import '../app_runtime/app_manifest.dart' show ReportDefinition;

/// Generic saved-report infrastructure (ADR-050). A [SavedReportDefinition] is
/// an app-neutral, user-owned customisation of a report: which columns show and
/// in what order, which filters apply (with stored defaults), and how rows are
/// sorted. It is deliberately data-only — it carries no SQL, no expressions,
/// and no script. The `SavedReportEngine` interprets it against DocType
/// metadata and the document store to produce a normal `ReportResult`.
///
/// This is a faithful Dart port of the Swift `SavedReportDefinition`.

/// Who may see and run a saved report. `private` reports are visible only to
/// their owner; `shared` reports are visible to anyone who can already reach
/// the underlying documents.
enum SavedReportVisibility { private, shared }

/// Direction for a saved-report sort key.
enum SavedReportSortDirection { ascending, descending }

/// The comparison a saved-report filter applies. Each case maps 1:1 onto a
/// `ListFilter` operator the document store already understands — there is no
/// free-form SQL or expression surface here.
enum SavedReportFilterOperator {
  equals,
  notEquals,
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,

  /// Substring match (`LIKE %value%`). Only meaningful for text fields.
  contains,
  isNull,
  isNotNull;

  /// Whether the operator needs a value to compare against. `isNull` /
  /// `isNotNull` are unary and ignore any stored value.
  bool get requiresValue =>
      this != SavedReportFilterOperator.isNull &&
      this != SavedReportFilterOperator.isNotNull;
}

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  if (name == null) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// One ordered sort key in a saved report.
class SavedReportSort {
  final String fieldKey;
  final SavedReportSortDirection direction;

  const SavedReportSort({
    required this.fieldKey,
    this.direction = SavedReportSortDirection.ascending,
  });

  factory SavedReportSort.fromJson(Map<String, dynamic> json) => SavedReportSort(
        fieldKey: json['fieldKey'] as String,
        direction: _enumByName(SavedReportSortDirection.values,
            json['direction'] as String?, SavedReportSortDirection.ascending),
      );

  Map<String, dynamic> toJson() =>
      {'fieldKey': fieldKey, 'direction': direction.name};
}

/// A stored filter on a saved report.
///
/// At execution the effective value resolves as
/// `runtime override → value → defaultValue`. A `required` filter with no
/// effective value is a hard error so a report can't silently run unfiltered.
class SavedReportFilter {
  final String fieldKey;
  final SavedReportFilterOperator op;

  /// The value baked into the saved report (may be overridden at run time).
  final Object? value;

  /// Fallback used when neither a runtime override nor [value] is supplied.
  final Object? defaultValue;

  /// When true, execution fails unless an effective value is available.
  final bool required;

  const SavedReportFilter({
    required this.fieldKey,
    this.op = SavedReportFilterOperator.equals,
    this.value,
    this.defaultValue,
    this.required = false,
  });

  factory SavedReportFilter.fromJson(Map<String, dynamic> json) =>
      SavedReportFilter(
        fieldKey: json['fieldKey'] as String,
        // `operator` is the natural JSON key (matches the Swift encoding).
        op: _enumByName(SavedReportFilterOperator.values,
            json['operator'] as String?, SavedReportFilterOperator.equals),
        value: json['value'],
        defaultValue: json['defaultValue'],
        required: json['required'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'fieldKey': fieldKey,
        'operator': op.name,
        if (value != null) 'value': value,
        if (defaultValue != null) 'defaultValue': defaultValue,
        'required': required,
      };
}

/// The aggregation applied when a saved report groups its rows (C7). Mirrors
/// the Swift `SavedReportAggregateFunction`.
enum SavedReportAggregateFunction { count, sum, avg, min, max }

/// One aggregate column of a grouped saved report. For [count] the [fieldKey]
/// is ignored (the group's rows are counted); the numeric functions fold the
/// values of [fieldKey] within each group, skipping non-numeric/null cells.
class SavedReportAggregate {
  final String fieldKey;
  final SavedReportAggregateFunction fn;

  /// Header text to show instead of the derived "fn(fieldKey)" / "Count".
  final String? labelOverride;

  const SavedReportAggregate({
    this.fieldKey = '',
    this.fn = SavedReportAggregateFunction.sum,
    this.labelOverride,
  });

  /// The header this aggregate contributes: the override, else `Count` for a
  /// count and `fn(fieldKey)` for the numeric folds.
  String get resolvedLabel =>
      labelOverride ??
      (fn == SavedReportAggregateFunction.count
          ? 'Count'
          : '${fn.name}($fieldKey)');

  factory SavedReportAggregate.fromJson(Map<String, dynamic> json) =>
      SavedReportAggregate(
        fieldKey: json['fieldKey'] as String? ?? '',
        fn: _enumByName(SavedReportAggregateFunction.values,
            json['function'] as String?, SavedReportAggregateFunction.sum),
        labelOverride: json['labelOverride'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'fieldKey': fieldKey,
        'function': fn.name,
        if (labelOverride != null) 'labelOverride': labelOverride,
      };
}

/// The kind of chart a grouped saved report renders.
enum SavedReportChartType { bar, line, pie }

/// A chart derived from a grouped saved report (C7): one bar/line point/slice
/// per group, its value taken from the aggregate at [aggregateIndex].
class SavedReportChart {
  final SavedReportChartType type;

  /// The group field whose values label the chart categories. Must be one of
  /// the report's [SavedReportDefinition.groupBy] keys.
  final String categoryFieldKey;

  /// Index into [SavedReportDefinition.aggregates] supplying each category's
  /// value.
  final int aggregateIndex;

  const SavedReportChart({
    this.type = SavedReportChartType.bar,
    required this.categoryFieldKey,
    this.aggregateIndex = 0,
  });

  factory SavedReportChart.fromJson(Map<String, dynamic> json) =>
      SavedReportChart(
        type: _enumByName(SavedReportChartType.values, json['type'] as String?,
            SavedReportChartType.bar),
        categoryFieldKey: json['categoryFieldKey'] as String,
        aggregateIndex: json['aggregateIndex'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'categoryFieldKey': categoryFieldKey,
        'aggregateIndex': aggregateIndex,
      };
}

/// A column in a saved report. [order] drives left-to-right placement;
/// `visible == false` hides the column without losing its configuration.
class SavedReportColumn {
  final String fieldKey;

  /// Header text to show instead of the raw field key, when set.
  final String? labelOverride;
  final bool visible;
  final int order;

  /// Optional preferred render width. Advisory only — the engine ignores it.
  final double? width;

  const SavedReportColumn({
    required this.fieldKey,
    this.labelOverride,
    this.visible = true,
    required this.order,
    this.width,
  });

  /// The header label this column contributes to a `ReportResult` — the
  /// override when present, otherwise the raw field key.
  String get resolvedLabel => labelOverride ?? fieldKey;

  factory SavedReportColumn.fromJson(Map<String, dynamic> json) =>
      SavedReportColumn(
        fieldKey: json['fieldKey'] as String,
        labelOverride: json['labelOverride'] as String?,
        visible: json['visible'] as bool? ?? true,
        order: json['order'] as int,
        width: (json['width'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'fieldKey': fieldKey,
        if (labelOverride != null) 'labelOverride': labelOverride,
        'visible': visible,
        'order': order,
        if (width != null) 'width': width,
      };
}

/// A generic, app-neutral saved/customised report. (ADR-050)
class SavedReportDefinition {
  final String id;
  final String name;

  /// The built-in `ReportDefinition.id` this was derived from, if any.
  final String? baseReportId;

  /// The DocType whose documents the report queries.
  final String sourceDocType;

  /// The user who owns (and, when `private`, exclusively sees) this report.
  final String ownerUserId;
  final SavedReportVisibility visibility;
  final List<SavedReportColumn> columns;
  final List<SavedReportFilter> filters;
  final List<SavedReportSort> sorts;

  /// Field keys the report groups by (C7). When non-empty the report executes
  /// as a grouped/aggregated report: one output row per distinct group, with an
  /// [aggregates] column set instead of the raw [columns].
  final List<String> groupBy;

  /// Aggregate columns computed per group. Only consulted when [groupBy] is
  /// non-empty.
  final List<SavedReportAggregate> aggregates;

  /// Optional chart over the grouped result. Only consulted when [groupBy] and
  /// [aggregates] are non-empty.
  final SavedReportChart? chart;

  final DateTime createdAt;
  final DateTime updatedAt;

  SavedReportDefinition({
    String? id,
    required this.name,
    this.baseReportId,
    required this.sourceDocType,
    required this.ownerUserId,
    this.visibility = SavedReportVisibility.private,
    this.columns = const [],
    this.filters = const [],
    this.sorts = const [],
    this.groupBy = const [],
    this.aggregates = const [],
    this.chart,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Visible columns in [order], ties broken by their original array index so
  /// ordering is deterministic. These define the `ReportResult` column set.
  List<SavedReportColumn> get visibleColumnsInOrder {
    final indexed = columns.asMap().entries.where((e) => e.value.visible).toList()
      ..sort((a, b) {
        final byOrder = a.value.order.compareTo(b.value.order);
        return byOrder != 0 ? byOrder : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
  }

  /// Whether this report executes as a grouped/aggregated report (C7).
  bool get isGrouped => groupBy.isNotEmpty && aggregates.isNotEmpty;

  /// Ownership/visibility gate. `private` reports are reachable only by their
  /// owner; `shared` reports are reachable by anyone (document-level access is
  /// still enforced separately when the report runs).
  bool canBeAccessed(String userId) =>
      visibility == SavedReportVisibility.shared || userId == ownerUserId;

  /// Clone a built-in [ReportDefinition] into editable saved-report
  /// configuration. Every declared column becomes a visible column in
  /// declaration order. Filters and sorts start empty — Dart report
  /// definitions declare filtering as a `filterExpression`, not as structured
  /// per-field filters, so there is nothing to seed.
  factory SavedReportDefinition.fromReport(
    ReportDefinition report, {
    String? id,
    String? name,
    required String ownerUserId,
    SavedReportVisibility visibility = SavedReportVisibility.private,
    DateTime? now,
  }) {
    final ts = now ?? DateTime.now();
    final columns = [
      for (var i = 0; i < report.columns.length; i++)
        SavedReportColumn(
            fieldKey: report.columns[i].fieldKey, visible: true, order: i),
    ];
    return SavedReportDefinition(
      id: id,
      name: name ?? report.name,
      baseReportId: report.id,
      sourceDocType: report.docType,
      ownerUserId: ownerUserId,
      visibility: visibility,
      columns: columns,
      createdAt: ts,
      updatedAt: ts,
    );
  }

  factory SavedReportDefinition.fromJson(Map<String, dynamic> json) =>
      SavedReportDefinition(
        id: json['id'] as String,
        name: json['name'] as String,
        baseReportId: json['baseReportId'] as String?,
        sourceDocType: json['sourceDocType'] as String,
        ownerUserId: json['ownerUserId'] as String,
        visibility: _enumByName(SavedReportVisibility.values,
            json['visibility'] as String?, SavedReportVisibility.private),
        columns: (json['columns'] as List<dynamic>?)
                ?.map((c) =>
                    SavedReportColumn.fromJson(Map<String, dynamic>.from(c as Map)))
                .toList() ??
            const [],
        filters: (json['filters'] as List<dynamic>?)
                ?.map((f) =>
                    SavedReportFilter.fromJson(Map<String, dynamic>.from(f as Map)))
                .toList() ??
            const [],
        sorts: (json['sorts'] as List<dynamic>?)
                ?.map((s) =>
                    SavedReportSort.fromJson(Map<String, dynamic>.from(s as Map)))
                .toList() ??
            const [],
        groupBy: (json['groupBy'] as List<dynamic>?)
                ?.map((g) => g as String)
                .toList() ??
            const [],
        aggregates: (json['aggregates'] as List<dynamic>?)
                ?.map((a) => SavedReportAggregate.fromJson(
                    Map<String, dynamic>.from(a as Map)))
                .toList() ??
            const [],
        chart: json['chart'] == null
            ? null
            : SavedReportChart.fromJson(
                Map<String, dynamic>.from(json['chart'] as Map)),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (baseReportId != null) 'baseReportId': baseReportId,
        'sourceDocType': sourceDocType,
        'ownerUserId': ownerUserId,
        'visibility': visibility.name,
        'columns': columns.map((c) => c.toJson()).toList(),
        'filters': filters.map((f) => f.toJson()).toList(),
        'sorts': sorts.map((s) => s.toJson()).toList(),
        if (groupBy.isNotEmpty) 'groupBy': groupBy,
        if (aggregates.isNotEmpty)
          'aggregates': aggregates.map((a) => a.toJson()).toList(),
        if (chart != null) 'chart': chart!.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}
