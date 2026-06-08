/// Comparison operators for a [ListFilter] pushed down to SQL by
/// `DocumentEngine.list` (ADR-036).
enum FilterOp {
  eq,
  ne,
  gt,
  gte,
  lt,
  lte,
  isIn,
  notIn,
  like,
  notLike,
  between,
  isNull,
  isNotNull,
}

/// A typed list predicate compiled to a `json_extract(payload, '$.field') <op>`
/// SQL fragment, so filtering happens in SQLite rather than in Dart after a
/// full table scan. Use over the plain equality `filters` map when you need
/// ranges, membership, pattern, or null checks.
///
/// `value` shape by operator:
/// * scalar — eq, ne, gt, gte, lt, lte, like, notLike
/// * `List` — isIn, notIn
/// * `[lo, hi]` — between
/// * ignored — isNull, isNotNull
class ListFilter {
  final String field;
  final FilterOp op;
  final Object? value;

  const ListFilter(this.field, this.op, [this.value]);

  const ListFilter.eq(this.field, this.value) : op = FilterOp.eq;
  const ListFilter.ne(this.field, this.value) : op = FilterOp.ne;
  const ListFilter.gt(this.field, this.value) : op = FilterOp.gt;
  const ListFilter.gte(this.field, this.value) : op = FilterOp.gte;
  const ListFilter.lt(this.field, this.value) : op = FilterOp.lt;
  const ListFilter.lte(this.field, this.value) : op = FilterOp.lte;
  const ListFilter.isIn(this.field, List<Object?> values)
      : op = FilterOp.isIn,
        value = values;
  const ListFilter.notIn(this.field, List<Object?> values)
      : op = FilterOp.notIn,
        value = values;
  const ListFilter.like(this.field, String pattern)
      : op = FilterOp.like,
        value = pattern;
  const ListFilter.notLike(this.field, String pattern)
      : op = FilterOp.notLike,
        value = pattern;
  // Not const: builds a list from runtime args.
  ListFilter.between(this.field, Object low, Object high)
      : op = FilterOp.between,
        value = [low, high];
  const ListFilter.isNull(this.field)
      : op = FilterOp.isNull,
        value = null;
  const ListFilter.isNotNull(this.field)
      : op = FilterOp.isNotNull,
        value = null;

  /// Compiles to a `(clause, args)` pair ready to append to a parameterised
  /// query. The column reference is `json_extract(payload, '$.<field>')`.
  (String, List<Object?>) toSql() {
    final col = "json_extract(payload, '\$.$field')";
    switch (op) {
      case FilterOp.eq:
        return ('$col = ?', [value]);
      case FilterOp.ne:
        return ('$col <> ?', [value]);
      case FilterOp.gt:
        return ('$col > ?', [value]);
      case FilterOp.gte:
        return ('$col >= ?', [value]);
      case FilterOp.lt:
        return ('$col < ?', [value]);
      case FilterOp.lte:
        return ('$col <= ?', [value]);
      case FilterOp.like:
        return ('$col LIKE ?', [value]);
      case FilterOp.notLike:
        return ('$col NOT LIKE ?', [value]);
      case FilterOp.isNull:
        return ('$col IS NULL', const []);
      case FilterOp.isNotNull:
        return ('$col IS NOT NULL', const []);
      case FilterOp.between:
        final v = (value as List).cast<Object?>();
        return ('$col BETWEEN ? AND ?', [v[0], v[1]]);
      case FilterOp.isIn:
      case FilterOp.notIn:
        final values = (value as List).cast<Object?>();
        final negate = op == FilterOp.notIn;
        if (values.isEmpty) {
          // IN () is invalid SQL: an empty set matches nothing (and its
          // negation matches everything).
          return (negate ? '1 = 1' : '1 = 0', const []);
        }
        final placeholders = List.filled(values.length, '?').join(', ');
        return ('$col ${negate ? 'NOT IN' : 'IN'} ($placeholders)', values);
    }
  }
}
