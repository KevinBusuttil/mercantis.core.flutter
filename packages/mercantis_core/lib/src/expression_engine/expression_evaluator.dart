import 'expression_ast.dart';
import 'expression_parser.dart';

class EvaluationContext {
  final Map<String, dynamic> fields;
  final Map<String, dynamic> user;

  const EvaluationContext({required this.fields, this.user = const {}});
}

class EvaluationError implements Exception {
  final String message;
  const EvaluationError(this.message);
  @override
  String toString() => 'EvaluationError: $message';
}

typedef DocumentLookupFn = Future<dynamic> Function(
    String docType, String name, String field);

class ExpressionEvaluator {
  final _parseCache = <String, ExpressionNode>{};
  static const _maxCacheSize = 256;

  ExpressionNode parse(String source) {
    if (_parseCache.containsKey(source)) return _parseCache[source]!;
    final node = ExpressionParser.fromSource(source).parse();
    if (_parseCache.length >= _maxCacheSize) {
      _parseCache.remove(_parseCache.keys.first);
    }
    _parseCache[source] = node;
    return node;
  }

  bool evaluateBool(String expression, EvaluationContext context) {
    if (expression.trim().isEmpty) return true;
    final node = parse(expression);
    final result = _evaluate(node, context);
    if (result is bool) return result;
    if (result == null) return false;
    if (result is num) return result != 0;
    if (result is String) return result.isNotEmpty;
    return true;
  }

  dynamic evaluateValue(String expression, EvaluationContext context) {
    if (expression.trim().isEmpty) return null;
    final node = parse(expression);
    return _evaluate(node, context);
  }

  bool evaluateBoolParsed(ExpressionNode node, EvaluationContext context) {
    final result = _evaluate(node, context);
    if (result is bool) return result;
    if (result == null) return false;
    if (result is num) return result != 0;
    return true;
  }

  dynamic evaluateValueParsed(ExpressionNode node, EvaluationContext context) {
    return _evaluate(node, context);
  }

  Set<String> referencedFields(String expression) {
    try {
      final node = parse(expression);
      return ExpressionParser.referencedFields(node);
    } catch (_) {
      return {};
    }
  }

  dynamic _evaluate(ExpressionNode node, EvaluationContext ctx) {
    return switch (node) {
      LiteralNode(value: final v) => v,
      IdentifierNode(name: final name) => _resolveIdentifier(name, ctx),
      UnaryNode(operator_: final op, operand: final operand) =>
        _evaluateUnary(op, _evaluate(operand, ctx)),
      BinaryNode(operator_: final op, left: final l, right: final r) =>
        _evaluateBinary(op, _evaluate(l, ctx), _evaluate(r, ctx)),
      CallNode(name: final name, arguments: final args) =>
        _evaluateCall(name, args, ctx),
      MemberNode(object: final obj, member: final member) =>
        _resolveMember(_evaluate(obj, ctx), member),
    };
  }

  dynamic _resolveIdentifier(String name, EvaluationContext ctx) {
    // Handle dot-notation (e.g., user.id)
    if (name.contains('.')) {
      final parts = name.split('.');
      if (parts.first == 'user') {
        final key = parts.skip(1).join('.');
        return ctx.user[key];
      }
      // Try to resolve as nested field
      dynamic current = ctx.fields;
      for (final part in parts) {
        if (current is Map) {
          current = current[part];
        } else {
          return null;
        }
      }
      return current;
    }
    return ctx.fields[name];
  }

  dynamic _resolveMember(dynamic object, String member) {
    if (object is Map) return object[member];
    return null;
  }

  dynamic _evaluateUnary(TokenType op, dynamic value) {
    return switch (op) {
      TokenType.not_ => !(value as bool? ?? false),
      TokenType.minus => switch (value) {
          int v => -v,
          double v => -v,
          _ => throw EvaluationError('Cannot negate non-numeric value: $value'),
        },
      _ => throw EvaluationError('Unknown unary operator: $op'),
    };
  }

  dynamic _evaluateBinary(TokenType op, dynamic left, dynamic right) {
    switch (op) {
      case TokenType.and_:
        return _isTruthy(left) && _isTruthy(right);
      case TokenType.or_:
        return _isTruthy(left) || _isTruthy(right);
      case TokenType.eq:
        return _equals(left, right);
      case TokenType.neq:
        return !_equals(left, right);
      case TokenType.lt:
        return _compare(left, right) < 0;
      case TokenType.lte:
        return _compare(left, right) <= 0;
      case TokenType.gt:
        return _compare(left, right) > 0;
      case TokenType.gte:
        return _compare(left, right) >= 0;
      case TokenType.plus:
        if (left is String || right is String) {
          return '${left ?? ''}${right ?? ''}';
        }
        return _toNum(left) + _toNum(right);
      case TokenType.minus:
        return _toNum(left) - _toNum(right);
      case TokenType.star:
        return _toNum(left) * _toNum(right);
      case TokenType.slash:
        final d = _toNum(right);
        if (d == 0) throw const EvaluationError('Division by zero');
        return _toNum(left) / d;
      case TokenType.percent_:
        final d = _toNum(right);
        if (d == 0) throw const EvaluationError('Modulo by zero');
        return _toNum(left) % d;
      default:
        throw EvaluationError('Unknown binary operator: $op');
    }
  }

  dynamic _evaluateCall(
      String name, List<ExpressionNode> argNodes, EvaluationContext ctx) {
    final args = argNodes.map((a) => _evaluate(a, ctx)).toList();
    switch (name) {
      case 'len':
      case 'length':
        final arg = args.first;
        if (arg == null) return 0;
        if (arg is String) return arg.length;
        if (arg is List) return arg.length;
        if (arg is Map) return arg.length;
        return 0;
      case 'contains':
        if (args.length < 2) return false;
        final container = args[0];
        final item = args[1];
        if (container is String && item is String) {
          return container.contains(item);
        }
        if (container is List) return container.contains(item);
        return false;
      case 'startswith':
      case 'startsWith':
        if (args.length < 2 || args[0] == null) return false;
        return args[0].toString().startsWith(args[1]?.toString() ?? '');
      case 'endswith':
      case 'endsWith':
        if (args.length < 2 || args[0] == null) return false;
        return args[0].toString().endsWith(args[1]?.toString() ?? '');
      case 'upper':
      case 'toUpperCase':
        return args.first?.toString().toUpperCase();
      case 'lower':
      case 'toLowerCase':
        return args.first?.toString().toLowerCase();
      case 'str':
      case 'toString':
        return args.first?.toString() ?? '';
      case 'int':
      case 'toInt':
        return _toNum(args.first).toInt();
      case 'float':
      case 'toDouble':
        return _toNum(args.first).toDouble();
      case 'now':
        return DateTime.now().toIso8601String();
      case 'today':
        final now = DateTime.now();
        return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      default:
        return null;
    }
  }

  bool _isTruthy(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.isNotEmpty;
    return true;
  }

  bool _equals(dynamic a, dynamic b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a is num && b is num) return a == b;
    if (a is String && b is String) return a == b;
    if (a is bool && b is bool) return a == b;
    return a.toString() == b.toString();
  }

  int _compare(dynamic a, dynamic b) {
    if (a is num && b is num) return a.compareTo(b);
    if (a is String && b is String) return a.compareTo(b);
    if (a is DateTime && b is DateTime) return a.compareTo(b);
    return a.toString().compareTo(b.toString());
  }

  num _toNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    if (v is bool) return v ? 1 : 0;
    return 0;
  }
}
