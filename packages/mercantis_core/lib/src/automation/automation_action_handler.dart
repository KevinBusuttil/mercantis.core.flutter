import '../document_engine/document.dart';
import '../document_engine/document_engine.dart';
import '../notifications/event_emitter.dart';

class AutomationContext {
  final DocumentEngine documentEngine;
  final String userId;
  final EventEmitter emitter;

  const AutomationContext({
    required this.documentEngine,
    required this.userId,
    required this.emitter,
  });
}

abstract class AutomationActionHandler {
  Future<void> execute(
    Document document,
    Map<String, dynamic> parameters,
    AutomationContext context,
  );
}
