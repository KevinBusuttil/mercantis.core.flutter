import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/core_providers.dart';

/// Developer ▸ Data Browser: a read-only SQL console with a schema sidebar
/// (tables + columns), a flexible result table (sort, per-column filter, global
/// search, copy-CSV) and saved queries. Port of Swift `DataBrowserView`.
///
/// Read-only by construction: every statement goes through
/// [ReadOnlyQueryRunner.runReadOnlyQuery], which permits only a single
/// SELECT/WITH/EXPLAIN/PRAGMA. **Gate access to a privileged role** (e.g. System
/// Manager) at the route level — this is a developer tool.
class DataBrowserView extends ConsumerStatefulWidget {
  const DataBrowserView({super.key});

  @override
  ConsumerState<DataBrowserView> createState() => _DataBrowserViewState();
}

class _ColumnInfo {
  const _ColumnInfo(this.name, this.type, this.isPrimaryKey);
  final String name;
  final String type;
  final bool isPrimaryKey;
}

class _SavedQuery {
  const _SavedQuery(this.name, this.sql);
  final String name;
  final String sql;

  Map<String, dynamic> toJson() => {'name': name, 'sql': sql};
  static _SavedQuery fromJson(Map<String, dynamic> j) =>
      _SavedQuery(j['name'] as String? ?? '', j['sql'] as String? ?? '');
}

class _DataBrowserViewState extends ConsumerState<DataBrowserView> {
  static const _defaultSql =
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;";
  static const _savedKey = 'databrowser.saved_queries';
  static const _renderCap = 1000;
  static const _colWidth = 180.0;

  final TextEditingController _sql = TextEditingController(text: _defaultSql);
  final TextEditingController _search = TextEditingController();

  ReadOnlyQueryResult? _result;
  String? _error;
  bool _running = false;

  int? _sortColumn;
  bool _sortAscending = true;
  final Map<int, String> _columnFilters = {};

  List<_SavedQuery> _saved = [];
  List<String> _tables = [];
  final Set<String> _expanded = {};
  final Map<String, List<_ColumnInfo>> _tableColumns = {};

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _loadSaved();
    _loadTables();
  }

  @override
  void dispose() {
    _sql.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<ReadOnlyQueryResult> _query(String sql) async {
    final database = await ref.read(mercantisDatabaseProvider.future);
    return database.runReadOnlyQuery(sql);
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final r = await _query(_sql.text);
      if (!mounted) return;
      setState(() {
        _result = r;
        _sortColumn = null;
        _columnFilters.clear();
        _search.clear();
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _result = null;
        _running = false;
      });
    }
  }

  Future<void> _loadTables() async {
    try {
      final r = await _query(
          "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
      if (!mounted) return;
      setState(() => _tables = [
            for (final row in r.rows)
              if (row.isNotEmpty) row.first
          ]);
    } catch (_) {
      // Non-fatal — the sidebar just stays empty.
    }
  }

  Future<void> _loadColumns(String table) async {
    try {
      final r = await _query('PRAGMA table_info("$table")');
      final nameIdx = r.columns.indexOf('name');
      final typeIdx = r.columns.indexOf('type');
      final pkIdx = r.columns.indexOf('pk');
      String at(List<String> row, int i) =>
          (i >= 0 && i < row.length) ? row[i] : '';
      if (!mounted) return;
      setState(() => _tableColumns[table] = [
            for (final row in r.rows)
              _ColumnInfo(
                at(row, nameIdx < 0 ? 1 : nameIdx),
                at(row, typeIdx < 0 ? 2 : typeIdx),
                at(row, pkIdx < 0 ? 5 : pkIdx) != '0',
              ),
          ]);
    } catch (_) {/* ignore */}
  }

  void _toggleTable(String table) {
    setState(() {
      if (_expanded.remove(table)) return;
      _expanded.add(table);
      if (_tableColumns[table] == null) _loadColumns(table);
    });
  }

  void _toggleSort(int column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  // MARK: saved queries

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_savedKey);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => _SavedQuery.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() => _saved = list);
    } catch (_) {/* ignore corrupt prefs */}
  }

  Future<void> _persistSaved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _savedKey, jsonEncode([for (final q in _saved) q.toJson()]));
  }

  Future<void> _saveCurrent() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => const _SaveQueryDialog(),
    );
    if (name == null || name.trim().isEmpty) return;
    setState(() => _saved = [..._saved, _SavedQuery(name.trim(), _sql.text)]);
    await _persistSaved();
  }

  Future<void> _deleteSaved(int index) async {
    setState(() => _saved = [..._saved]..removeAt(index));
    await _persistSaved();
  }

  // MARK: result processing

  List<List<String>> _processedRows(ReadOnlyQueryResult result) {
    var rows = result.rows;
    final global = _search.text.trim().toLowerCase();
    if (global.isNotEmpty) {
      rows = rows
          .where((row) => row.any((c) => c.toLowerCase().contains(global)))
          .toList();
    }
    _columnFilters.forEach((column, needle) {
      final lowered = needle.toLowerCase();
      if (lowered.isEmpty) return;
      rows = rows
          .where((r) =>
              column < r.length && r[column].toLowerCase().contains(lowered))
          .toList();
    });
    final sortColumn = _sortColumn;
    if (sortColumn != null) {
      rows = [...rows]..sort((a, b) {
          final av = sortColumn < a.length ? a[sortColumn] : '';
          final bv = sortColumn < b.length ? b[sortColumn] : '';
          final an = double.tryParse(av);
          final bn = double.tryParse(bv);
          final cmp = (an != null && bn != null)
              ? an.compareTo(bn)
              : av.toLowerCase().compareTo(bv.toLowerCase());
          return _sortAscending ? cmp : -cmp;
        });
    }
    return rows;
  }

  String _csv(ReadOnlyQueryResult result) {
    String esc(String s) =>
        (s.contains(',') || s.contains('"') || s.contains('\n'))
            ? '"${s.replaceAll('"', '""')}"'
            : s;
    final rows = _processedRows(result);
    final buf = StringBuffer()..writeln(result.columns.map(esc).join(','));
    for (final row in rows) {
      buf.writeln(row.map(esc).join(','));
    }
    return buf.toString();
  }

  // MARK: build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data Browser')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 260, child: _sidebar(context)),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _editorPane(context),
                const Divider(height: 1),
                Expanded(child: _resultsPane(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebar(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _sidebarHeading(context, 'SAVED QUERIES'),
        if (_saved.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Save a query to reuse it later.',
                style: TextStyle(fontSize: 12)),
          ),
        for (var i = 0; i < _saved.length; i++)
          ListTile(
            dense: true,
            title: Text(_saved[i].name, maxLines: 1),
            onTap: () => setState(() => _sql.text = _saved[i].sql),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: 'Delete saved query',
              onPressed: () => _deleteSaved(i),
            ),
          ),
        const Divider(),
        _sidebarHeading(context, 'TABLES'),
        if (_tables.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('No tables found.', style: TextStyle(fontSize: 12)),
          ),
        for (final table in _tables)
          _TableTile(
            table: table,
            expanded: _expanded.contains(table),
            columns: _tableColumns[table],
            onToggle: () => _toggleTable(table),
            onOpen: () {
              setState(() => _sql.text = 'SELECT * FROM "$table" LIMIT 100;');
              _run();
            },
            theme: theme,
          ),
      ],
    );
  }

  Widget _sidebarHeading(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
        child: Text(text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
      );

  Widget _editorPane(BuildContext context) {
    final theme = Theme.of(context);
    final emptySql = _sql.text.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('READ-ONLY SQL',
                  style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant)),
              const Spacer(),
              if (_running)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              TextButton.icon(
                onPressed: emptySql ? null : _saveCurrent,
                icon: const Icon(Icons.bookmark_border, size: 18),
                label: const Text('Save'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _running ? null : _run,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Run'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _sql,
            maxLines: 6,
            minLines: 3,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              hintText: 'SELECT * FROM documents LIMIT 100',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline,
                      size: 16, color: theme.colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_error!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultsPane(BuildContext context) {
    final result = _result;
    if (result == null) {
      return _centered('Run a query to see results here.');
    }
    if (result.columns.isEmpty) {
      return Column(
        children: [
          _resultsToolbar(context, result, 0),
          const Divider(height: 1),
          Expanded(
              child: _centered('Query ran, but returned no columns.')),
        ],
      );
    }
    final rows = _processedRows(result);
    final shown = rows.length;
    final capped = rows.length > _renderCap ? rows.sublist(0, _renderCap) : rows;
    return Column(
      children: [
        _resultsToolbar(context, result, shown),
        const Divider(height: 1),
        Expanded(child: _resultsTable(context, result.columns, capped)),
      ],
    );
  }

  Widget _resultsToolbar(
      BuildContext context, ReadOnlyQueryResult result, int shown) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search results',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_summary(result, shown),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _csv(result)));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied result as CSV')),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy CSV'),
          ),
        ],
      ),
    );
  }

  String _summary(ReadOnlyQueryResult result, int shown) {
    final parts = <String>[];
    if (shown == result.rows.length) {
      parts.add('$shown row${shown == 1 ? '' : 's'}');
    } else {
      parts.add('$shown of ${result.rows.length} rows');
    }
    if (shown > _renderCap) parts.add('showing first $_renderCap');
    if (result.truncated) parts.add('query capped');
    return parts.join(' · ');
  }

  Widget _resultsTable(
      BuildContext context, List<String> columns, List<List<String>> rows) {
    final theme = Theme.of(context);
    final totalWidth = columns.length * _colWidth;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: totalWidth < 320 ? 320 : totalWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header (tappable sort)
            Container(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  for (var i = 0; i < columns.length; i++)
                    InkWell(
                      onTap: () => _toggleSort(i),
                      child: SizedBox(
                        width: _colWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(columns[i],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12)),
                              ),
                              if (_sortColumn == i)
                                Icon(
                                    _sortAscending
                                        ? Icons.arrow_drop_up
                                        : Icons.arrow_drop_down,
                                    size: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Per-column filters
            Row(
              children: [
                for (var i = 0; i < columns.length; i++)
                  SizedBox(
                    width: _colWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: TextField(
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Filter',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                        style: const TextStyle(fontSize: 11),
                        onChanged: (v) => setState(() {
                          if (v.isEmpty) {
                            _columnFilters.remove(i);
                          } else {
                            _columnFilters[i] = v;
                          }
                        }),
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, r) {
                  final row = rows[r];
                  return Container(
                    color: r.isEven
                        ? null
                        : theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.35),
                    child: Row(
                      children: [
                        for (var c = 0; c < columns.length; c++)
                          SizedBox(
                            width: _colWidth,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 5),
                              child: Text(
                                c < row.length ? row[c] : '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 12),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _centered(String message) => Center(
        child: Text(message,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _TableTile extends StatelessWidget {
  const _TableTile({
    required this.table,
    required this.expanded,
    required this.columns,
    required this.onToggle,
    required this.onOpen,
    required this.theme,
  });

  final String table;
  final bool expanded;
  final List<_ColumnInfo>? columns;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          dense: true,
          leading: IconButton(
            icon: Icon(expanded ? Icons.expand_more : Icons.chevron_right,
                size: 20),
            onPressed: onToggle,
            tooltip: expanded ? 'Hide columns' : 'Show columns',
          ),
          title: Row(
            children: [
              const Icon(Icons.table_chart_outlined, size: 16),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(table,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12))),
            ],
          ),
          onTap: onOpen,
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: 24, bottom: 6),
            child: columns == null
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 0, 4),
                    child: Text('Loading…', style: TextStyle(fontSize: 11)),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final col in columns!)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 2),
                          child: Row(
                            children: [
                              Icon(
                                  col.isPrimaryKey
                                      ? Icons.key
                                      : Icons.circle,
                                  size: col.isPrimaryKey ? 12 : 6,
                                  color: col.isPrimaryKey
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(col.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11))),
                              Text(col.type,
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      color:
                                          theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
      ],
    );
  }
}

class _SaveQueryDialog extends StatefulWidget {
  const _SaveQueryDialog();

  @override
  State<_SaveQueryDialog> createState() => _SaveQueryDialogState();
}

class _SaveQueryDialogState extends State<_SaveQueryDialog> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save query'),
      content: TextField(
        controller: _name,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_name.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
