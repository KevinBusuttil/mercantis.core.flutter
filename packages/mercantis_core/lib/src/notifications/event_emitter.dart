import 'dart:async';
import '../document_engine/document.dart';

class DocumentSavedEvent {
  final Document document;
  final String docType;
  final String userId;
  const DocumentSavedEvent({required this.document, required this.docType, required this.userId});
}

class DocumentDeletedEvent {
  final String documentId;
  final String docType;
  final String userId;
  const DocumentDeletedEvent({required this.documentId, required this.docType, required this.userId});
}

class DocumentSubmittedEvent {
  final Document document;
  final String docType;
  final String userId;
  const DocumentSubmittedEvent({required this.document, required this.docType, required this.userId});
}

class DocumentCancelledEvent {
  final Document document;
  final String docType;
  final String userId;
  const DocumentCancelledEvent({required this.document, required this.docType, required this.userId});
}

class WorkflowTransitionEvent {
  final String documentId;
  final String workflow;
  final String fromState;
  final String toState;
  final String action;
  final String userId;
  const WorkflowTransitionEvent({
    required this.documentId,
    required this.workflow,
    required this.fromState,
    required this.toState,
    required this.action,
    required this.userId,
  });
}

class AppInstalledEvent {
  final String appId;
  final String version;
  const AppInstalledEvent({required this.appId, required this.version});
}

class SubscriptionToken {
  final void Function() _cancel;
  SubscriptionToken(this._cancel);
  void cancel() => _cancel();
}

class EventEmitter {
  final Map<Type, List<dynamic>> _handlers = {};

  SubscriptionToken subscribe<E>(void Function(E event) handler) {
    _handlers.putIfAbsent(E, () => []).add(handler);
    return SubscriptionToken(() {
      _handlers[E]?.remove(handler);
    });
  }

  void publish<E>(E event) {
    final handlers = _handlers[E];
    if (handlers == null) return;
    for (final handler in List.from(handlers)) {
      try {
        (handler as void Function(E))(event);
      } catch (_) {
        // Isolate handler errors
      }
    }
  }

  void dispose() => _handlers.clear();
}
