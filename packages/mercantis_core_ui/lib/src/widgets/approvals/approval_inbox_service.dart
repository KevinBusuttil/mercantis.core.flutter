import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ApprovalEntry {
  const ApprovalEntry({
    required this.id,
    required this.docType,
    required this.title,
    required this.requestedBy,
    required this.requestedAt,
    this.amount,
    this.subtitle,
    this.icon,
    this.workspaceId,
  });

  final String id;
  final String docType;
  final String title;
  final String requestedBy;
  final DateTime requestedAt;
  final String? amount;
  final String? subtitle;
  final IconData? icon;
  final String? workspaceId;

  String get route => '/form/$docType/$id';
}

abstract class ApprovalInboxSource {
  Future<List<ApprovalEntry>> fetchPending();
}

class StaticApprovalInboxSource implements ApprovalInboxSource {
  StaticApprovalInboxSource(this._entries);
  final List<ApprovalEntry> _entries;

  @override
  Future<List<ApprovalEntry>> fetchPending() async => _entries;
}

class ApprovalInboxService {
  ApprovalInboxService(this._source);
  final ApprovalInboxSource _source;

  Future<List<ApprovalEntry>> pending() => _source.fetchPending();
}

final approvalInboxSourceProvider = Provider<ApprovalInboxSource>(
  (_) => StaticApprovalInboxSource(const []),
);

final approvalInboxServiceProvider = Provider<ApprovalInboxService>(
  (ref) => ApprovalInboxService(ref.watch(approvalInboxSourceProvider)),
);

final pendingApprovalsProvider = FutureProvider<List<ApprovalEntry>>(
  (ref) => ref.watch(approvalInboxServiceProvider).pending(),
);
