class WorkflowTransitionHistory {
  final String id;
  final String workflowId;
  final String documentId;
  final String fromState;
  final String toState;
  final String action;
  final String userId;
  final DateTime timestamp;

  const WorkflowTransitionHistory({
    required this.id,
    required this.workflowId,
    required this.documentId,
    required this.fromState,
    required this.toState,
    required this.action,
    required this.userId,
    required this.timestamp,
  });

  factory WorkflowTransitionHistory.fromDbRow(Map<String, dynamic> row) =>
      WorkflowTransitionHistory(
        id: row['id'] as String,
        workflowId: row['workflow_id'] as String,
        documentId: row['document_id'] as String,
        fromState: row['from_state'] as String,
        toState: row['to_state'] as String,
        action: row['action'] as String,
        userId: row['user_id'] as String,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
      );

  Map<String, dynamic> toDbRow() => {
        'id': id,
        'workflow_id': workflowId,
        'document_id': documentId,
        'from_state': fromState,
        'to_state': toState,
        'action': action,
        'user_id': userId,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };
}
