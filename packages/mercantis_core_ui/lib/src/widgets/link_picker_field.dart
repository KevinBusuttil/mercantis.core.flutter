import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';

import '../providers/core_providers.dart';
import '../shell/breakpoints.dart';
import '../views/form_field_support.dart';

/// Roles used when persisting an inline-created linked record — mirrors
/// `GenericFormView`'s save roles.
const _createRoles = <String>{'System Manager'};

/// Provider signature for link picker search results. Caller-owned
/// because Hub (and other shells) can swap in a server-backed lookup
/// without coupling Core to a specific transport. Synchronous to keep
/// the picker snappy on incremental typing — async wrappers can use a
/// debouncer.
typedef LinkSearchProvider = List<Document> Function(
  String targetDocType,
  String query,
);

/// Derives a human title for [doc] — mirrors Swift's `primaryLabel(for:)`.
/// Prefers the target DocType's first string field (via [metaDocType], when a
/// resolver supplied it), then a canonical name key, then (optionally) any
/// non-id string, and finally the raw id. Top-level so both the field's
/// selected-value display and the picker sheet's result rows share one
/// definition.
String deriveLinkLabel(Document doc, DocType? metaDocType,
    {bool allowAnyString = true}) {
  const candidateKeys = [
    'customer_name',
    'supplier_name',
    'item_name',
    'lead_name',
    'first_name',
    'name1',
    'title',
    'display_name',
    'name',
    'address_title',
    'label',
  ];
  if (metaDocType != null) {
    for (final field in metaDocType.fields) {
      if (field.type != FieldType.data &&
          field.type != FieldType.text &&
          field.type != FieldType.smallText) {
        continue;
      }
      final v = doc.payload[field.key];
      if (v is String && v.isNotEmpty && v != doc.id) return v;
    }
  }
  for (final key in candidateKeys) {
    final v = doc.payload[key];
    if (v is String && v.isNotEmpty && v != doc.id) return v;
  }
  if (allowAnyString) {
    for (final v in doc.payload.values) {
      if (v is String && v.isNotEmpty && v != doc.id) return v;
    }
  }
  return doc.id;
}

/// Compact text + button surface for `FieldType.link` values. Tapping
/// the surface opens a search sheet that mirrors the macOS rewrite from
/// Swift PR #120:
///
///   * Fixed minimum size (460 x 380 logical px) on tablet/desktop so a
///     nested sheet doesn't compress the results list to a few dozen
///     points high.
///   * Bottom sheet on phone (full width).
///   * In-sheet header with the search field — NOT in a toolbar — so
///     the input is always visible alongside results.
///   * Rows show a human title (sourced from common payload keys like
///     `customer_name`, `supplier_name`, `item_name`, `lead_name`,
///     `name1`, `title`, `display_name`) with the raw id shown as a
///     monospaced caption underneath.
///   * Empty state distinguishes "No <DocType> records yet" from "No
///     matches for '<query>'".
///   * Footer reports match count + Clear / Cancel.
class LinkPickerField extends ConsumerStatefulWidget {
  const LinkPickerField({
    super.key,
    required this.label,
    required this.targetDocType,
    required this.value,
    required this.required,
    required this.readOnly,
    required this.onChanged,
    this.searchProvider,
    this.targetDocTypeResolver,
    this.enableInlineCreate = true,
    this.dense = false,
  });

  final String label;
  final String targetDocType;
  final String? value;
  final bool required;
  final bool readOnly;
  final ValueChanged<String?> onChanged;

  /// When true (the default) the picker offers an inline "New <DocType>" action
  /// that creates the linked master record without leaving the form, then
  /// selects it — port of Swift's `LinkPickerField` inline create.
  final bool enableInlineCreate;

  /// Caller-supplied lookup. When `null` the picker falls back to
  /// `engine.list(targetDocType)` filtered client-side, which is fine
  /// for small offline collections.
  final LinkSearchProvider? searchProvider;

  /// Lets callers map a `targetDocType` id to its [DocType] so the
  /// sheet can prefer the registry's title field. Optional — falls
  /// back to a built-in key heuristic.
  final DocType? Function(String docTypeId)? targetDocTypeResolver;

  /// Compact variant for embedding in a dense surface such as a child-table
  /// cell: drops the floating label (the column header already names it) and
  /// tightens padding so it sits at cell height. The tap-to-search behaviour
  /// and title resolution are unchanged.
  final bool dense;

  @override
  ConsumerState<LinkPickerField> createState() => _LinkPickerFieldState();
}

class _LinkPickerFieldState extends ConsumerState<LinkPickerField> {
  /// Human title resolved for [LinkPickerField.value] (e.g. a Customer's name)
  /// so the field reads as a name, not the raw stored id — which for master
  /// data is an opaque UUID. Null until resolved, or when the target can't be
  /// found, in which case the id is shown as a graceful fallback.
  String? _displayTitle;
  String? _resolvedFor;
  // Whether the resolution behind [_displayTitle] had the target DocType's meta
  // available. A resolver (e.g. GenericFormView's) can populate its meta
  // asynchronously, so a title first resolved without meta is retried once meta
  // arrives — otherwise a non-standard title field would stay stuck as the id.
  bool _resolvedWithMeta = false;

  @override
  void initState() {
    super.initState();
    _resolveTitle();
  }

  @override
  void didUpdateWidget(LinkPickerField old) {
    super.didUpdateWidget(old);
    // Re-run on every update: _resolveTitle cheaply no-ops when the value is
    // already resolved with meta, but retries when a resolver has since become
    // able to name the target (or when value/targetDocType changed).
    _resolveTitle();
  }

  String? _displayTitleFor(String value) =>
      _resolvedFor == value ? _displayTitle : null;

  /// Fetches the linked record and derives its human title. Cheap (a keyed
  /// local lookup); cached against the value so rebuilds don't re-fetch.
  Future<void> _resolveTitle() async {
    final value = widget.value;
    if (value == null || value.isEmpty) {
      if (mounted && _resolvedFor != null) {
        setState(() {
          _displayTitle = null;
          _resolvedFor = null;
          _resolvedWithMeta = false;
        });
      }
      return;
    }
    final meta = widget.targetDocTypeResolver?.call(widget.targetDocType);
    final hasMeta = meta != null;
    // Already resolved this value — skip, unless the last resolution lacked the
    // target meta and it's now available (which may surface a better title).
    if (_resolvedFor == value && (_resolvedWithMeta || !hasMeta)) return;
    try {
      final engine = await ref.read(documentEngineProvider.future);
      final doc = await engine.fetch(widget.targetDocType, value);
      if (!mounted) return;
      setState(() {
        _resolvedFor = value;
        _resolvedWithMeta = hasMeta;
        // Skip the fuzzy "any string field" fallback: for a document link
        // (e.g. a Sales Invoice) the id itself is the meaningful label, so we
        // only substitute a title when the target has a real name field.
        _displayTitle =
            doc == null ? null : deriveLinkLabel(doc, meta, allowAnyString: false);
      });
    } catch (_) {
      // Leave unresolved → the raw id shows as a fallback.
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = (widget.value ?? '').isNotEmpty;
    // InkWell wraps the whole InputDecorator so the entire decorated
    // surface — label, border padding, suffix icon — counts as the tap
    // target. Nesting the InkWell inside the decorator's child made only
    // the inner Row tappable, and Row has no intrinsic height when its
    // only Expanded child is a single line of text, so taps mostly hit
    // the surrounding chrome and never reached _openPicker.
    return InkWell(
      onTap: widget.readOnly ? null : _openPicker,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: widget.dense
            ? const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.link, size: 18),
                suffixIconConstraints:
                    BoxConstraints(minWidth: 32, minHeight: 32),
              )
            : InputDecoration(
                label: _RequiredAwareLabel(
                  label: widget.label,
                  required: widget.required,
                ),
                suffixIcon: const Icon(Icons.link),
              ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                hasValue
                    ? (_displayTitleFor(widget.value!) ?? widget.value!)
                    : 'Choose ${widget.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: hasValue
                    ? null
                    : TextStyle(
                        color: Theme.of(context).hintColor,
                      ),
              ),
            ),
            if (hasValue && !widget.readOnly)
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => widget.onChanged(null),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPicker() async {
    final bp = Breakpoint.of(context);
    final picked = await (bp.isPhone
        ? showModalBottomSheet<String?>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (ctx) => _LinkPickerSheet(
              targetDocType: widget.targetDocType,
              currentValue: widget.value,
              searchProvider: widget.searchProvider,
              targetDocTypeResolver: widget.targetDocTypeResolver,
              enableInlineCreate: widget.enableInlineCreate,
            ),
          )
        : showDialog<String?>(
            context: context,
            builder: (ctx) => Dialog(
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 460,
                  minHeight: 380,
                  maxWidth: 640,
                  maxHeight: 560,
                ),
                child: _LinkPickerSheet(
                  targetDocType: widget.targetDocType,
                  currentValue: widget.value,
                  searchProvider: widget.searchProvider,
                  targetDocTypeResolver: widget.targetDocTypeResolver,
                  enableInlineCreate: widget.enableInlineCreate,
                ),
              ),
            ),
          ));
    if (!mounted) return;
    if (picked == _kClearSentinel) {
      widget.onChanged(null);
    } else if (picked != null) {
      widget.onChanged(picked);
    }
  }
}

/// Distinct from `null` (the user dismissed) so we can tell "Clear"
/// apart from "Cancel" without an extra return-type wrapper.
const _kClearSentinel = ' __cleared__';

class _LinkPickerSheet extends ConsumerStatefulWidget {
  const _LinkPickerSheet({
    required this.targetDocType,
    required this.currentValue,
    required this.searchProvider,
    required this.targetDocTypeResolver,
    required this.enableInlineCreate,
  });

  final String targetDocType;
  final String? currentValue;
  final LinkSearchProvider? searchProvider;
  final DocType? Function(String)? targetDocTypeResolver;
  final bool enableInlineCreate;

  @override
  ConsumerState<_LinkPickerSheet> createState() => _LinkPickerSheetState();
}

class _LinkPickerSheetState extends ConsumerState<_LinkPickerSheet> {
  final TextEditingController _query = TextEditingController();
  List<Document> _results = const [];
  bool _loading = true;

  /// Surfaces a thrown provider error inline above the results list.
  /// Reset alongside `_refresh` so a successful query clears the
  /// banner without an extra setState. No provider in Core currently
  /// throws — the slot is groundwork for server-backed providers.
  String? _lastSearchError;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => _refresh(_query.text));
    _refresh('');
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _refresh(String query) async {
    setState(() {
      _loading = true;
      _lastSearchError = null;
    });
    try {
      final results = await _runSearch(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _loading = false;
        _lastSearchError =
            e is DocumentEngineError ? e.humanMessage : e.toString();
      });
    }
  }

  Future<List<Document>> _runSearch(String query) async {
    final provider = widget.searchProvider;
    if (provider != null) {
      return provider(widget.targetDocType, query);
    }
    // Fallback: use the engine to list all records and filter on id /
    // string payload values. Cheap enough for the offline collections
    // Core targets out of the box.
    final engine = await ref.read(documentEngineProvider.future);
    final docs = await engine.list(widget.targetDocType);
    if (query.isEmpty) return docs;
    final q = query.toLowerCase();
    return docs.where((d) {
      if (d.id.toLowerCase().contains(q)) return true;
      for (final v in d.payload.values) {
        if (v is String && v.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }

  /// Human title for a result row — delegates to the shared [deriveLinkLabel].
  String _primaryLabel(Document doc) => deriveLinkLabel(
      doc, widget.targetDocTypeResolver?.call(widget.targetDocType));

  /// Opens the inline create sheet; on success pops the picker with the new
  /// record's id so the field selects it immediately.
  Future<void> _createNew() async {
    final newId = await showDialog<String?>(
      context: context,
      builder: (_) => _InlineCreateSheet(
        targetDocType: widget.targetDocType,
        targetDocTypeResolver: widget.targetDocTypeResolver,
        searchProvider: widget.searchProvider,
      ),
    );
    if (!mounted || newId == null || newId.isEmpty) return;
    Navigator.of(context).pop(newId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onCreate = widget.enableInlineCreate ? _createNew : null;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(
            targetDocType: widget.targetDocType,
            controller: _query,
          ),
          const Divider(height: 1),
          if (_lastSearchError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: theme.colorScheme.errorContainer,
              child: Text(
                _lastSearchError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          Flexible(
            child: _ResultsBody(
              loading: _loading,
              results: _results,
              query: _query.text,
              targetDocType: widget.targetDocType,
              primaryLabelOf: _primaryLabel,
              onPick: (doc) => Navigator.of(context).pop(doc.id),
              onCreate: onCreate,
            ),
          ),
          const Divider(height: 1),
          _Footer(
            matchCount: _results.length,
            hasValue: (widget.currentValue ?? '').isNotEmpty,
            onClear: () => Navigator.of(context).pop(_kClearSentinel),
            onCancel: () => Navigator.of(context).pop(),
            onCreate: onCreate,
            targetDocType: widget.targetDocType,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.targetDocType, required this.controller});
  final String targetDocType;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Select $targetDocType',
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search $targetDocType',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => controller.clear(),
                      ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsBody extends StatelessWidget {
  const _ResultsBody({
    required this.loading,
    required this.results,
    required this.query,
    required this.targetDocType,
    required this.primaryLabelOf,
    required this.onPick,
    this.onCreate,
  });
  final bool loading;
  final List<Document> results;
  final String query;
  final String targetDocType;
  final String Function(Document) primaryLabelOf;
  final ValueChanged<Document> onPick;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    if (loading && results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (results.isEmpty) {
      return _EmptyState(
          query: query, targetDocType: targetDocType, onCreate: onCreate);
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
      itemBuilder: (context, i) {
        final doc = results[i];
        return ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(primaryLabelOf(doc), maxLines: 1),
          subtitle: Text(
            doc.id,
            style: TextStyle(
              fontFamily: 'monospace',
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => onPick(doc),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(
      {required this.query, required this.targetDocType, this.onCreate});
  final String query;
  final String targetDocType;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasQuery = query.isNotEmpty;
    final title =
        hasQuery ? 'No matches for "$query"' : 'No $targetDocType records yet';
    final body = hasQuery
        ? 'Try a different search.'
        : onCreate != null
            ? 'Create the first $targetDocType to link to it.'
            : 'Create a $targetDocType first, then link to it from here.';
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasQuery ? Icons.search_off : Icons.inbox_outlined,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 8),
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onCreate != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: Text('New $targetDocType'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.matchCount,
    required this.hasValue,
    required this.onClear,
    required this.onCancel,
    required this.targetDocType,
    this.onCreate,
  });
  final int matchCount;
  final bool hasValue;
  final VoidCallback onClear;
  final VoidCallback onCancel;
  final String targetDocType;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (onCreate != null)
            TextButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 18),
              label: Text('New $targetDocType'),
            ),
          const SizedBox(width: 8),
          Text(
            matchCount == 0
                ? ''
                : '$matchCount ${matchCount == 1 ? 'match' : 'matches'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          if (hasValue)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: onClear,
              child: const Text('Clear selection'),
            ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

/// A compact "create a new linked record" form shown from within the picker.
/// Renders the target DocType's editable fields, persists the draft via the
/// document engine, and returns the saved record's id (which becomes the link
/// value). Port of Swift `LinkPickerField`'s inline create form.
class _InlineCreateSheet extends ConsumerStatefulWidget {
  const _InlineCreateSheet({
    required this.targetDocType,
    this.targetDocTypeResolver,
    this.searchProvider,
  });

  final String targetDocType;
  final DocType? Function(String)? targetDocTypeResolver;
  final LinkSearchProvider? searchProvider;

  @override
  ConsumerState<_InlineCreateSheet> createState() => _InlineCreateSheetState();
}

class _InlineCreateSheetState extends ConsumerState<_InlineCreateSheet> {
  final Map<String, dynamic> _values = {};
  Map<String, String> _errors = {};
  bool _saving = false;
  String? _saveError;

  bool _isEditable(ResolvedFieldDefinition f) {
    switch (f.type) {
      case FieldType.heading:
      case FieldType.sectionBreak:
      case FieldType.columnBreak:
      case FieldType.formula:
      case FieldType.table:
      case FieldType.tableMultiSelect:
        return false;
      default:
        return !f.readOnly;
    }
  }

  Future<void> _create(ResolvedMeta meta) async {
    final errs = <String, String>{};
    for (final f in meta.visibleFields) {
      if (!_isEditable(f)) continue;
      final e = localFieldValidationError(f, _values[f.key], isReadOnly: false);
      if (e != null) errs[f.key] = e;
    }
    if (errs.isNotEmpty) {
      setState(() => _errors = errs);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final engine = await ref.read(documentEngineProvider.future);
      final doc = Document(
        id: '',
        docType: widget.targetDocType,
        payload: Map<String, dynamic>.from(_values),
      );
      final saved = await engine.save(doc, _createRoles);
      if (!mounted) return;
      Navigator.of(context).pop(saved.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError =
            e is DocumentEngineError ? e.humanMessage : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final metaAsync = ref.watch(resolvedMetaProvider(widget.targetDocType));
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: metaAsync.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) =>
              Padding(padding: const EdgeInsets.all(24), child: Text('Error: $e')),
          data: (meta) => meta == null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                      "Can't create ${widget.targetDocType} — its definition is unavailable."))
              : _form(context, meta),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, ResolvedMeta meta) {
    final theme = Theme.of(context);
    final fields = meta.visibleFields.where(_isEditable).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Text('New ${widget.targetDocType}',
              style: theme.textTheme.titleMedium),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _editor(context, f),
                  ),
                if (_saveError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_saveError!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error)),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Spacer(),
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : () => _create(meta),
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Create ${widget.targetDocType}'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _editor(BuildContext context, ResolvedFieldDefinition f) {
    void set(dynamic v) => setState(() {
          _values[f.key] = v;
          _errors.remove(f.key);
        });
    final decoration = InputDecoration(
      label: _RequiredAwareLabel(label: f.label, required: f.required),
      hintText: f.placeholder,
      errorText: _errors[f.key],
    );

    switch (f.type) {
      case FieldType.check:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: _RequiredAwareLabel(label: f.label, required: f.required),
          value: (_values[f.key] as int? ?? 0) == 1,
          onChanged: (v) => set(v ? 1 : 0),
        );
      case FieldType.integer:
        return TextFormField(
          decoration: decoration,
          keyboardType: TextInputType.number,
          onChanged: (v) => set(int.tryParse(v)),
        );
      case FieldType.float:
      case FieldType.currency:
      case FieldType.percent:
        return TextFormField(
          decoration: decoration,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => set(double.tryParse(v)),
        );
      case FieldType.select:
        final opts =
            (f.options ?? '').split('\n').where((o) => o.isNotEmpty).toList();
        return DropdownButtonFormField<String>(
          initialValue: _values[f.key] as String?,
          decoration: decoration,
          items: [
            for (final o in opts) DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: (v) => set(v),
        );
      case FieldType.link:
      case FieldType.dynamicLink:
        return LinkPickerField(
          label: f.label,
          targetDocType: f.linkDocType ?? f.options ?? '',
          value: _values[f.key] as String?,
          required: f.required,
          readOnly: false,
          searchProvider: widget.searchProvider,
          targetDocTypeResolver: widget.targetDocTypeResolver,
          onChanged: set,
        );
      case FieldType.date:
        final current = _values[f.key] as String?;
        return InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.tryParse(current ?? '') ?? DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              set('${picked.year.toString().padLeft(4, '0')}-'
                  '${picked.month.toString().padLeft(2, '0')}-'
                  '${picked.day.toString().padLeft(2, '0')}');
            }
          },
          child: InputDecorator(
            decoration:
                decoration.copyWith(suffixIcon: const Icon(Icons.calendar_today, size: 18)),
            child: Text(
              current ?? '',
              style: current == null
                  ? TextStyle(color: Theme.of(context).hintColor)
                  : null,
            ),
          ),
        );
      default:
        return TextFormField(decoration: decoration, onChanged: set);
    }
  }
}

/// Local copy of the required-label widget kept private to this file
/// so the picker doesn't depend on `generic_form_view.dart` internals.
class _RequiredAwareLabel extends StatelessWidget {
  const _RequiredAwareLabel({required this.label, required this.required});
  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final asterisk = base.copyWith(
      color: Theme.of(context).colorScheme.error,
      fontWeight: FontWeight.w600,
    );
    return Semantics(
      label: required ? '$label, required' : label,
      excludeSemantics: true,
      child: RichText(
        text: TextSpan(
          style: base,
          children: [
            TextSpan(text: label),
            if (required) TextSpan(text: ' *', style: asterisk),
          ],
        ),
      ),
    );
  }
}
