class IndexDefinition {
  final String fieldKey;
  final bool isUnique;

  const IndexDefinition({required this.fieldKey, this.isUnique = false});

  factory IndexDefinition.fromJson(Map<String, dynamic> json) =>
      IndexDefinition(
        fieldKey: json['fieldKey'] as String,
        isUnique: (json['isUnique'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'fieldKey': fieldKey,
        'isUnique': isUnique,
      };
}
