import '../metadata/doc_type.dart';
import '../metadata/field_definition.dart';
import '../document_engine/document.dart';
import '../expression_engine/expression_evaluator.dart';
import '../document_engine/validation_pipeline.dart';

class PermissionEngine {
  const PermissionEngine();

  bool canPerform({
    required DocumentOperation operation,
    required DocType on,
    required Set<String> userRoles,
  }) {
    if (userRoles.contains('System Manager') || userRoles.contains('Administrator')) {
      return true;
    }
    // Cancel is a distinct authority (C5), but for back-compat a `delete` grant
    // still covers it in the lenient (default) mode. A fail-closed DocType opts
    // out of that fallback and demands an explicit `cancel` grant.
    final cancelFallsBackToDelete =
        operation == DocumentOperation.cancel && !on.failClosed;
    for (final rule in on.permissions) {
      if (!userRoles.contains(rule.role)) continue;
      switch (operation) {
        case DocumentOperation.read:
          if (rule.read) return true;
        case DocumentOperation.write:
          if (rule.write) return true;
        case DocumentOperation.create:
          if (rule.create) return true;
        case DocumentOperation.delete:
          if (rule.delete) return true;
        case DocumentOperation.submit:
          if (rule.submit) return true;
        case DocumentOperation.cancel:
          if (rule.cancel) return true;
          if (cancelFallsBackToDelete && rule.delete) return true;
        case DocumentOperation.amend:
          if (rule.amend) return true;
      }
    }
    return false;
  }

  bool canAccessField({
    required String fieldKey,
    required DocType on,
    required Set<String> userRoles,
    required FieldOperation operation,
  }) {
    if (userRoles.contains('System Manager') || userRoles.contains('Administrator')) {
      return true;
    }
    try {
      final field = on.fields.firstWhere((f) => f.key == fieldKey);
      final perms = field.permissions;
      if (perms == null) return true;
      final roles = operation == FieldOperation.read ? perms.readRoles : perms.writeRoles;
      return roles.isEmpty || roles.any((r) => userRoles.contains(r));
    } catch (_) {
      return false;
    }
  }

  bool canAccessRow({
    required Document document,
    required Set<String> userRoles,
    String? rowExpression,
    String userId = '',
    Map<String, dynamic> userAttributes = const {},
    ExpressionEvaluator? expressionEvaluator,
  }) {
    if (rowExpression == null || rowExpression.trim().isEmpty) return true;
    if (expressionEvaluator == null) return true;
    try {
      final userContext = <String, dynamic>{
        'id': userId,
        'roles': userRoles.toList(),
        ...userAttributes,
      };
      final ctx = EvaluationContext(
        fields: document.payload,
        user: userContext,
      );
      return expressionEvaluator.evaluateBool(rowExpression, ctx);
    } catch (_) {
      return false;
    }
  }
}
