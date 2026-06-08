import '../notifications/event_emitter.dart';
import '../expression_engine/expression_evaluator.dart';
import '../document_engine/document.dart';
import 'automation_action_handler.dart';
import 'automation_action_registry.dart';

/// When an [AutomationRule] should fire on a schedule rather than in response
/// to a document event (`event == 'on_schedule'`). The [interval] name maps to
/// `TaskInterval`; [cron] supplies the 5-field expression when interval is
/// `cron`. (ADR-041)
class AutomationSchedule {
  final String interval;
  final String? cron;

  const AutomationSchedule({required this.interval, this.cron});

  factory AutomationSchedule.fromJson(Map<String, dynamic> json) =>
      AutomationSchedule(
        interval: json['interval'] as String? ?? 'daily',
        cron: json['cron'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'interval': interval,
        if (cron != null) 'cron': cron,
      };
}

class AutomationRule {
  final String id;
  final String event;
  final String? docType;
  final String? conditionExpression;
  final List<Map<String, dynamic>> actions;

  /// Present for `on_schedule` rules; null for document-event rules.
  final AutomationSchedule? schedule;

  const AutomationRule({
    required this.id,
    required this.event,
    this.docType,
    this.conditionExpression,
    required this.actions,
    this.schedule,
  });

  /// Whether this rule is driven by the scheduler rather than a document event.
  bool get isScheduled => event == 'on_schedule';

  factory AutomationRule.fromJson(Map<String, dynamic> json) => AutomationRule(
        id: json['id'] as String,
        event: json['event'] as String,
        docType: json['docType'] as String?,
        conditionExpression: json['conditionExpression'] as String?,
        actions: (json['actions'] as List<dynamic>?)
                ?.map((a) => Map<String, dynamic>.from(a as Map))
                .toList() ??
            [],
        schedule: json['schedule'] == null
            ? null
            : AutomationSchedule.fromJson(
                Map<String, dynamic>.from(json['schedule'] as Map)),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'event': event,
        if (docType != null) 'docType': docType,
        if (conditionExpression != null)
          'conditionExpression': conditionExpression,
        'actions': actions,
        if (schedule != null) 'schedule': schedule!.toJson(),
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
      await _runRuleForDocument(rule, document, context);
    }
  }

  /// Runs a scheduled (`on_schedule`) rule by fanning out across every document
  /// of the rule's docType, evaluating the rule condition per document and
  /// executing its actions for each match. A rule without a docType runs its
  /// actions once against a synthetic empty document. (ADR-041)
  Future<void> runScheduled(
    AutomationRule rule,
    AutomationContext context,
  ) async {
    if (rule.docType == null) {
      await _runRuleForDocument(
          rule, Document(id: '', docType: ''), context);
      return;
    }
    final documents = await context.documentEngine.list(rule.docType!);
    for (final document in documents) {
      await _runRuleForDocument(rule, document, context);
    }
  }

  /// Evaluates the rule's condition against [document] and, if it passes, runs
  /// every action. Shared by document-event and scheduled dispatch so both
  /// honour the same condition/error semantics: a failing condition skips the
  /// document, and a failing action never aborts the rest.
  Future<void> _runRuleForDocument(
    AutomationRule rule,
    Document document,
    AutomationContext context,
  ) async {
    if (rule.conditionExpression != null &&
        rule.conditionExpression!.isNotEmpty) {
      bool shouldRun;
      try {
        final ctx = EvaluationContext(fields: document.payload, user: {});
        shouldRun = _evaluator.evaluateBool(rule.conditionExpression!, ctx);
      } catch (_) {
        shouldRun = false;
      }
      if (!shouldRun) return;
    }

    for (final action in rule.actions) {
      final actionType = action['actionType'] as String?;
      if (actionType == null) continue;
      final parameters =
          Map<String, dynamic>.from(action['parameters'] as Map? ?? {});
      try {
        await _registry.execute(actionType, document, parameters, context);
      } catch (_) {
        // Log error but don't fail the rest of the rule.
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
