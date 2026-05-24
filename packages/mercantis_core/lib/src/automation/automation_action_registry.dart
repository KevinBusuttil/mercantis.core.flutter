import '../document_engine/document.dart';
import 'automation_action_handler.dart';

class AutomationActionRegistry {
  final Map<String, AutomationActionHandler> _handlers = {};

  void register(String actionType, AutomationActionHandler handler) {
    _handlers[actionType] = handler;
  }

  void unregister(String actionType) => _handlers.remove(actionType);

  AutomationActionHandler? handler(String actionType) => _handlers[actionType];

  Future<void> execute(
    String actionType,
    Document document,
    Map<String, dynamic> parameters,
    AutomationContext context,
  ) async {
    final h = _handlers[actionType];
    if (h == null) throw Exception('Unknown automation action type: $actionType');
    await h.execute(document, parameters, context);
  }

  bool hasHandler(String actionType) => _handlers.containsKey(actionType);
}
