import '../workspace/workspace_descriptor.dart';

/// Query values arrive as text; numeric filters (e.g. a `billable` check
/// stored as 1) must compare as numbers in the store's JSON predicate.
Object listFilterValue(String raw) => num.tryParse(raw) ?? raw;

/// The canonical location of a record list, carrying a workspace item's
/// relabel and pre-filter so a "Customer payments" entry opens the receive-only
/// payments — not every Payment Entry under the engine's name.
String listLocation(String docType,
    {String? title, Map<String, dynamic>? filter}) {
  final params = <String, String>{
    if (title != null) 'title': title,
    if (filter != null)
      for (final e in filter.entries) 'f.${e.key}': '${e.value}',
  };
  final base = '/list/$docType';
  if (params.isEmpty) return base;
  // Keep the path readable (`/list/Payment Entry`, as elsewhere); only the
  // query is encoded.
  return '$base?${Uri(queryParameters: params).query}';
}

/// [listLocation] for a [DocTypeWorkspaceItem] — its label (when it renames
/// the DocType) and its list filter travel with the link.
String docTypeItemLocation(DocTypeWorkspaceItem item) => listLocation(
      item.docType,
      title: item.label,
      filter: item.listFilter,
    );
