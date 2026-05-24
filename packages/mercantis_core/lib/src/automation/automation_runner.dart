import '../notifications/event_emitter.dart';
import '../expression_engine/expression_evaluator.dart';
import '../document_engine/document.dart';
import 'automation_action_handler.dart';
import 'automation_action_registry.dart';

class AutomationRule {
  final String id;
  final String event;
  final String? docType;
  final String? conditionExpression;
  final List<Map<String, dynamic>> actions;

  const AutomationRule({
    required this.id,
    required this.event,
    this.docType,
    this.conditionExpression,
    required this.actions,
  });

  factory AutomationRule.fromJson(Map<String, dynamic> json) => AutomationRule(
        id: json['id'] as String,
        event: json['event'] as String,
        docType: json['docType'] as String?,
        conditionExpression: json['conditionExpression'] as String?,
        actions: (json['actions'] as List<dynamic>?)
                ?.map((a) => Map<String, dynamic>.from(a as Map))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'event': event,
        if (docType != null) 'docType': docType,
        if (conditionExpression != null)
          'conditionExpression': conditionExpression,
        'actions': actions,
      };
}

class AutomationRunner {
  final AutomationActionRegistry _registry;
  final ExpressionEvaluator _evaluator;
  final List<SubscriptionToken> _subscriptions = [];

  List<AutomationRule> rules = [];

  AutomationRunner({
    required AutomationActionRegistry registry,
    required ExpressionEvaluator evaluator,
  })  : _registry = registry,
        _evaluator = evaluator;

  void start(EventEmitter emitter, AutomationContext context) {
    _subscriptions.add(emitter.subscribe<DocumentSavedEvent>((e) async {
      await _processEvent('on_save', e.docType, e.document, context);
    }));
    _subscriptions.add(emitter.subscribe<DocumentSubmittedEvent>((e) async {
      await _processEvent('on_submit', e.docType, e.document, context);
    }));
    _subscriptions.add(emitter.subscribe<DocumentCancelledEvent>((e) async {
      await _processEvent('on_cancel', e.docType, e.document, context);
    }));
  }

  Future<void> _processEvent(
    String event,
    String docType,
    Document document,
    AutomationContext context,
  ) async {
    final matching = rules.where((r) {
      if (r.event != event) return false;
      if (r.docType != null && r.docType != docType) return false;
      return true;
    });

    for (final rule in matching) {
      bool shouldRun = true;
      if (rule.conditionExpression != null &&
          rule.conditionExpression!.isNotEmpty) {
        try {
          final ctx = EvaluationContext(fields: document.payload, user: {});
          shouldRun =
              _evaluator.evaluateBool(rule.conditionExpression!, ctx);
        } catch (_) {
          shouldRun = false;
        }
      }
      if (!shouldRun) continue;

      for (final action in rule.actions) {
        final actionType = action['actionType'] as String?;
        final parameters = Map<String, dynamic>.from(
            action['parameters'] as Map? ?? {});
        if (actionType == null) continue;
        try {
          await _registry.execute(
              actionType, document, parameters, context);
        } catch (_) {
          // Log error but don't fail the document save
        }
      }
    }
  }

  void stop() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }
}
