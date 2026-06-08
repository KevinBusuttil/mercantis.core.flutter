import '../automation/automation_action_handler.dart';
import '../automation/automation_runner.dart';
import '../notifications/event_emitter.dart';
import '../scheduling/scheduler_service.dart';
import '../scheduling/scheduled_task.dart';
import 'app_manifest.dart';

class ExtensionPointResolver {
  static void resolve(
    AppManifest manifest,
    EventEmitter emitter,
    SchedulerService scheduler, {
    AutomationRunner? automationRunner,
    AutomationContext? automationContext,
  }) {
    // Register scheduler events
    for (final decl in manifest.schedulerEvents) {
      final interval = TaskInterval.values.firstWhere(
        (i) => i.name == decl.event,
        orElse: () => TaskInterval.daily,
      );
      scheduler.register(ScheduledTask(
        key: '${manifest.id}::${decl.id}',
        appId: manifest.id,
        interval: interval,
        dispatch: () async {
          // Dispatch to the automation action registry
        },
      ));
    }

    // ADR-041: register `on_schedule` automation rules as scheduled tasks so
    // the scheduler fans them out across matching documents when due.
    if (automationRunner != null && automationContext != null) {
      for (final rule in manifest.automationRules) {
        final sched = rule.schedule;
        if (!rule.isScheduled || sched == null) continue;
        final interval = TaskInterval.values.firstWhere(
          (i) => i.name == sched.interval,
          orElse: () => TaskInterval.daily,
        );
        scheduler.register(ScheduledTask(
          key: '${manifest.id}::automation::${rule.id}',
          appId: manifest.id,
          interval: interval,
          cronExpression: sched.cron,
          dispatch: () => automationRunner.runScheduled(rule, automationContext),
        ));
      }
    }
  }
}
