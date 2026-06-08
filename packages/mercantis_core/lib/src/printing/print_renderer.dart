import 'dart:typed_data';

import '../document_engine/document.dart';
import 'print_format.dart';

/// Inputs assembled by `PrintService` for one render call.
class PrintRenderContext {
  final PrintFormat format;
  final Document document;
  final LetterHead? letterHead;
  final DateTime now;

  PrintRenderContext({
    required this.format,
    required this.document,
    required this.letterHead,
    DateTime? now,
  }) : now = now ?? DateTime.now();
}

/// The bytes produced by a renderer plus their MIME type and a suggested file
/// name.
class PrintRenderResult {
  final Uint8List bytes;
  final String mimeType;
  final String suggestedFileName;

  const PrintRenderResult({
    required this.bytes,
    required this.mimeType,
    required this.suggestedFileName,
  });
}

/// One concrete output backend, handling a single [PrintOutputKind].
/// `PrintService` picks the right backend by kind.
abstract class PrintRenderer {
  PrintOutputKind get outputKind;
  Future<PrintRenderResult> render(PrintRenderContext context);
}

class PrintRenderException implements Exception {
  final String message;
  const PrintRenderException(this.message);

  factory PrintRenderException.backendUnavailable(String reason) =>
      PrintRenderException('Print backend unavailable: $reason');

  @override
  String toString() => 'PrintRenderException: $message';
}

/// Helpers shared by every renderer: `{field}` substitution and the default
/// formatting of a payload value to a printable string.
class PrintTemplate {
  const PrintTemplate._();

  static const Object _absent = Object();

  /// Substitute every `{key}` placeholder in [template] with the formatted
  /// document value. Unknown keys are left literal (`{key}`) so format authors
  /// can spot typos without the renderer crashing.
  static String substitute(String template, Document document) {
    final out = StringBuffer();
    var i = 0;
    final n = template.length;
    while (i < n) {
      if (template.codeUnitAt(i) == 0x7B /* { */) {
        final close = template.indexOf('}', i + 1);
        if (close != -1) {
          final key = template.substring(i + 1, close);
          if (key.isNotEmpty && !key.contains('{')) {
            final value = _lookup(key, document);
            out.write(identical(value, _absent) ? '{$key}' : format(value));
            i = close + 1;
            continue;
          }
        }
      }
      out.writeCharCode(template.codeUnitAt(i));
      i++;
    }
    return out.toString();
  }

  /// Formatted value for [key], or empty string when absent. Used by the field
  /// and table renderers (where a missing value renders blank rather than the
  /// literal placeholder).
  static String lookupString(String key, Document document) {
    final v = _lookup(key, document);
    return identical(v, _absent) ? '' : format(v);
  }

  /// Looks [key] up in the payload, then a few system-column conveniences.
  /// Returns [_absent] when not found (distinct from a present null value).
  static Object? _lookup(String key, Document document) {
    if (document.payload.containsKey(key)) return document.payload[key];
    switch (key) {
      case 'id':
        return document.id;
      case 'company':
        return document.company;
      case 'docStatus':
        return document.docStatus;
      case 'createdAt':
        return document.createdAt;
      case 'modifiedAt':
        return document.modifiedAt;
      default:
        return _absent;
    }
  }

  /// Default printable form of a payload value.
  static String format(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is bool) return value ? 'true' : 'false';
    if (value is int) return value.toString();
    if (value is double) return _formatDouble(value);
    if (value is DateTime) return _formatDateTime(value);
    if (value is List) return value.map(format).join(', ');
    return value.toString();
  }

  static String _formatDouble(double d) {
    if (d == d.roundToDouble() && d.isFinite) return d.toStringAsFixed(0);
    return d.toString();
  }

  static String _formatDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  /// Humanise a snake_case or camelCase field key into a label.
  static String defaultLabel(String key) {
    if (key.isEmpty) return key;
    final b = StringBuffer();
    for (var i = 0; i < key.length; i++) {
      final c = key.codeUnitAt(i);
      if (c == 0x5F /* _ */) {
        b.write(' ');
      } else if (c >= 65 && c <= 90 && i > 0) {
        b.write(' ');
        b.writeCharCode(c);
      } else {
        b.writeCharCode(c);
      }
    }
    final s = b.toString();
    return s.substring(0, 1).toUpperCase() + s.substring(1);
  }
}
