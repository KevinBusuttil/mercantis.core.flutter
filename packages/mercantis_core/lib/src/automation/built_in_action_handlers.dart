import '../document_engine/document.dart';
import '../notifications/notification_log.dart';
import 'automation_action_handler.dart';
import 'automation_action_registry.dart';

class SetValueHandler implements AutomationActionHandler {
  const SetValueHandler();

  @override
  Future<void> execute(
    Document document,
    Map<String, dynamic> parameters,
    AutomationContext context,
  ) async {
    final field = parameters['field'] as String?;
    final value = parameters['value'];
    if (field == null) return;
    document.payload[field] = value;
    await context.documentEngine
        .save(document, {'System Manager'});
  }
}

class SetStatusHandler implements AutomationActionHandler {
  const SetStatusHandler();

  @override
  Future<void> execute(
    Document document,
    Map<String, dynamic> parameters,
    AutomationContext context,
  ) async {
    final status = parameters['status'] as String?;
    if (status == null) return;
    document.payload['status'] = status;
    await context.documentEngine.save(document, {'System Manager'});
  }
}

/// Records a notification to the [AutomationContext.notificationLog] sink, from
/// which the in-app [NotificationInbox] reads (ADR-048).
///
/// Parameters:
/// - `channel` (optional, default `default`) — logical transport.
/// - `recipient` (optional) — user id / email / role; null is the global feed.
/// - `subject` (optional, default `''`).
/// - `body` (optional, default `''`). `{field}` placeholders are expanded from
///   the document's payload; unknown placeholders are left literal.
class SendNotificationHandler implements AutomationActionHandler {
  const SendNotificationHandler();

  @override
  Future<void> execute(
    Document document,
    Map<String, dynamic> parameters,
    AutomationContext context,
  ) async {
    final sink = context.notificationLog;
    if (sink == null) return;

    final entry = NotificationLogEntry(
      appId: context.appId,
      docType: document.docType,
      documentId: document.id,
      channel: parameters['channel']?.toString() ?? 'default',
      recipient: parameters['recipient']?.toString(),
      subject: interpolate(parameters['subject']?.toString() ?? '', document),
      body: interpolate(parameters['body']?.toString() ?? '', document),
    );
    await sink.write(entry);
  }

  /// Expands `{field}` placeholders against [document]'s payload. Unknown
  /// placeholders are left literal (e.g. `{missing}`) so callers can spot them.
  static String interpolate(String template, Document document) {
    if (!template.contains('{')) return template;
    final result = StringBuffer();
    final buffer = StringBuffer();
    var inPlaceholder = false;
    for (final ch in template.split('')) {
      if (ch == '{') {
        if (inPlaceholder) {
          // A new '{' before closing the previous one: flush literally.
          result.write('{');
          result.write(buffer);
          buffer.clear();
        }
        inPlaceholder = true;
        continue;
      }
      if (ch == '}' && inPlaceholder) {
        final key = buffer.toString();
        final value = document.payload[key];
        if (value != null) {
          result.write(value);
        } else {
          result.write('{$key}');
        }
        buffer.clear();
        inPlaceholder = false;
        continue;
      }
      if (inPlaceholder) {
        buffer.write(ch);
      } else {
        result.write(ch);
      }
    }
    // Trailing unclosed placeholder: restore literally.
    if (inPlaceholder) {
      result.write('{');
      result.write(buffer);
    }
    return result.toString();
  }
}

class ValidateHandler implements AutomationActionHandler {
  const ValidateHandler();

  @override
  Future<void> execute(
    Document document,
    Map<String, dynamic> parameters,
    AutomationContext context,
  ) async {
    final message = parameters['message']?.toString() ?? 'Validation failed';
    final condition = parameters['condition']?.toString();
    if (condition == null) return;
    // Validation is typically handled by the validation pipeline
    // This action is a hook for custom validation logic
  }
}

class AssignHandler implements AutomationActionHandler {
  const AssignHandler();

  @override
  Future<void> execute(
    Document document,
    Map<String, dynamic> parameters,
    AutomationContext context,
  ) async {
    final assignTo = parameters['assign_to']?.toString();
    if (assignTo == null) return;
    document.payload['assigned_to'] = assignTo;
    await context.documentEngine.save(document, {'System Manager'});
  }
}

void registerBuiltInActionHandlers(AutomationActionRegistry registry) {
  registry.register('set_value', const SetValueHandler());
  registry.register('set_status', const SetStatusHandler());
  registry.register('send_notification', const SendNotificationHandler());
  registry.register('validate', const ValidateHandler());
  registry.register('assign', const AssignHandler());
}
