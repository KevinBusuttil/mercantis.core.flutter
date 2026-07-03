import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mercantis_core/mercantis_core.dart';
import '../metadata/metadata_display.dart';
import '../providers/core_providers.dart';
import '../providers/recents_providers.dart';
import '../shell/recents_store.dart';
import '../theme/atlas/atlas.dart';
import '../widgets/child_table_field.dart';
import '../widgets/fields/attachment_field.dart';
import '../widgets/fields/barcode_field.dart';
import '../widgets/fields/color_field.dart';
import '../widgets/fields/geolocation_field.dart';
import '../widgets/fields/scalar_field_widgets.dart';
import '../widgets/fields/signature_field.dart';
import '../widgets/link_picker_field.dart';
import '../widgets/workflow_action_button.dart';
import 'document_action.dart';
import 'form_field_support.dart';
import 'record_workspace_chrome.dart';

const _userRoles = <String>{'System Manager'};

/// Reads a document's child rows for [fieldKey] as the plain map list the
/// child-table grid edits. Child rows live in [Document.children] (the
/// `document_children` table), not the parent payload — so the form must source
/// them here, never from `doc[fieldKey]`.
List<Map<String, dynamic>> childRowsAsMaps(Document doc, String fieldKey) {
  final rows = doc.children[fieldKey];
  if (rows == null) return const [];
  return [for (final r in rows) Map<String, dynamic>.from(r.payload)];
}

/// Returns a copy of [base] with [childChanges] applied to [Document.children]
/// — each entry is a full replacement row list for that field key, rebuilt as
/// [ChildRow]s (with parent linkage + row index). Edits go to `children`, never
/// payload, so they persist to `document_children` and flow into derivation.
Document applyChildChanges(
    Document base, Map<String, List<Map<String, dynamic>>> childChanges) {
  if (childChanges.isEmpty) return base;
  final children = Map<String, List<ChildRow>>.from(base.children);
  childChanges.forEach((key, rows) {
    children[key] = [
      for (var i = 0; i < rows.length; i++)
        ChildRow(
          id: '',
          parentId: base.id,
          parentDocType: base.docType,
          tableName: key,
          rowIndex: i,
          payload: Map<String, dynamic>.from(rows[i]),
        ),
    ];
  });
  return base.copyWith(children: children);
}

/// Matches an engine `fieldKey` that points into a child table —
/// `items[2]` (a whole row) or `items[2].rate` (a row's field).
final RegExp _childErrorKeyPattern =
    RegExp(r'^([A-Za-z0-9_]+)\[(\d+)\](?:\.(.+))?$');

/// The engine prefixes each child-row message with "Row N:"; stripped when
/// distributing since the row index is already the map key.
final RegExp _rowPrefixPattern = RegExp(r'^Row \d+:\s*');

/// Partitions engine [ValidationError]s into parent-field messages (keyed by
/// field key) and child-table messages (table key → row index → child field
/// key → message; a whole-row error uses the empty-string key). Pure and
/// exported so the fieldKey-routing — the tricky part of Phase 3c — is
/// unit-tested without standing up the whole form.
({
  Map<String, String> parent,
  Map<String, Map<int, Map<String, String>>> child,
}) partitionValidationErrors(List<ValidationError> errors) {
  final parent = <String, String>{};
  final child = <String, Map<int, Map<String, String>>>{};
  for (final e in errors) {
    final key = e.fieldKey;
    if (key == null) continue;
    final match = _childErrorKeyPattern.firstMatch(key);
    if (match == null) {
      parent[key] = e.message;
      continue;
    }
    final tableKey = match.group(1)!;
    final rowIndex = int.parse(match.group(2)!);
    final childField = match.group(3) ?? '';
    final message = e.message.replaceFirst(_rowPrefixPattern, '');
    (child[tableKey] ??= {})
        .putIfAbsent(rowIndex, () => <String, String>{})[childField] = message;
  }
  return (parent: parent, child: child);
}

final _fetchDocProvider =
    FutureProvider.family<Document?, (String, String?)>((ref, args) async {
  final (docTypeName, name) = args;
  if (name == null) return null;
  final engine = await ref.watch(documentEngineProvider.future);
  return engine.fetch(docTypeName, name);
});

/// Prefetches every child-table and link [DocType] referenced by a
/// parent form so the synchronous resolver wired into [GenericFormView]
/// can answer without rebuilding through Riverpod. Without this map the
/// child-table widget falls back to the "Wire childDocTypeProvider…"
/// warning and the link picker can't read the target's title field
/// (forcing it onto a key-name heuristic). Returns an empty map when
/// meta is missing.
final _referencedDocTypesProvider =
    FutureProvider.family<Map<String, DocType>, String>(
        (ref, docTypeName) async {
  final meta = await ref.watch(resolvedMetaProvider(docTypeName).future);
  if (meta == null) return const {};
  final registry = await ref.watch(metadataRegistryProvider.future);
  final ids = <String>{};
  for (final f in meta.fields) {
    final t = f.tableDocType;
    if (t != null && t.isNotEmpty) ids.add(t);
    final l = f.linkDocType;
    if (l != null && l.isNotEmpty) ids.add(l);
  }
  final out = <String, DocType>{};
  for (final id in ids) {
    final dt = await registry.get(id);
    if (dt != null) out[id] = dt;
  }
  return out;
});

/// Master DocTypes referenced by required link fields (and required child-table
/// link columns) that currently have zero records — drives the non-blocking
/// "set up your basics first" banner. Port of Swift's `missingPrerequisites`.
final _missingPrerequisitesProvider =
    FutureProvider.family<List<MissingPrerequisite>, String>(
        (ref, docTypeName) async {
  final meta = await ref.watch(resolvedMetaProvider(docTypeName).future);
  if (meta == null) return const [];
  final registry = await ref.watch(metadataRegistryProvider.future);
  final engine = await ref.watch(documentEngineProvider.future);

  // Prefetch the child DocTypes so the (synchronous) traversal can see their
  // required link columns.
  final children = <String, DocType>{};
  for (final f in meta.docType.fields) {
    final t = f.tableDocType;
    if (f.type == FieldType.table && t != null && t.isNotEmpty) {
      final dt = await registry.get(t);
      if (dt != null) children[t] = dt;
    }
  }

  final targets = FormPrerequisites.candidateTargets(
    docType: meta.docType,
    childDocType: (id) => children[id],
  );

  final missing = <MissingPrerequisite>[];
  for (final target in targets) {
    final rows = await engine.list(target);
    if (rows.isEmpty) {
      final dt = await registry.get(target);
      missing.add(MissingPrerequisite(
        targetDocType: target,
        displayName: dt?.name ?? target,
      ));
    }
  }
  return missing;
});

/// Resolves a currency code (the value of a `currency` link field) to its
/// symbol, by convention: `currency` → `Currency` record → its `symbol` field.
/// Drives the prefix on `.currency` editors. Port of Swift's `currencySymbol`.
final _currencySymbolProvider =
    FutureProvider.family<String?, String>((ref, currencyCode) async {
  if (currencyCode.isEmpty) return null;
  final engine = await ref.watch(documentEngineProvider.future);
  final doc = await engine.fetch('Currency', currencyCode);
  final symbol = doc?.payload['symbol'];
  return (symbol is String && symbol.isNotEmpty) ? symbol : null;
});

class GenericFormView extends ConsumerStatefulWidget {
  const GenericFormView({
    super.key,
    required this.docTypeName,
    required this.documentName,
    this.linkSearchProvider,
    this.childDocTypeProvider,
    this.sectionColumns,
  });
  final String docTypeName;
  final String? documentName;

  /// Optional caller-supplied link picker search provider, forwarded
  /// to every link [FieldWidget]. Mirrors Swift PR #113.
  final LinkSearchProvider? linkSearchProvider;

  /// Optional resolver for a link target's [DocType] — used by the
  /// link picker to prefer the registry's title field, and by the new
  /// child-table grid to resolve `tableDocType` references.
  final DocType? Function(String docTypeId)? childDocTypeProvider;

  /// Optional per-section column hint. Swift PR #122's `columns: 2`
  /// equivalent — sections listed here lay their compact fields out as
  /// pairs; stacked field types (table, longText, multiselect, image,
  /// table) still span the full width. Section name is the same string
  /// used in [FieldDefinition.section]; the empty-string key targets
  /// fields with no explicit section.
  final Map<String, int>? sectionColumns;

  @override
  ConsumerState<GenericFormView> createState() => _GenericFormViewState();
}

class _GenericFormViewState extends ConsumerState<GenericFormView> {
  final Map<String, dynamic> _changes = {};

  /// Edits to child-table fields, keyed by field key. Tracked separately from
  /// [_changes] because child rows live in [Document.children] (the
  /// `document_children` table), not in the parent payload.
  final Map<String, List<Map<String, dynamic>>> _childChanges = {};
  bool _isSaving = false;
  String? _error;

  /// Live inline errors per field key, and the set of fields the user has
  /// touched. A field's error is only surfaced once it's been touched (or after
  /// a Save attempt, which marks every field touched) so a pristine form isn't
  /// pre-painted red. Mirrors Swift's blur-validated `fieldErrors`.
  final Map<String, String> _fieldErrors = {};
  final Set<String> _touched = {};

  /// Server-attributed child-table errors from the last save/submit, keyed
  /// table field key → row index → child field key → message. A row-level
  /// error (no child field, e.g. a duplicate-row rule) is stored under the
  /// empty-string key. Cleared for a table as soon as the user edits its rows,
  /// since the stale server verdict no longer applies to the new content.
  final Map<String, Map<int, Map<String, String>>> _childErrors = {};

  /// Spreads the engine's [ValidationError]s onto the fields/rows that caused
  /// them: parent-field errors reuse the existing inline-error channel
  /// ([_fieldErrors]); child-row errors populate [_childErrors] so the offending
  /// row shows a badge and its editor shows the message inline — instead of only
  /// the collapsed banner. Callers setState around this.
  void _distributeValidationErrors(List<ValidationError> errors) {
    final split = partitionValidationErrors(errors);
    _childErrors
      ..clear()
      ..addAll(split.child);
    split.parent.forEach((key, message) {
      // Surface inline beneath the offending control (mark touched so the
      // existing gate lets it render).
      _touched.add(key);
      _fieldErrors[key] = message;
    });
  }

  /// Re-evaluates one field against the current document and stores/clears its
  /// inline error. Only touched fields contribute to the surfaced map.
  void _validateField(ResolvedMeta meta, String key, Document doc) {
    final field = meta.fieldByKey(key);
    if (field == null) return;
    final message = localFieldValidationError(field, doc[key],
        isReadOnly: doc.docStatus != 0);
    if (message != null && _touched.contains(key)) {
      _fieldErrors[key] = message;
    } else {
      _fieldErrors.remove(key);
    }
  }

  /// Marks every editable field touched and validates them — used on Save so the
  /// user sees all outstanding required-field errors at once. Returns true when
  /// the form is locally valid.
  bool _validateAll(ResolvedMeta meta, Document doc) {
    for (final f in meta.visibleFields) {
      _touched.add(f.key);
      _validateField(meta, f.key, doc);
    }
    return _fieldErrors.isEmpty;
  }

  /// Guards against re-recording the same opened record on every rebuild.
  String? _recordedKey;

  bool get _isDirty => _changes.isNotEmpty || _childChanges.isNotEmpty;

  /// Captures an opened existing record into the Recents list. No-op for new
  /// drafts (no id yet) or until the [DocType] has resolved (needed for the
  /// display title). Records once per record per mount.
  void _maybeRecordRecent(Document base, DocType? type) {
    if (widget.documentName == null || base.id.isEmpty || type == null) return;
    final key = '${base.docType}::${base.id}';
    if (_recordedKey == key) return;
    _recordedKey = key;
    final entry = RecentEntry(
      docType: base.docType,
      docId: base.id,
      title: MetadataDisplay.titleFor(type, base),
      subtitle: MetadataDisplay.subtitleFor(type, base),
      openedAt: DateTime.now(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(recentsProvider.notifier).record(entry);
    });
  }

  Document _apply(Document base) {
    if (_changes.isEmpty && _childChanges.isEmpty) return base;
    final payload = Map<String, dynamic>.from(base.payload)..addAll(_changes);
    return applyChildChanges(base.copyWith(payload: payload), _childChanges);
  }

  Document _emptyDoc() => Document(id: '', docType: widget.docTypeName);

  Future<void> _save(
      DocumentEngine engine, Document current, ResolvedMeta? meta) async {
    // Local pre-flight: surface required/format errors inline before hitting
    // the engine. The full ValidationPipeline still runs in engine.save.
    if (meta != null && !_validateAll(meta, current)) {
      setState(() {});
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await engine.save(current, _userRoles);
      setState(() {
        _changes.clear();
        _childChanges.clear();
        // A clean save means no outstanding errors — drop any the previous
        // failed attempt attributed to fields/rows.
        _fieldErrors.clear();
        _childErrors.clear();
      });
      ref.invalidate(_fetchDocProvider((widget.docTypeName, current.id)));
    } catch (e) {
      setState(() {
        if (e is DocumentEngineError) {
          _error = e.humanMessage;
          _distributeValidationErrors(e.validationErrors);
        } else {
          _error = e.toString();
        }
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Runs a host-contributed [DocumentAction] (e.g. a document conversion),
  /// reusing the command bar's busy/error affordances. The action itself reaches
  /// the engine via [ref] and typically navigates away on success; the `mounted`
  /// guards cover the widget being torn down by that navigation.
  Future<void> _invokeAction(DocumentAction action, Document current) async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await action.invoke(context, ref, current);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e is DocumentEngineError ? e.humanMessage : e.toString());
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _submit(DocumentEngine engine, Document current) async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await engine.submit(current, _userRoles);
      setState(() {
        _fieldErrors.clear();
        _childErrors.clear();
      });
      ref.invalidate(_fetchDocProvider((widget.docTypeName, current.id)));
    } catch (e) {
      setState(() {
        if (e is DocumentEngineError) {
          _error = e.humanMessage;
          _distributeValidationErrors(e.validationErrors);
        } else {
          _error = e.toString();
        }
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fetchAsync =
        ref.watch(_fetchDocProvider((widget.docTypeName, widget.documentName)));
    final engineAsync = ref.watch(documentEngineProvider);
    final metaAsync = ref.watch(resolvedMetaProvider(widget.docTypeName));
    final referencedAsync =
        ref.watch(_referencedDocTypesProvider(widget.docTypeName));
    final referenced = referencedAsync.valueOrNull ?? const <String, DocType>{};

    // Default resolver: read from the prefetched map. Callers can still
    // override with their own (e.g. async HTTP-backed) implementation.
    DocType? defaultResolver(String id) => referenced[id];
    final effectiveChildResolver =
        widget.childDocTypeProvider ?? defaultResolver;

    return fetchAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (fetched) => engineAsync.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
        data: (engine) {
          final base = fetched ?? _emptyDoc();
          _maybeRecordRecent(base, metaAsync.valueOrNull?.docType);
          final doc = _apply(base);
          final docType = metaAsync.valueOrNull?.docType;
          final isSubmittable = docType?.isSubmittable ?? false;
          final docStatus = doc.docStatus;

          // Host-contributed actions (e.g. document conversion). Resolved
          // synchronously from the document's own fields once its DocType is
          // known; the work runs in [_invokeAction]. Suppressed on a dirty draft
          // so a conversion never reads stale, unsaved edits.
          final extraActions = <Widget>[];
          if (docType != null && !_isDirty) {
            final actions = ref
                .watch(documentActionRegistryProvider)
                .actionsFor(doc, docType);
            for (final action in actions) {
              extraActions.add(WorkflowActionButton(
                key: ValueKey('doc-action-${action.id}'),
                label: action.label,
                icon: action.icon,
                style: action.style,
                busy: _isSaving,
                onPressed: () => _invokeAction(action, doc),
              ));
            }
          }

          // Currency symbol prefix for `.currency` editors, resolved from the
          // document's `currency` link (re-resolves as the user changes it).
          final currencyCode = doc.payload['currency'];
          final currencySymbol = (currencyCode is String && currencyCode.isNotEmpty)
              ? ref.watch(_currencySymbolProvider(currencyCode)).valueOrNull
              : null;

          return RecordWorkspaceChrome(
            docTypeName: widget.docTypeName,
            documentName: doc.id.isEmpty ? null : doc.id,
            isDirty: _isDirty,
            isSaving: _isSaving,
            isSubmittable: isSubmittable,
            docStatus: docStatus,
            onSave: () => _save(engine, doc, metaAsync.valueOrNull),
            onSubmit: () => _submit(engine, doc),
            error: _error,
            extraActions: extraActions,
            child: metaAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (meta) => meta != null
                  ? Column(
                      children: [
                        // Non-blocking "set up your basics first" nudge, shown
                        // only on an editable draft.
                        if (docStatus == 0)
                          _PrerequisiteBannerHost(docTypeName: widget.docTypeName),
                        Expanded(
                          child: _MetaForm(
                            doc: doc,
                            meta: meta,
                            readOnly: docStatus != 0,
                            sectionColumns: widget.sectionColumns,
                            errors: _fieldErrors,
                            childErrors: _childErrors,
                            currencySymbol: currencySymbol,
                            onChanged: (k, v) => setState(() {
                              _changes[k] = v;
                              _touched.add(k);
                              _validateField(meta, k, _apply(base));
                            }),
                            onChildChanged: (k, rows) => setState(() {
                              _childChanges[k] = rows;
                              // The user changed this table's rows, so any
                              // server verdict attributed to its old content is
                              // stale — drop it until the next save re-checks.
                              _childErrors.remove(k);
                            }),
                            linkSearchProvider: widget.linkSearchProvider,
                            childDocTypeProvider: effectiveChildResolver,
                          ),
                        ),
                      ],
                    )
                  : _RawForm(doc: doc),
            ),
          );
        },
      ),
    );
  }
}

/// Internal section bucket. We bucket [ResolvedFieldDefinition]s by
/// their `section` string and tag each bucket with its requested column
/// count so the renderer can pair-up compact fields.
class _SectionGroup {
  _SectionGroup({
    required this.name,
    required this.columns,
    required this.explicit,
    required this.fields,
  });
  final String name;
  final int columns;

  /// Whether [columns] was set explicitly by the caller's `sectionColumns`
  /// (as opposed to the default). An explicit value — including an explicit
  /// `1` that pins the group full-width — is honoured over the responsive
  /// two-column default.
  final bool explicit;
  final List<ResolvedFieldDefinition> fields;
}

/// Render decision for one row of a two-column section.
sealed class _PairedRow {
  const _PairedRow();
}

class _Pair extends _PairedRow {
  const _Pair(this.left, this.right);
  final ResolvedFieldDefinition left;
  final ResolvedFieldDefinition? right;
}

class _Full extends _PairedRow {
  const _Full(this.field);
  final ResolvedFieldDefinition field;
}

class _MetaForm extends StatelessWidget {
  const _MetaForm({
    required this.doc,
    required this.meta,
    required this.readOnly,
    required this.onChanged,
    required this.onChildChanged,
    this.errors = const {},
    this.childErrors = const {},
    this.currencySymbol,
    this.sectionColumns,
    this.linkSearchProvider,
    this.childDocTypeProvider,
  });
  final Document doc;
  final ResolvedMeta meta;
  final bool readOnly;

  /// Inline validation errors keyed by field key — rendered as a footnote
  /// beneath the offending control.
  final Map<String, String> errors;

  /// Server-attributed child-table errors, keyed table field key → row index →
  /// child field key → message. Threaded into each [ChildTableField] to drive
  /// per-row badges and inline editor messages.
  final Map<String, Map<int, Map<String, String>>> childErrors;

  /// Symbol prefixed onto `.currency` editors (e.g. "€"), or null.
  final String? currencySymbol;
  final void Function(String key, dynamic value) onChanged;

  /// Child-table edits (a full replacement row list for [key]).
  final void Function(String key, List<Map<String, dynamic>> rows)
      onChildChanged;
  final Map<String, int>? sectionColumns;
  final LinkSearchProvider? linkSearchProvider;
  final DocType? Function(String docTypeId)? childDocTypeProvider;

  List<_SectionGroup> _groupedSections() {
    final groups = <String, _SectionGroup>{};
    final order = <String>[];
    for (final f in meta.visibleFields) {
      final key = f.section ?? '';
      final explicit = sectionColumns?.containsKey(key) ?? false;
      final cols = sectionColumns?[key] ?? 1;
      final g = groups.putIfAbsent(key, () {
        order.add(key);
        return _SectionGroup(
            name: key, columns: cols, explicit: explicit, fields: []);
      });
      g.fields.add(f);
    }
    return [for (final k in order) groups[k]!];
  }

  /// Lays the supplied fields out as either a sequence of pairs or full
  /// rows. Stacked field types (table, longText, multiselect, image)
  /// break the pair and span both columns — matches the Swift policy.
  List<_PairedRow> _paired(List<ResolvedFieldDefinition> fields) {
    final out = <_PairedRow>[];
    ResolvedFieldDefinition? pending;
    for (final f in fields) {
      if (_usesStackedLayout(f)) {
        if (pending != null) {
          out.add(_Pair(pending, null));
          pending = null;
        }
        out.add(_Full(f));
      } else if (pending != null) {
        out.add(_Pair(pending, f));
        pending = null;
      } else {
        pending = f;
      }
    }
    if (pending != null) out.add(_Pair(pending, null));
    return out;
  }

  bool _usesStackedLayout(ResolvedFieldDefinition f) {
    switch (f.type) {
      case FieldType.table:
      case FieldType.tableMultiSelect:
      case FieldType.longText:
      case FieldType.attach:
      case FieldType.attachImage:
      case FieldType.code:
      case FieldType.signature:
      case FieldType.barcode:
      case FieldType.geolocation:
        return true;
      default:
        return false;
    }
  }

  bool _containsTable(_SectionGroup g) => g.fields.any(
      (f) => f.type == FieldType.table || f.type == FieldType.tableMultiSelect);

  /// A computed money value — a read-only currency field. These are the
  /// document's totals; Step 3 lifts them out of the section flow and groups
  /// them into a pinned [AtlasSummaryCard] at the foot of the form. Matches the
  /// same rule [FieldWidget] uses to render them as [AtlasTotalRow].
  static bool _isSummaryField(ResolvedFieldDefinition f) =>
      f.readOnly && f.type == FieldType.currency;

  @override
  Widget build(BuildContext context) {
    final groups = _groupedSections();
    // Step 3: lift the document's money totals (read-only currency fields) out
    // of the ordinary section flow so they can be grouped and pinned as one
    // summary card. A section that held only totals drops out of the body; its
    // name titles the summary card so the grouping still reads in context.
    final summaryFields = <ResolvedFieldDefinition>[];
    String? summaryTitle;
    final bodyGroups = <_SectionGroup>[];
    for (final g in groups) {
      final kept = <ResolvedFieldDefinition>[];
      for (final f in g.fields) {
        if (_isSummaryField(f)) {
          summaryFields.add(f);
          summaryTitle ??= g.name.trim().isNotEmpty ? g.name : null;
        } else {
          kept.add(f);
        }
      }
      if (kept.isNotEmpty) {
        bodyGroups.add(_SectionGroup(
          name: g.name,
          columns: g.columns,
          explicit: g.explicit,
          fields: kept,
        ));
      }
    }
    // Responsive layout: on a wide pane (tablet-landscape and desktop, ≥ 840px
    // of *available* width — measured, not the screen, so it's correct inside a
    // master-detail split) compact fields pair up into two columns so forms use
    // the horizontal space instead of a tall single column. Narrow panes
    // (phone / tablet-portrait) stay single-column. A caller that pinned a
    // `sectionColumns` count still wins. Stacked field types (tables, long text,
    // attachments, …) always span full width via `_paired`/`_usesStackedLayout`.
    // Sheet surface shows through directly — no muted backdrop. Cards
    // differentiate via stroke alone, matching the modern HIG sheet
    // pattern PR #124 adopted on the Swift side.
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        // Honour an explicit per-section override (including an explicit `1`
        // that pins a group full-width); apply the responsive two-column
        // default only where the caller didn't specify a count.
        int columnsFor(_SectionGroup g) =>
            g.explicit ? g.columns : (wide ? 2 : 1);
        final body = SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final g in bodyGroups) ...[
                AtlasSectionCard(
                  name: g.name,
                  containsTable: _containsTable(g),
                  child: columnsFor(g) >= 2
                      ? _TwoColumnLayout(
                          rows: _paired(g.fields),
                          buildField: (f) => _buildField(f),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final f in g.fields)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildField(f),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        );
        if (summaryFields.isEmpty) return body;
        // Pin the grouped totals to the foot of the form so the bottom line
        // stays in view while the fields scroll above it. _MetaForm is hosted
        // in an Expanded, so `constraints` here is bounded — but a non-flex
        // child of a Column is laid out with *unbounded* height, so we must
        // hand that bounded height to the footer explicitly. Without it,
        // AtlasSummaryCard sees an infinite maxHeight, its 45% cap never
        // applies, and a tall totals list could grow to full content and
        // starve the scrolling body.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: body),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight),
              child: AtlasSummaryCard(
                title: summaryTitle,
                children: [
                  for (final f in summaryFields) _buildField(f),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Wraps the control with an inline footnote (help text + validation error)
  /// when either is present — port of Swift's `fieldFootnotes`.
  Widget _buildField(ResolvedFieldDefinition f) {
    final control = _buildControl(f);
    final help = f.helpText?.trim();
    final error = errors[f.key]?.trim();
    final hasFootnote =
        (help != null && help.isNotEmpty) || (error != null && error.isNotEmpty);
    if (!hasFootnote) return control;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        control,
        FieldFootnote(helpText: f.helpText, error: errors[f.key]),
      ],
    );
  }

  Widget _buildControl(ResolvedFieldDefinition f) {
    final isTable =
        f.type == FieldType.table || f.type == FieldType.tableMultiSelect;
    if (isTable) {
      final targetName = f.tableDocType ?? f.options ?? '';
      final resolved = childDocTypeProvider?.call(targetName);
      final rows = _rowsFor(f.key);
      return _LabelledField(
        label: f.label,
        required: f.required,
        child: ChildTableField(
          field: f,
          childDocType: resolved,
          rows: rows,
          readOnly: readOnly || f.readOnly,
          onChanged: (next) => onChildChanged(f.key, next),
          // Server-attributed per-row errors for this table (null when clean).
          errors: childErrors[f.key],
          // Give link columns (e.g. a line's Item) the same picker + resolver
          // the top-level link fields use, so they're selectable, not raw text.
          linkSearchProvider: linkSearchProvider,
          linkTargetResolver: childDocTypeProvider,
        ),
      );
    }
    return FieldWidget(
      field: f,
      value: doc[f.key],
      // Honour the field's own read-only flag as well as the form's — matches
      // the child-table branch above. A metadata read-only field (e.g. a
      // computed total) must render read-only even on an editable form.
      readOnly: readOnly || f.readOnly,
      onChanged: (v) => onChanged(f.key, v),
      currencySymbol: currencySymbol,
      linkSearchProvider: linkSearchProvider,
      childDocTypeProvider: childDocTypeProvider,
    );
  }

  /// Child rows come from [Document.children] (the `document_children` table),
  /// not the parent payload. In-flight edits are already merged here because
  /// the form rebuilds `doc.children` via `_apply` before this widget renders.
  List<Map<String, dynamic>> _rowsFor(String key) => childRowsAsMaps(doc, key);
}


class _LabelledField extends StatelessWidget {
  const _LabelledField({
    required this.label,
    required this.required,
    required this.child,
  });
  final String label;
  final bool required;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
            child: Text(
              required ? '$label *' : label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _TwoColumnLayout extends StatelessWidget {
  const _TwoColumnLayout({
    required this.rows,
    required this.buildField,
  });
  final List<_PairedRow> rows;
  final Widget Function(ResolvedFieldDefinition field) buildField;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: switch (row) {
              _Pair(:final left, :final right) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: buildField(left)),
                    const SizedBox(width: 20),
                    Expanded(
                      child: right == null
                          ? const SizedBox.shrink()
                          : buildField(right),
                    ),
                  ],
                ),
              _Full(:final field) => buildField(field),
            },
          ),
      ],
    );
  }
}

/// Watches [_missingPrerequisitesProvider] and renders the non-blocking
/// prerequisite banner, or nothing while loading / when all master data exists.
class _PrerequisiteBannerHost extends ConsumerWidget {
  const _PrerequisiteBannerHost({required this.docTypeName});
  final String docTypeName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missing = ref
            .watch(_missingPrerequisitesProvider(docTypeName))
            .valueOrNull ??
        const <MissingPrerequisite>[];
    if (missing.isEmpty) return const SizedBox.shrink();
    return PrerequisiteBanner(docTypeName: docTypeName, missing: missing);
  }
}

class _RawForm extends StatelessWidget {
  const _RawForm({required this.doc});
  final Document doc;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          for (final e in doc.payload.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                initialValue: e.value?.toString() ?? '',
                decoration: InputDecoration(labelText: e.key),
                readOnly: true,
              ),
            ),
        ],
      ),
    );
  }
}

class FieldWidget extends StatelessWidget {
  const FieldWidget({
    super.key,
    required this.field,
    required this.value,
    required this.readOnly,
    required this.onChanged,
    this.currencySymbol,
    this.linkSearchProvider,
    this.childDocTypeProvider,
  });
  final ResolvedFieldDefinition field;
  final dynamic value;
  final bool readOnly;
  final ValueChanged<dynamic> onChanged;

  /// Symbol prefixed onto the editor when this is a `.currency` field.
  final String? currencySymbol;

  /// Optional callback used by the link picker sheet to resolve
  /// search results. When `null` the picker falls back to a client-side
  /// scan via `documentEngineProvider`.
  final LinkSearchProvider? linkSearchProvider;

  /// Optional resolver for the target [DocType] of a link / child-table
  /// field. The picker uses it to prefer the registry's title field
  /// over the built-in key heuristic; supplied as part of the
  /// provider-forwarding contract from Swift PR #113.
  final DocType? Function(String docTypeId)? childDocTypeProvider;

  String get _label => field.label;

  /// Builds an `InputDecoration` that appends a red asterisk to the label
  /// when the field is required. Using `label:` (a `Widget`) instead of
  /// `labelText:` lets us inline the marker without giving up Material's
  /// native floating-label behaviour.
  ///
  /// Inside a child-table data cell (detected via [ChildTableContext]),
  /// the external label is dropped and the field name becomes
  /// `hintText` instead — the column header already carries the label,
  /// and Material's floating label otherwise eats so much horizontal
  /// space that narrow cells collapse to per-character columns. Mirrors
  /// Swift PR #121's `mercantisInput()` `.labelsHidden()` fix.
  InputDecoration _decoration(
    BuildContext context, {
    String? hintText,
    Widget? suffixIcon,
    String? suffixText,
    String? prefixText,
  }) {
    final inline = ChildTableContext.isInline(context);
    return InputDecoration(
      label: inline
          ? null
          : AtlasLabel.inheritStyle(label: _label, required: field.required),
      // Explicit placeholder wins; otherwise inline cells fall back to the
      // field label as ghost text (the column header already names them).
      hintText: hintText ?? field.placeholder ?? (inline ? _label : null),
      suffixIcon: suffixIcon,
      suffixText: suffixText,
      prefixText: prefixText,
      isDense: inline,
    );
  }

  /// Inline label widget for non-`InputDecoration` controls (heading,
  /// checkbox, etc.) — same red-asterisk treatment.
  Widget _inlineLabel(BuildContext context, {TextStyle? style}) {
    return AtlasLabel.inheritStyle(
      label: _label,
      required: field.required,
      style: style,
    );
  }

  String _atlasMoney(num? v) {
    final s = (v ?? 0).toDouble().toStringAsFixed(2);
    return (currencySymbol != null && currencySymbol!.isNotEmpty)
        ? '$currencySymbol$s'
        : s;
  }

  /// Wraps a composite scalar editor (rating, duration, code, colour) — rendered
  /// in its [embedded] labelless form — inside an Atlas field row so it reads as
  /// one language with the rest of the form. Inside a child-table cell the
  /// caller keeps the widget's own outlined rendering instead.
  Widget _atlasScalarRow(Widget embeddedChild) {
    return AtlasFieldRow(
      icon: atlasFieldIcon(field),
      label: _label,
      required: field.required,
      readOnly: readOnly,
      child: embeddedChild,
    );
  }

  /// An inline single-line text row (used for text / smallText / data and the
  /// default fallback). Inside a dense child-table cell it keeps the outlined
  /// editor; on a form it delegates to the public [AtlasTextInputRow].
  Widget _atlasTextRow(BuildContext context) {
    if (ChildTableContext.isInline(context)) {
      return AtlasTextFieldEditor(
        value: value?.toString() ?? '',
        decoration: _decoration(context),
        readOnly: readOnly,
        onChanged: onChanged,
      );
    }
    return AtlasTextInputRow(
      icon: atlasFieldIcon(field),
      label: _label,
      required: field.required,
      readOnly: readOnly,
      value: value?.toString(),
      placeholder: field.placeholder ?? 'Enter ${_label.toLowerCase()}',
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (field.type) {
      case FieldType.check:
        if (ChildTableContext.isInline(context)) {
          return CheckboxListTile(
            title: _inlineLabel(context),
            value: (value as int? ?? 0) == 1,
            onChanged: readOnly ? null : (v) => onChanged(v == true ? 1 : 0),
            contentPadding: EdgeInsets.zero,
          );
        }
        final on = (value as int? ?? 0) == 1;
        return AtlasFieldRow(
          icon: atlasFieldIcon(field),
          label: _label,
          required: field.required,
          readOnly: readOnly,
          onTap: readOnly ? null : () => onChanged(on ? 0 : 1),
          trailing: Switch(
            value: on,
            onChanged: readOnly ? null : (v) => onChanged(v ? 1 : 0),
          ),
        );
      case FieldType.integer:
        if (ChildTableContext.isInline(context)) {
          return AtlasTextFieldEditor(
            value: (value as int?)?.toString() ?? '',
            decoration: _decoration(context),
            keyboardType: TextInputType.number,
            readOnly: readOnly,
            onChanged: (v) => onChanged(int.tryParse(v)),
          );
        }
        return AtlasTextInputRow(
          icon: atlasFieldIcon(field),
          label: _label,
          required: field.required,
          readOnly: readOnly,
          value: (value as int?)?.toString(),
          keyboardType: TextInputType.number,
          onChanged: (v) => onChanged(int.tryParse(v)),
        );
      case FieldType.float:
      case FieldType.currency:
      case FieldType.percent:
        if (ChildTableContext.isInline(context)) {
          return AtlasTextFieldEditor(
            value: (value as num?)?.toString() ?? '',
            decoration: _decoration(
              context,
              suffixText: field.type == FieldType.percent ? '%' : null,
              prefixText:
                  field.type == FieldType.currency ? currencySymbol : null,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            readOnly: readOnly,
            onChanged: (v) => onChanged(double.tryParse(v)),
          );
        }
        final numVal = value as num?;
        // A read-only *currency* field is a computed money value → totals row;
        // the grand total gets the tinted emphasis. Gate on field.readOnly (not
        // the form-wide readOnly, which is also true for any submitted document)
        // so a plain Rate stays a normal scalar row. Restrict to currency, not
        // float: a read-only float such as an exchange/conversion rate (e.g.
        // 3.333) is not money and must not be rounded to 2dp with a currency
        // symbol — it renders as a plain read-only value row below.
        if (field.readOnly && field.type == FieldType.currency) {
          final k = field.key.toLowerCase();
          return AtlasTotalRow(
            label: _label,
            value: _atlasMoney(numVal),
            emphasize: k.contains('grand') || _label.toLowerCase().contains('grand'),
          );
        }
        return AtlasMoneyField(
          icon: atlasFieldIcon(field),
          label: _label,
          required: field.required,
          readOnly: readOnly,
          value: numVal,
          prefixText: field.type == FieldType.currency ? currencySymbol : null,
          suffixText: field.type == FieldType.percent ? '%' : null,
          onChanged: onChanged,
        );
      case FieldType.select:
        final opts = (field.options ?? '')
            .split('\n')
            .where((o) => o.isNotEmpty)
            .toList();
        // Atlas selector row on a form; the outlined dropdown only inside a
        // child-table cell (where the column header carries the label).
        if (!ChildTableContext.isInline(context)) {
          return AtlasSelectorRow(
            icon: atlasFieldIcon(field),
            label: _label,
            required: field.required,
            readOnly: readOnly,
            value: value as String?,
            options: opts,
            onChanged: onChanged,
          );
        }
        return DropdownButtonFormField<String>(
          initialValue: value as String?,
          decoration: _decoration(context),
          items: opts
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: readOnly ? null : (v) => onChanged(v),
        );
      case FieldType.date:
        if (!ChildTableContext.isInline(context)) {
          return AtlasDateFieldRow(
            icon: atlasFieldIcon(field),
            label: _label,
            required: field.required,
            value: value as String?,
            readOnly: readOnly,
            onChanged: onChanged,
            // Optional dates can be cleared (the picker only changes a date).
            onCleared: (readOnly || field.required)
                ? null
                : () => onChanged(null),
          );
        }
        return _DateField(
          label: _label,
          required: field.required,
          value: value as String?,
          readOnly: readOnly,
          onChanged: onChanged,
        );
      case FieldType.time:
        if (!ChildTableContext.isInline(context)) {
          return AtlasTimeFieldRow(
            icon: atlasFieldIcon(field),
            label: _label,
            required: field.required,
            value: value as String?,
            readOnly: readOnly,
            onChanged: onChanged,
          );
        }
        return _TimeField(
          label: _label,
          required: field.required,
          value: value as String?,
          readOnly: readOnly,
          onChanged: onChanged,
        );
      case FieldType.dateTime:
        if (!ChildTableContext.isInline(context)) {
          return AtlasDateTimeFieldRow(
            icon: atlasFieldIcon(field),
            label: _label,
            required: field.required,
            value: value as String?,
            readOnly: readOnly,
            onChanged: onChanged,
          );
        }
        return _DateTimeField(
          label: _label,
          required: field.required,
          value: value as String?,
          readOnly: readOnly,
          onChanged: onChanged,
        );
      case FieldType.link:
        return LinkPickerField(
          label: _label,
          targetDocType: field.linkDocType ?? field.options ?? '',
          value: value as String?,
          required: field.required,
          readOnly: readOnly,
          searchProvider: linkSearchProvider,
          targetDocTypeResolver: childDocTypeProvider,
          onChanged: onChanged,
          // Atlas selector row on a form; the outlined field only inside a
          // dense child-table cell.
          atlas: !ChildTableContext.isInline(context),
          icon: atlasFieldIcon(field),
        );
      case FieldType.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: _inlineLabel(
            context,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        );
      case FieldType.longText:
        if (ChildTableContext.isInline(context)) {
          return AtlasTextFieldEditor(
            value: value as String? ?? '',
            decoration: _decoration(context),
            maxLines: 5,
            readOnly: readOnly,
            onChanged: onChanged,
          );
        }
        // The Atlas text row preserves line breaks when read-only (a multi-line
        // child Text) and shows a 5-line editor otherwise.
        return AtlasTextInputRow(
          icon: atlasFieldIcon(field),
          label: _label,
          required: field.required,
          readOnly: readOnly,
          value: value as String?,
          placeholder: field.placeholder,
          maxLines: 5,
          onChanged: onChanged,
        );
      case FieldType.smallText:
      case FieldType.text:
        return _atlasTextRow(context);
      case FieldType.color:
        if (ChildTableContext.isInline(context)) {
          return ColorField(
            label: _label,
            required: field.required,
            value: value as String?,
            readOnly: readOnly,
            onChanged: onChanged,
          );
        }
        return _atlasScalarRow(ColorField(
          label: _label,
          required: field.required,
          value: value as String?,
          readOnly: readOnly,
          onChanged: onChanged,
          embedded: true,
        ));
      case FieldType.signature:
        return SignatureField(
          label: _label,
          required: field.required,
          value: value as String?,
          readOnly: readOnly,
          onChanged: onChanged,
        );
      case FieldType.barcode:
        return BarcodeField(
          label: _label,
          required: field.required,
          value: value as String?,
          readOnly: readOnly,
          onChanged: onChanged,
        );
      case FieldType.rating:
        if (ChildTableContext.isInline(context)) {
          return RatingField(
            label: _label,
            required: field.required,
            value: value,
            readOnly: readOnly,
            onChanged: onChanged,
          );
        }
        return _atlasScalarRow(RatingField(
          label: _label,
          required: field.required,
          value: value,
          readOnly: readOnly,
          onChanged: onChanged,
          embedded: true,
        ));
      case FieldType.duration:
        if (ChildTableContext.isInline(context)) {
          return DurationField(
            label: _label,
            required: field.required,
            value: value,
            readOnly: readOnly,
            onChanged: onChanged,
          );
        }
        return _atlasScalarRow(DurationField(
          label: _label,
          required: field.required,
          value: value,
          readOnly: readOnly,
          onChanged: onChanged,
          embedded: true,
        ));
      case FieldType.code:
        if (ChildTableContext.isInline(context)) {
          return CodeField(
            label: _label,
            required: field.required,
            value: value as String?,
            readOnly: readOnly,
            onChanged: onChanged,
          );
        }
        return _atlasScalarRow(CodeField(
          label: _label,
          required: field.required,
          value: value as String?,
          readOnly: readOnly,
          onChanged: onChanged,
          embedded: true,
        ));
      case FieldType.attach:
        return AttachmentField(
          label: _label,
          required: field.required,
          value: value as String?,
          readOnly: readOnly,
          onChanged: onChanged,
        );
      case FieldType.attachImage:
        return AttachmentField(
          label: _label,
          required: field.required,
          value: value as String?,
          readOnly: readOnly,
          onChanged: onChanged,
          isImage: true,
        );
      case FieldType.geolocation:
        return GeolocationField(
          label: _label,
          required: field.required,
          value: value as String?,
          readOnly: readOnly,
          onChanged: onChanged,
        );
      default:
        return _atlasTextRow(context);
    }
  }
}


class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.required,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });
  final String label;
  final bool required;
  final String? value;
  final bool readOnly;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final inline = ChildTableContext.isInline(context);
    return TextFormField(
      key: ValueKey('date_$value'),
      initialValue: value ?? '',
      decoration: InputDecoration(
        label: inline
            ? null
            : AtlasLabel.inheritStyle(label: label, required: required),
        hintText: inline ? label : null,
        isDense: inline,
        suffixIcon: readOnly
            ? null
            : IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate:
                        DateTime.tryParse(value ?? '') ?? DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    onChanged(DateFormat('yyyy-MM-dd').format(picked));
                  }
                },
              ),
      ),
      readOnly: readOnly,
      onChanged: readOnly ? null : onChanged,
    );
  }
}

/// Time-of-day picker storing a `HH:mm` string. Mirrors [_DateField].
class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.required,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });
  final String label;
  final bool required;
  final String? value;
  final bool readOnly;
  final ValueChanged<dynamic> onChanged;

  static TimeOfDay _parse(String? v) {
    if (v != null && v.contains(':')) {
      final parts = v.split(':');
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) return TimeOfDay(hour: h, minute: m);
    }
    return TimeOfDay.now();
  }

  static String _format(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final inline = ChildTableContext.isInline(context);
    return TextFormField(
      key: ValueKey('time_$value'),
      initialValue: value ?? '',
      decoration: InputDecoration(
        label: inline ? null : AtlasLabel.inheritStyle(label: label, required: required),
        hintText: inline ? label : null,
        isDense: inline,
        suffixIcon: readOnly
            ? null
            : IconButton(
                icon: const Icon(Icons.schedule),
                onPressed: () async {
                  final picked = await showTimePicker(context: context, initialTime: _parse(value));
                  if (picked != null) onChanged(_format(picked));
                },
              ),
      ),
      readOnly: readOnly,
      onChanged: readOnly ? null : onChanged,
    );
  }
}

/// Combined date + time picker storing a `yyyy-MM-dd HH:mm` string.
class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.required,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });
  final String label;
  final bool required;
  final String? value;
  final bool readOnly;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final inline = ChildTableContext.isInline(context);
    return TextFormField(
      key: ValueKey('datetime_$value'),
      initialValue: value ?? '',
      decoration: InputDecoration(
        label: inline ? null : AtlasLabel.inheritStyle(label: label, required: required),
        hintText: inline ? label : null,
        isDense: inline,
        suffixIcon: readOnly
            ? null
            : IconButton(
                icon: const Icon(Icons.event),
                onPressed: () async {
                  final existing = DateTime.tryParse(value ?? '') ?? DateTime.now();
                  final date = await showDatePicker(
                    context: context,
                    initialDate: existing,
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                  );
                  if (date == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(existing),
                  );
                  if (time == null) return;
                  final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                  onChanged(DateFormat('yyyy-MM-dd HH:mm').format(combined));
                },
              ),
      ),
      readOnly: readOnly,
      onChanged: readOnly ? null : onChanged,
    );
  }
}
