/// A conditional naming series (ADR-040).
///
/// When [condition] — a boolean expression over the document's fields, or
/// null/empty meaning "always" — matches, the document is named using
/// [series], a rule string in the same forms `DocType.namingRule` accepts
/// (naming series like `SINV-.YYYY.-.####`, `format:{abbr}-{n}`, `field:code`).
/// Rules are evaluated in order; the first match wins, otherwise the engine
/// falls back to `DocType.namingRule`. This lets one DocType vary its series
/// per company, per fiscal year, or by any field-driven condition.
class DocumentNamingRule {
  final String? condition;
  final String series;

  const DocumentNamingRule({this.condition, required this.series});

  factory DocumentNamingRule.fromJson(Map<String, dynamic> json) =>
      DocumentNamingRule(
        condition: json['condition'] as String?,
        series: json['series'] as String,
      );

  Map<String, dynamic> toJson() => {
        if (condition != null) 'condition': condition,
        'series': series,
      };
}
