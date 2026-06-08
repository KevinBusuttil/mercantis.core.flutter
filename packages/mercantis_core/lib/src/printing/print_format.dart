/// Declarative print formats and letter heads (ADR-044). Manifests declare a
/// [PrintFormat] per (DocType, format-id) pair; the print subsystem renders one
/// to bytes (plain text or PDF) for any document of that DocType.

/// Output format requested from `PrintService.render(...)`.
enum PrintOutputKind { plainText, pdf }

/// Reusable header/footer chrome attached to print formats. Stored once per app
/// and referenced by [PrintFormat.letterHeadId].
class LetterHead {
  final String id;
  final String name;

  /// Plain text rendered above the document body. Supports `{field}`
  /// substitution from the document.
  final String header;

  /// Optional plain-text footer rendered below the document body.
  final String? footer;

  const LetterHead({
    required this.id,
    required this.name,
    required this.header,
    this.footer,
  });

  factory LetterHead.fromJson(Map<String, dynamic> json) => LetterHead(
        id: json['id'] as String,
        name: json['name'] as String,
        header: json['header'] as String? ?? '',
        footer: json['footer'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'header': header,
        if (footer != null) 'footer': footer,
      };
}

/// One renderable unit inside a [PrintFormat]. Sealed so renderers can switch
/// exhaustively without re-parsing markup.
sealed class PrintSection {
  const PrintSection();

  factory PrintSection.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String?;
    switch (kind) {
      case 'heading':
        return HeadingSection(json['text'] as String? ?? '');
      case 'paragraph':
        return ParagraphSection(json['text'] as String? ?? '');
      case 'fields':
        return FieldsSection(
          keys: (json['keys'] as List<dynamic>?)?.cast<String>() ?? const [],
          labels: _stringMap(json['labels']),
        );
      case 'table':
        return TableSection(
          tableKey: json['tableKey'] as String? ?? '',
          columns:
              (json['columns'] as List<dynamic>?)?.cast<String>() ?? const [],
          labels: _stringMap(json['labels']),
        );
      case 'keyValue':
        return KeyValueSection(
          label: json['label'] as String? ?? '',
          value: json['value'] as String? ?? '',
        );
      default:
        throw ArgumentError.value(kind, 'kind', 'Unknown print section kind');
    }
  }

  Map<String, dynamic> toJson();

  static Map<String, String> _stringMap(dynamic raw) {
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }
}

/// Top-level heading. [text] supports `{field}` substitution.
class HeadingSection extends PrintSection {
  final String text;
  const HeadingSection(this.text);

  @override
  Map<String, dynamic> toJson() => {'kind': 'heading', 'text': text};
}

/// A paragraph of body text. Supports `{field}` substitution.
class ParagraphSection extends PrintSection {
  final String text;
  const ParagraphSection(this.text);

  @override
  Map<String, dynamic> toJson() => {'kind': 'paragraph', 'text': text};
}

/// Two-column "label / value" grid over a fixed list of field keys.
/// [labels] overrides the default humanised label per key.
class FieldsSection extends PrintSection {
  final List<String> keys;
  final Map<String, String> labels;
  const FieldsSection({required this.keys, this.labels = const {}});

  @override
  Map<String, dynamic> toJson() =>
      {'kind': 'fields', 'keys': keys, 'labels': labels};
}

/// A grid for one of the document's child tables. [tableKey] is the
/// `Document.children` map key; [columns] are the child row field keys to
/// render in order. Empty [columns] falls back to "every key seen in the rows".
class TableSection extends PrintSection {
  final String tableKey;
  final List<String> columns;
  final Map<String, String> labels;
  const TableSection(
      {required this.tableKey, this.columns = const [], this.labels = const {}});

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'table',
        'tableKey': tableKey,
        'columns': columns,
        'labels': labels,
      };
}

/// Free-form key-value line, e.g. totals: "Subtotal: 150.00". Both [label] and
/// [value] support `{field}` substitution.
class KeyValueSection extends PrintSection {
  final String label;
  final String value;
  const KeyValueSection({required this.label, required this.value});

  @override
  Map<String, dynamic> toJson() =>
      {'kind': 'keyValue', 'label': label, 'value': value};
}

/// Declarative print format for one DocType. Sections render in order.
class PrintFormat {
  final String id;
  final String name;
  final String docType;
  final String? letterHeadId;
  final List<PrintSection> sections;

  const PrintFormat({
    required this.id,
    required this.name,
    required this.docType,
    this.letterHeadId,
    this.sections = const [],
  });

  factory PrintFormat.fromJson(Map<String, dynamic> json) => PrintFormat(
        id: json['id'] as String,
        name: json['name'] as String,
        docType: json['docType'] as String,
        letterHeadId: json['letterHeadId'] as String?,
        sections: (json['sections'] as List<dynamic>?)
                ?.map((s) =>
                    PrintSection.fromJson(Map<String, dynamic>.from(s as Map)))
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'docType': docType,
        if (letterHeadId != null) 'letterHeadId': letterHeadId,
        'sections': sections.map((s) => s.toJson()).toList(),
      };
}
