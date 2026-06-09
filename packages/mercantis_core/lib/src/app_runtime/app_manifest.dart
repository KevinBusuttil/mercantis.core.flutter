import '../metadata/doc_type.dart';
import '../workflow/workflow_engine.dart';
import '../automation/automation_runner.dart';

class ReportColumn {
  final String fieldKey;
  final String label;
  final String? type;
  const ReportColumn({required this.fieldKey, required this.label, this.type});
  factory ReportColumn.fromJson(Map<String, dynamic> json) => ReportColumn(
    fieldKey: json['fieldKey'] as String,
    label: json['label'] as String,
    type: json['type'] as String?,
  );
  Map<String, dynamic> toJson() => {'fieldKey': fieldKey, 'label': label, if (type != null) 'type': type};
}

class ReportDefinition {
  final String id;
  final String name;
  final String docType;
  final List<String> roles;
  final List<ReportColumn> columns;
  final String? filterExpression;

  const ReportDefinition({
    required this.id,
    required this.name,
    required this.docType,
    this.roles = const [],
    this.columns = const [],
    this.filterExpression,
  });

  factory ReportDefinition.fromJson(Map<String, dynamic> json) => ReportDefinition(
    id: json['id'] as String,
    name: json['name'] as String,
    docType: json['docType'] as String,
    roles: (json['roles'] as List<dynamic>?)?.cast<String>() ?? const [],
    columns: (json['columns'] as List<dynamic>?)?.map((c) => ReportColumn.fromJson(c as Map<String, dynamic>)).toList() ?? const [],
    filterExpression: json['filterExpression'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'docType': docType,
    'roles': roles,
    'columns': columns.map((c) => c.toJson()).toList(),
    if (filterExpression != null) 'filterExpression': filterExpression,
  };
}

class DashboardWidget {
  final String id;
  final String type;
  final String label;
  final Map<String, dynamic> config;
  const DashboardWidget({required this.id, required this.type, required this.label, this.config = const {}});
  factory DashboardWidget.fromJson(Map<String, dynamic> json) => DashboardWidget(
    id: json['id'] as String, type: json['type'] as String, label: json['label'] as String,
    config: Map<String, dynamic>.from(json['config'] as Map? ?? {}),
  );
  Map<String, dynamic> toJson() => {'id': id, 'type': type, 'label': label, 'config': config};
}

class DashboardDefinition {
  final String id;
  final String name;
  final List<DashboardWidget> widgets;
  final List<String> roles;
  const DashboardDefinition({required this.id, required this.name, this.widgets = const [], this.roles = const []});
  factory DashboardDefinition.fromJson(Map<String, dynamic> json) => DashboardDefinition(
    id: json['id'] as String, name: json['name'] as String,
    widgets: (json['widgets'] as List<dynamic>?)?.map((w) => DashboardWidget.fromJson(w as Map<String, dynamic>)).toList() ?? const [],
    roles: (json['roles'] as List<dynamic>?)?.cast<String>() ?? const [],
  );
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'widgets': widgets.map((w) => w.toJson()).toList(), 'roles': roles};
}

class SchedulerEventDeclaration {
  final String id;
  final String event;
  final String actionType;
  final Map<String, dynamic> parameters;
  const SchedulerEventDeclaration({required this.id, required this.event, required this.actionType, this.parameters = const {}});
  factory SchedulerEventDeclaration.fromJson(Map<String, dynamic> json) => SchedulerEventDeclaration(
    id: json['id'] as String, event: json['event'] as String, actionType: json['actionType'] as String,
    parameters: Map<String, dynamic>.from(json['parameters'] as Map? ?? {}),
  );
  Map<String, dynamic> toJson() => {'id': id, 'event': event, 'actionType': actionType, 'parameters': parameters};
}

class DocumentEventSubscription {
  final String event;
  final String? docType;
  final String actionType;
  final Map<String, dynamic> parameters;
  const DocumentEventSubscription({required this.event, this.docType, required this.actionType, this.parameters = const {}});
  factory DocumentEventSubscription.fromJson(Map<String, dynamic> json) => DocumentEventSubscription(
    event: json['event'] as String, docType: json['docType'] as String?,
    actionType: json['actionType'] as String,
    parameters: Map<String, dynamic>.from(json['parameters'] as Map? ?? {}),
  );
  Map<String, dynamic> toJson() => {'event': event, if (docType != null) 'docType': docType, 'actionType': actionType, 'parameters': parameters};
}

class AppManifest {
  final String id;
  final String version;
  final String name;
  final String? minimumCoreVersion;
  final List<DocType> docTypes;
  final List<WorkflowDefinition> workflows;
  final List<ReportDefinition> reports;
  final List<AutomationRule> automationRules;
  final List<DashboardDefinition> dashboards;
  final List<SchedulerEventDeclaration> schedulerEvents;
  final List<DocumentEventSubscription> documentEventSubscriptions;
  final Map<String, dynamic> fixtures;

  const AppManifest({
    required this.id,
    required this.version,
    required this.name,
    this.minimumCoreVersion,
    this.docTypes = const [],
    this.workflows = const [],
    this.reports = const [],
    this.automationRules = const [],
    this.dashboards = const [],
    this.schedulerEvents = const [],
    this.documentEventSubscriptions = const [],
    this.fixtures = const {},
  });

  factory AppManifest.fromJson(Map<String, dynamic> json) => AppManifest(
    id: json['id'] as String,
    version: json['version'] as String,
    name: json['name'] as String,
    minimumCoreVersion: json['minimumCoreVersion'] as String?,
    docTypes: (json['docTypes'] as List<dynamic>?)?.map((d) => DocType.fromJson(d as Map<String, dynamic>)).toList() ?? const [],
    workflows: (json['workflows'] as List<dynamic>?)?.map((w) => WorkflowDefinition.fromJson(w as Map<String, dynamic>)).toList() ?? const [],
    reports: (json['reports'] as List<dynamic>?)?.map((r) => ReportDefinition.fromJson(r as Map<String, dynamic>)).toList() ?? const [],
    automationRules: (json['automationRules'] as List<dynamic>?)?.map((a) => AutomationRule.fromJson(a as Map<String, dynamic>)).toList() ?? const [],
    dashboards: (json['dashboards'] as List<dynamic>?)?.map((d) => DashboardDefinition.fromJson(d as Map<String, dynamic>)).toList() ?? const [],
    schedulerEvents: (json['schedulerEvents'] as List<dynamic>?)?.map((s) => SchedulerEventDeclaration.fromJson(s as Map<String, dynamic>)).toList() ?? const [],
    documentEventSubscriptions: (json['documentEventSubscriptions'] as List<dynamic>?)?.map((s) => DocumentEventSubscription.fromJson(s as Map<String, dynamic>)).toList() ?? const [],
    fixtures: Map<String, dynamic>.from(json['fixtures'] as Map? ?? {}),
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'version': version, 'name': name,
    if (minimumCoreVersion != null) 'minimumCoreVersion': minimumCoreVersion,
    'docTypes': docTypes.map((d) => d.toJson()).toList(),
    'workflows': workflows.map((w) => w.toJson()).toList(),
    'reports': reports.map((r) => r.toJson()).toList(),
    'automationRules': automationRules.map((a) => a.toJson()).toList(),
    'dashboards': dashboards.map((d) => d.toJson()).toList(),
    'schedulerEvents': schedulerEvents.map((s) => s.toJson()).toList(),
    'documentEventSubscriptions': documentEventSubscriptions.map((s) => s.toJson()).toList(),
    'fixtures': fixtures,
  };
}
