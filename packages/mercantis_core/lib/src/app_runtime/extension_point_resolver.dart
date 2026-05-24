import '../notifications/event_emitter.dart';
import '../scheduling/scheduler_service.dart';
import '../scheduling/scheduled_task.dart';
import 'app_manifest.dart';

class ExtensionPointResolver {
  static void resolve(
    AppManifest manifest,
    EventEmitter emitter,
    SchedulerService scheduler,
  ) {
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
  }
}
