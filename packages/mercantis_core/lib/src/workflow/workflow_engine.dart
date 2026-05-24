import 'dart:convert';
import 'package:sqflite_common/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../document_engine/document.dart';
import '../expression_engine/expression_evaluator.dart';
import 'workflow_transition_history.dart';

class WorkflowState {
  final String name;
  final bool isDefault;
  final bool allowEdit;
  final String? docStatus;

  const WorkflowState({
    required this.name,
    this.isDefault = false,
    this.allowEdit = true,
    this.docStatus,
  });

  factory WorkflowState.fromJson(Map<String, dynamic> json) => WorkflowState(
        name: json['name'] as String,
        isDefault: (json['isDefault'] as bool?) ?? false,
        allowEdit: (json['allowEdit'] as bool?) ?? true,
        docStatus: json['docStatus'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'isDefault': isDefault,
        'allowEdit': allowEdit,
        if (docStatus != null) 'docStatus': docStatus,
      };
}

class WorkflowTransition {
  final String id;
  final String fromState;
  final String toState;
  final String action;
  final List<String> allowedRoles;
  final String? conditionExpression;

  const WorkflowTransition({
    required this.id,
    required this.fromState,
    required this.toState,
    required this.action,
    this.allowedRoles = const [],
    this.conditionExpression,
  });

  factory WorkflowTransition.fromJson(Map<String, dynamic> json) =>
      WorkflowTransition(
        id: json['id'] as String,
        fromState: json['fromState'] as String,
        toState: json['toState'] as String,
        action: json['action'] as String,
        allowedRoles:
            (json['allowedRoles'] as List<dynamic>?)?.cast<String>() ??
                const [],
        conditionExpression: json['conditionExpression'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromState': fromState,
        'toState': toState,
        'action': action,
        'allowedRoles': allowedRoles,
        if (conditionExpression != null)
          'conditionExpression': conditionExpression,
      };
}

class WorkflowDefinition {
  final String id;
  final String? appId;
  final List<WorkflowState> states;
  final List<WorkflowTransition> transitions;

  const WorkflowDefinition({
    required this.id,
    this.appId,
    required this.states,
    required this.transitions,
  });

  factory WorkflowDefinition.fromJson(Map<String, dynamic> json) =>
      WorkflowDefinition(
        id: json['id'] as String,
        appId: json['appId'] as String?,
        states: (json['states'] as List<dynamic>?)
                ?.map((s) =>
                    WorkflowState.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
        transitions: (json['transitions'] as List<dynamic>?)
                ?.map((t) =>
                    WorkflowTransition.fromJson(t as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (appId != null) 'appId': appId,
        'states': states.map((s) => s.toJson()).toList(),
        'transitions': transitions.map((t) => t.toJson()).toList(),
      };

  String get defaultState {
    try {
      return states.firstWhere((s) => s.isDefault).name;
    } catch (_) {
      return states.isNotEmpty ? states.first.name : '';
    }
  }
}

class WorkflowEngine {
  final Database _db;
  static const _uuid = Uuid();

  const WorkflowEngine(this._db);

  List<WorkflowTransition> availableTransitions({
    required WorkflowDefinition workflow,
    required String currentState,
    required Set<String> userRoles,
    required Document document,
    ExpressionEvaluator? expressionEvaluator,
  }) {
    return workflow.transitions.where((t) {
      if (t.fromState != currentState) return false;
      if (t.allowedRoles.isNotEmpty &&
          !t.allowedRoles.any((r) => userRoles.contains(r))) {
        return false;
      }
      if (t.conditionExpression != null &&
          t.conditionExpression!.isNotEmpty &&
          expressionEvaluator != null) {
        try {
          final ctx = EvaluationContext(fields: document.payload, user: {});
          return expressionEvaluator.evaluateBool(
              t.conditionExpression!, ctx);
        } catch (_) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Future<Document> transition({
    required Document document,
    required WorkflowDefinition workflow,
    required String action,
    required Set<String> userRoles,
    ExpressionEvaluator? expressionEvaluator,
  }) async {
    final currentState =
        (document.payload['workflow_state'] as String?) ??
            workflow.defaultState;
    final available = availableTransitions(
      workflow: workflow,
      currentState: currentState,
      userRoles: userRoles,
      document: document,
      expressionEvaluator: expressionEvaluator,
    );
    final t = available.firstWhere(
      (t) => t.action == action,
      orElse: () => throw Exception(
          'Transition "$action" not available from state "$currentState"'),
    );

    document.payload['workflow_state'] = t.toState;
    document.modifiedAt = DateTime.now();

    await _db.update(
      'documents',
      {
        'payload': jsonEncode(document.payload),
        'modified_at': document.modifiedAt!.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [document.id],
    );

    await _db.insert('workflow_transitions', {
      'id': _uuid.v4(),
      'workflow_id': workflow.id,
      'document_id': document.id,
      'from_state': currentState,
      'to_state': t.toState,
      'action': action,
      'user_id': 'system',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    return document;
  }

  Future<WorkflowDefinition?> getWorkflow(String workflowId) async {
    final rows = await _db
        .query('workflows', where: 'id = ?', whereArgs: [workflowId]);
    if (rows.isEmpty) return null;
    return WorkflowDefinition.fromJson(
      jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>,
    );
  }
}
