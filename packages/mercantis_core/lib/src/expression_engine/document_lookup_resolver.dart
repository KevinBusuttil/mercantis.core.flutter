abstract class DocumentLookupResolver {
  Future<dynamic> lookup(String docType, String name, String field);
}

class CachingDocumentLookupResolver implements DocumentLookupResolver {
  final DocumentLookupResolver _inner;
  final Map<String, dynamic> _cache = {};

  CachingDocumentLookupResolver(this._inner);

  @override
  Future<dynamic> lookup(String docType, String name, String field) async {
    final key = '$docType:$name:$field';
    if (_cache.containsKey(key)) return _cache[key];
    final value = await _inner.lookup(docType, name, field);
    _cache[key] = value;
    return value;
  }

  void invalidate() => _cache.clear();
}
