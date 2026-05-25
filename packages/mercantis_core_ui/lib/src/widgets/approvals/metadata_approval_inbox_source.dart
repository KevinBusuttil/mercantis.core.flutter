import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import '../../metadata/metadata_display.dart';
import '../../providers/core_providers.dart';
import 'approval_inbox_service.dart';

/// Queries Core for documents in docStatus=0 across every submittable
/// DocType the user is allowed to read. Used as the production data
/// source for ApprovalInboxList.
class MetadataApprovalInboxSource implements ApprovalInboxSource {
  MetadataApprovalInboxSource(this._ref, {this.userRoles = const {}});
  final Ref _ref;
  final Set<String> userRoles;

  @override
  Future<List<ApprovalEntry>> fetchPending() async {
    final registry = await _ref.read(metadataRegistryProvider.future);
    final engine = await _ref.read(documentEngineProvider.future);
    final permissions = _ref.read(permissionEngineProvider);

    final allTypes = await registry.all();
    final entries = <ApprovalEntry>[];
    for (final type in allTypes) {
      if (!type.isSubmittable) continue;
      if (!permissions.canPerform(
        operation: DocumentOperation.read,
        on: type,
        userRoles: userRoles,
      )) continue;

      final docs = await engine.list(type.id, limit: 50);
      for (final d in docs) {
        if (d.docStatus != 0) continue;
        entries.add(ApprovalEntry(
          id: d.id,
          docType: type.id,
          title: '${d.id} · ${MetadataDisplay.titleFor(type, d)}',
          requestedBy: 'System',
          requestedAt: d.createdAt,
          amount: MetadataDisplay.amountFor(type, d),
          subtitle: MetadataDisplay.subtitleFor(type, d),
          icon: _iconFor(type),
        ));
      }
    }

    entries.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    return entries;
  }

  IconData _iconFor(DocType type) {
    final id = type.id.toLowerCase();
    if (id.contains('sales order')) return Icons.shopping_cart_outlined;
    if (id.contains('purchase order')) return Icons.shopping_basket_outlined;
    if (id.contains('invoice')) return Icons.receipt_long_outlined;
    if (id.contains('delivery')) return Icons.local_shipping_outlined;
    if (id.contains('stock')) return Icons.inventory_2_outlined;
    if (id.contains('payment')) return Icons.payments_outlined;
    if (id.contains('journal')) return Icons.menu_book_outlined;
    return Icons.fact_check_outlined;
  }
}
