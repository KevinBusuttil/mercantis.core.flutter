import 'field_definition.dart';
import 'permission_rule.dart';
import 'sync_policy.dart';
import 'index_definition.dart';
import 'document_naming_rule.dart';

class DocType {
  final String id;
  final String name;
  final String? module;
  final bool isSubmittable;
  final bool isSingleton;
  final bool isTree;
  final bool isChild;
  final String? parentField;
  final List<FieldDefinition> fields;
  final List<PermissionRule> permissions;
  final SyncPolicy syncPolicy;
  final List<IndexDefinition> indexes;
  final String? workflowId;
  final bool isCustom;
  final String? namingRule;

  /// Conditional naming series (ADR-040). Evaluated in order before
  /// [namingRule]; the first whose condition matches is used.
  final List<DocumentNamingRule> namingRules;
  final bool trackChanges;
  final int? maxAttachments;
  final bool makeAttachmentsPublic;

  /// Boolean expression auto-applied by `DocumentEngine.list` to gate which
  /// rows the current user may see (ADR-037). Evaluated per document with the
  /// row's fields plus `user.id` / `user.roles` in context; rows for which it
  /// is false are dropped. Null means no row-level restriction.
  final String? rowAccessExpression;

  const DocType({
    required this.id,
    required this.name,
    this.module,
    this.isSubmittable = false,
    this.isSingleton = false,
    this.isTree = false,
    this.isChild = false,
    this.parentField,
    this.fields = const [],
    this.permissions = const [],
    this.syncPolicy = const SyncPolicy(),
    this.indexes = const [],
    this.workflowId,
    this.isCustom = false,
    this.namingRule,
    this.namingRules = const [],
    this.trackChanges = false,
    this.maxAttachments,
    this.makeAttachmentsPublic = false,
    this.rowAccessExpression,
  });

  factory DocType.fromJson(Map<String, dynamic> json) => DocType(
        id: json['id'] as String,
        name: json['name'] as String,
        module: json['module'] as String?,
        isSubmittable: (json['isSubmittable'] as bool?) ?? false,
        isSingleton: (json['isSingleton'] as bool?) ?? false,
        isTree: (json['isTree'] as bool?) ?? false,
        isChild: (json['isChild'] as bool?) ?? false,
        parentField: json['parentField'] as String?,
        fields: (json['fields'] as List<dynamic>?)
                ?.map((f) => FieldDefinition.fromJson(f as Map<String, dynamic>))
                .toList() ??
            const [],
        permissions: (json['permissions'] as List<dynamic>?)
                ?.map((p) => PermissionRule.fromJson(p as Map<String, dynamic>))
                .toList() ??
            const [],
        syncPolicy: json['syncPolicy'] != null
            ? SyncPolicy.fromJson(json['syncPolicy'] as Map<String, dynamic>)
            : const SyncPolicy(),
        indexes: (json['indexes'] as List<dynamic>?)
                ?.map((i) => IndexDefinition.fromJson(i as Map<String, dynamic>))
                .toList() ??
            const [],
        workflowId: json['workflowId'] as String?,
        isCustom: (json['isCustom'] as bool?) ?? false,
        namingRule: json['namingRule'] as String?,
        namingRules: (json['namingRules'] as List<dynamic>?)
                ?.map((r) =>
                    DocumentNamingRule.fromJson(r as Map<String, dynamic>))
                .toList() ??
            const [],
        trackChanges: (json['trackChanges'] as bool?) ?? false,
        maxAttachments: json['maxAttachments'] as int?,
        makeAttachmentsPublic: (json['makeAttachmentsPublic'] as bool?) ?? false,
        rowAccessExpression: json['rowAccessExpression'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (module != null) 'module': module,
        'isSubmittable': isSubmittable,
        'isSingleton': isSingleton,
        'isTree': isTree,
        'isChild': isChild,
        if (parentField != null) 'parentField': parentField,
        'fields': fields.map((f) => f.toJson()).toList(),
        'permissions': permissions.map((p) => p.toJson()).toList(),
        'syncPolicy': syncPolicy.toJson(),
        'indexes': indexes.map((i) => i.toJson()).toList(),
        if (workflowId != null) 'workflowId': workflowId,
        'isCustom': isCustom,
        if (namingRule != null) 'namingRule': namingRule,
        if (namingRules.isNotEmpty)
          'namingRules': namingRules.map((r) => r.toJson()).toList(),
        'trackChanges': trackChanges,
        if (maxAttachments != null) 'maxAttachments': maxAttachments,
        'makeAttachmentsPublic': makeAttachmentsPublic,
        if (rowAccessExpression != null) 'rowAccessExpression': rowAccessExpression,
      };

  DocType copyWith({
    String? id, String? name, String? module, bool? isSubmittable, bool? isSingleton,
    bool? isTree, bool? isChild, String? parentField, List<FieldDefinition>? fields,
    List<PermissionRule>? permissions, SyncPolicy? syncPolicy, List<IndexDefinition>? indexes,
    String? workflowId, bool? isCustom, String? namingRule,
    List<DocumentNamingRule>? namingRules, bool? trackChanges,
    int? maxAttachments, bool? makeAttachmentsPublic, String? rowAccessExpression,
  }) =>
      DocType(
        id: id ?? this.id,
        name: name ?? this.name,
        module: module ?? this.module,
        isSubmittable: isSubmittable ?? this.isSubmittable,
        isSingleton: isSingleton ?? this.isSingleton,
        isTree: isTree ?? this.isTree,
        isChild: isChild ?? this.isChild,
        parentField: parentField ?? this.parentField,
        fields: fields ?? this.fields,
        permissions: permissions ?? this.permissions,
        syncPolicy: syncPolicy ?? this.syncPolicy,
        indexes: indexes ?? this.indexes,
        workflowId: workflowId ?? this.workflowId,
        isCustom: isCustom ?? this.isCustom,
        namingRule: namingRule ?? this.namingRule,
        namingRules: namingRules ?? this.namingRules,
        trackChanges: trackChanges ?? this.trackChanges,
        maxAttachments: maxAttachments ?? this.maxAttachments,
        makeAttachmentsPublic: makeAttachmentsPublic ?? this.makeAttachmentsPublic,
        rowAccessExpression: rowAccessExpression ?? this.rowAccessExpression,
      );
}
