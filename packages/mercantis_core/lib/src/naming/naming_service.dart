import '../metadata/doc_type.dart';
import '../document_engine/document.dart';
import '../expression_engine/expression_evaluator.dart';
import 'naming_strategy.dart';

class NamingService {
  final Map<String, NamingStrategy> _strategies = {};
  final NamingStrategy _defaultStrategy;
  final ExpressionEvaluator _evaluator;

  NamingService({NamingStrategy? defaultStrategy, ExpressionEvaluator? evaluator})
      : _defaultStrategy = defaultStrategy ?? const UuidV4Strategy(),
        _evaluator = evaluator ?? ExpressionEvaluator();

  void registerStrategy(String key, NamingStrategy strategy) {
    _strategies[key] = strategy;
  }

  Future<String> resolve(
      DocType docType, Document document, NamingContext context) async {
    // Conditional per-company / per-fiscal-year rules (ADR-040) take
    // precedence: the first whose condition matches wins.
    for (final r in docType.namingRules) {
      if (_conditionMatches(r.condition, document, context)) {
        return _resolveRule(r.series, docType, document, context);
      }
    }

    final rule = docType.namingRule;
    if (rule == null || rule.isEmpty) {
      return _defaultStrategy.resolve(docType, document, context);
    }
    return _resolveRule(rule, docType, document, context);
  }

  bool _conditionMatches(
      String? condition, Document document, NamingContext context) {
    if (condition == null || condition.isEmpty) return true;
    try {
      return _evaluator.evaluateBool(
        condition,
        EvaluationContext(
          fields: document.payload,
          user: {'id': context.userId, 'company': context.companyAbbr},
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Resolves a single rule string: a registered strategy key, `field:<key>`,
  /// `format:<template>`, a naming-series pattern (contains `#`), or the
  /// default strategy.
  Future<String> _resolveRule(
      String rule, DocType docType, Document document, NamingContext context) {
    if (_strategies.containsKey(rule)) {
      return _strategies[rule]!.resolve(docType, document, context);
    }
    if (rule.startsWith('field:')) {
      return FieldDerivedStrategy(rule.substring(6))
          .resolve(docType, document, context);
    }
    if (rule.startsWith('format:')) {
      return FormatStrategy(rule.substring(7))
          .resolve(docType, document, context);
    }
    if (rule.contains('#')) {
      return NamingSeriesStrategy(rule).resolve(docType, document, context);
    }
    return _defaultStrategy.resolve(docType, document, context);
  }
}
