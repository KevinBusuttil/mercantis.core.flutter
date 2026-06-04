/// Formats raw field values into display strings for report/dashboard cells.
///
/// Mirrors the Swift `ReportValueFormatter`: a small, dependency-free layer
/// that turns typed payload values (and a few system columns) into stable
/// strings. The optional [type] hint (sourced from `ReportColumn.type`) drives
/// currency, number, and date rendering; everything else falls back to a
/// readable `toString`. Kept free of `intl` to honour the headless engine's
/// pure-Dart, no-extra-dependency contract.
class ReportValueFormatter {
  const ReportValueFormatter();

  /// Returns `null` for absent values so callers can distinguish an empty
  /// cell from the literal string "null".
  String? format(dynamic value, {String? type}) {
    if (value == null) return null;

    switch (type) {
      case 'currency':
        final n = _asNum(value);
        return n == null ? value.toString() : _fixed(n, 2);
      case 'float':
      case 'number':
      case 'decimal':
      case 'percent':
        final n = _asNum(value);
        return n == null ? value.toString() : _trimmed(n);
      case 'int':
      case 'integer':
        final n = _asNum(value);
        return n == null ? value.toString() : n.toInt().toString();
      case 'date':
        final d = _asDate(value);
        return d == null ? value.toString() : _date(d);
      case 'datetime':
      case 'dateTime':
        final d = _asDate(value);
        return d == null ? value.toString() : '${_date(d)} ${_time(d)}';
      case 'check':
      case 'boolean':
        return _asBool(value) ? 'Yes' : 'No';
    }

    if (value is bool) return value ? 'Yes' : 'No';
    return value.toString();
  }

  /// Fixed decimal places with grouped thousands, e.g. `1234.5 -> "1,234.50"`.
  String _fixed(num value, int places) {
    final negative = value < 0;
    final fixed = value.abs().toStringAsFixed(places);
    final dot = fixed.indexOf('.');
    final intPart = dot == -1 ? fixed : fixed.substring(0, dot);
    final fracPart = dot == -1 ? '' : fixed.substring(dot);
    return '${negative ? '-' : ''}${_group(intPart)}$fracPart';
  }

  /// Up to two decimals, trailing zeros trimmed, e.g. `1234.0 -> "1,234"`.
  String _trimmed(num value) {
    var s = _fixed(value, 2);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  String _group(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  num? _asNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.toLowerCase();
      return v == 'true' || v == '1' || v == 'yes';
    }
    return false;
  }

  DateTime? _asDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
