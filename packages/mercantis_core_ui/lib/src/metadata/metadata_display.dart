import 'package:mercantis_core/mercantis_core.dart';
import '../widgets/status_chip.dart';

/// Heuristics for presenting metadata-driven documents in the new UI.
class MetadataDisplay {
  const MetadataDisplay._();

  static const _titleKeys = <String>[
    'title',
    'customer_name',
    'supplier_name',
    'item_name',
    'lead_name',
    'opportunity_name',
    'company_name',
    'account_name',
    'first_name',
    'subject',
    'name',
    'description',
  ];

  static const _subtitleKeys = <String>[
    'customer',
    'supplier',
    'lead',
    'opportunity',
    'company',
    'item_group',
    'territory',
    'description',
  ];

  static const _amountKeys = <String>[
    'grand_total',
    'total',
    'outstanding_amount',
    'paid_amount',
    'opportunity_amount',
    'standard_rate',
  ];

  static const _dateKeys = <String>[
    'transaction_date',
    'posting_date',
    'delivery_date',
    'due_date',
    'expected_closing',
    'valid_till',
    'year_start_date',
  ];

  /// Pick a human-friendly title for a document.
  /// Falls back to the document id if nothing matches.
  static String titleFor(DocType type, Document doc) {
    final payload = doc.payload;
    for (final key in _titleKeys) {
      final v = payload[key];
      if (v is String && v.trim().isNotEmpty) return v;
    }
    // first_name + last_name
    final fn = payload['first_name'];
    final ln = payload['last_name'];
    if (fn is String && ln is String && (fn.isNotEmpty || ln.isNotEmpty)) {
      return [fn, ln].where((s) => s.isNotEmpty).join(' ');
    }
    return doc.id.isEmpty ? type.name : doc.id;
  }

  /// Secondary descriptor — usually a related party or category.
  static String? subtitleFor(DocType type, Document doc) {
    final payload = doc.payload;
    for (final key in _subtitleKeys) {
      final v = payload[key];
      if (v is String && v.trim().isNotEmpty) return v;
    }
    return null;
  }

  /// Headline numeric value (formatted) — typically a grand total or amount.
  static String? amountFor(DocType type, Document doc) {
    final payload = doc.payload;
    for (final key in _amountKeys) {
      final v = payload[key];
      if (v is num && v != 0) return _formatCurrency(v.toDouble());
      if (v is String && v.trim().isNotEmpty) {
        final parsed = double.tryParse(v);
        if (parsed != null && parsed != 0) return _formatCurrency(parsed);
      }
    }
    return null;
  }

  /// Reasonable timestamp string for a list row.
  static String? timestampFor(DocType type, Document doc) {
    final payload = doc.payload;
    for (final key in _dateKeys) {
      final v = payload[key];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  static String docStatusLabel(int docStatus) => switch (docStatus) {
        0 => 'Draft',
        1 => 'Submitted',
        2 => 'Cancelled',
        _ => 'Unknown',
      };

  static StatusTone docStatusTone(int docStatus) => switch (docStatus) {
        0 => StatusTone.draft,
        1 => StatusTone.submitted,
        2 => StatusTone.cancelled,
        _ => StatusTone.neutral,
      };

  static String _formatCurrency(double v) {
    // Lightweight formatter — doesn't depend on intl locale.
    final neg = v < 0;
    final s = v.abs().toStringAsFixed(2);
    final parts = s.split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '${neg ? '-' : ''}$intPart.${parts[1]}';
  }
}
