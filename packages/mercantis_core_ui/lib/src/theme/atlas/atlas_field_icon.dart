import 'package:flutter/material.dart';
import 'package:mercantis_core/mercantis_core.dart';

/// Chooses a leading glyph for a field row. Prefers a match on the field's key
/// (so common ERP fields read at a glance), then falls back to the field type.
/// Returns null when nothing meaningful fits — the row then renders chip-less.
IconData? atlasFieldIcon(FieldDefinition field) {
  final k = field.key.toLowerCase();
  bool has(String s) => k.contains(s);

  if (has('customer') || has('contact') || has('lead') || has('party')) {
    return Icons.person_outline;
  }
  if (has('supplier') || has('vendor')) return Icons.local_shipping_outlined;
  if (has('item') || has('product')) return Icons.inventory_2_outlined;
  if (has('warehouse')) return Icons.warehouse_outlined;
  if (has('currency')) return Icons.attach_money;
  if (has('tax')) return Icons.percent;
  if (has('account') || has('ledger')) return Icons.account_balance_outlined;
  if (has('cost_center') || has('cost centre')) return Icons.hub_outlined;
  if (has('company')) return Icons.business_outlined;
  if (has('project')) return Icons.folder_outlined;
  if (has('description') || has('remarks') || has('notes') || has('terms')) {
    return Icons.notes_outlined;
  }

  switch (field.type) {
    case FieldType.date:
    case FieldType.dateTime:
      return Icons.calendar_today_outlined;
    case FieldType.time:
      return Icons.schedule_outlined;
    case FieldType.link:
    case FieldType.dynamicLink:
      return Icons.link_outlined;
    case FieldType.select:
    case FieldType.autocomplete:
      return Icons.expand_more;
    case FieldType.currency:
      return Icons.attach_money;
    case FieldType.percent:
      return Icons.percent;
    default:
      return null;
  }
}
