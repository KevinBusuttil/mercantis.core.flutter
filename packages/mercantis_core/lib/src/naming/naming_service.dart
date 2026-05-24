import '../metadata/doc_type.dart';
import '../document_engine/document.dart';
import 'naming_strategy.dart';

class NamingService {
  final Map<String, NamingStrategy> _strategies = {};
  final NamingStrategy _defaultStrategy;

  NamingService({NamingStrategy? defaultStrategy})
      : _defaultStrategy = defaultStrategy ?? const UuidV4Strategy();

  void registerStrategy(String key, NamingStrategy strategy) {
    _strategies[key] = strategy;
  }

  Future<String> resolve(
      DocType docType, Document document, NamingContext context) async {
    final rule = docType.namingRule;
    if (rule == null || rule.isEmpty) {
      return _defaultStrategy.resolve(docType, document, context);
    }

    // Check if it's a registered strategy key
    if (_strategies.containsKey(rule)) {
      return _strategies[rule]!.resolve(docType, document, context);
    }

    // Auto-detect strategy from rule format
    if (rule.startsWith('field:')) {
      final fieldKey = rule.substring(6);
      return FieldDerivedStrategy(fieldKey).resolve(docType, document, context);
    }
    if (rule.startsWith('format:')) {
      final template = rule.substring(7);
      return FormatStrategy(template).resolve(docType, document, context);
    }
    // Treat as naming series pattern (contains .####)
    if (rule.contains('#')) {
      return NamingSeriesStrategy(rule).resolve(docType, document, context);
    }

    return _defaultStrategy.resolve(docType, document, context);
  }
}
