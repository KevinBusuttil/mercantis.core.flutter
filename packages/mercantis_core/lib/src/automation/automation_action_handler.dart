import '../document_engine/document.dart';
import '../document_engine/document_engine.dart';
import '../notifications/event_emitter.dart';
import '../notifications/notification_log.dart';

class AutomationContext {
  final DocumentEngine documentEngine;
  final String userId;
  final EventEmitter emitter;

  /// App that owns the running rule, recorded on notification log entries.
  final String appId;

  /// Sink that `send_notification` writes to. When null, notifications are not
  /// persisted (the runtime stays observable but produces no inbox entries).
  final NotificationLogWriter? notificationLog;

  const AutomationContext({
    required this.documentEngine,
    required this.userId,
    required this.emitter,
    this.appId = '',
    this.notificationLog,
  });
}

abstract class AutomationActionHandler {
  Future<void> execute(
    Document document,
    Map<String, dynamic> parameters,
    AutomationContext context,
  );
}
