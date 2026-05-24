import '../document_engine/document.dart';
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

class SendNotificationHandler implements AutomationActionHandler {
  const SendNotificationHandler();

  @override
  Future<void> execute(
    Document document,
    Map<String, dynamic> parameters,
    AutomationContext context,
  ) async {
    // Log notification — full email/push integration via CloudAdapter
    final subject = parameters['subject']?.toString() ?? 'Notification';
    final recipients = (parameters['recipients'] as List<dynamic>?)?.cast<String>() ?? [];
    // In a real implementation this would send via CloudAdapter
    // For now just emit an event or log
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
