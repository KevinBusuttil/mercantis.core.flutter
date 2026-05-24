class CronExpression {
  final List<_CronField> _fields;

  CronExpression._(this._fields);

  factory CronExpression.parse(String expression) {
    final parts = expression.trim().split(RegExp(r'\s+'));
    if (parts.length != 5) {
      throw FormatException('Cron expression must have 5 fields: $expression');
    }
    return CronExpression._(
      parts.indexed.map((e) => _CronField.parse(e.$2, e.$1)).toList(),
    );
  }

  bool matches(DateTime dt) {
    final values = [dt.minute, dt.hour, dt.day, dt.month, dt.weekday % 7];
    for (var i = 0; i < 5; i++) {
      if (!_fields[i].matches(values[i])) return false;
    }
    return true;
  }
}

class _CronField {
  final List<_CronMatcher> _matchers;
  _CronField(this._matchers);

  factory _CronField.parse(String part, int fieldIndex) {
    final ranges = [
      (0, 59), (0, 23), (1, 31), (1, 12), (0, 6),
    ];
    final (min, max) = ranges[fieldIndex];

    if (part == '*') return _CronField([_AnyMatcher()]);

    final matchers = <_CronMatcher>[];
    for (final segment in part.split(',')) {
      if (segment.contains('/')) {
        final ps = segment.split('/');
        final step = int.parse(ps[1]);
        final start = ps[0] == '*' ? min : int.parse(ps[0]);
        matchers.add(_StepMatcher(start, max, step));
      } else if (segment.contains('-')) {
        final ps = segment.split('-');
        matchers.add(_RangeMatcher(int.parse(ps[0]), int.parse(ps[1])));
      } else {
        matchers.add(_ValueMatcher(int.parse(segment)));
      }
    }
    return _CronField(matchers);
  }

  bool matches(int value) => _matchers.any((m) => m.matches(value));
}

abstract class _CronMatcher {
  bool matches(int value);
}

class _AnyMatcher extends _CronMatcher {
  @override
  bool matches(int value) => true;
}

class _ValueMatcher extends _CronMatcher {
  final int _value;
  _ValueMatcher(this._value);
  @override
  bool matches(int value) => value == _value;
}

class _RangeMatcher extends _CronMatcher {
  final int _min, _max;
  _RangeMatcher(this._min, this._max);
  @override
  bool matches(int value) => value >= _min && value <= _max;
}

class _StepMatcher extends _CronMatcher {
  final int _start, _end, _step;
  _StepMatcher(this._start, this._end, this._step);
  @override
  bool matches(int value) {
    if (value < _start || value > _end) return false;
    return (value - _start) % _step == 0;
  }
}
