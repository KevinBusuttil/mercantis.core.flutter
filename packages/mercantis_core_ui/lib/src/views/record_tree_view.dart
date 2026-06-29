import 'package:flutter/material.dart';
import 'package:mercantis_core/mercantis_core.dart';

import '../metadata/metadata_display.dart';

/// A node in a [RecordTree] — a document plus its (already sorted) children.
class RecordTreeNode {
  RecordTreeNode(this.document, this.children);

  final Document document;
  final List<RecordTreeNode> children;

  String get id => document.id;
  bool get hasChildren => children.isNotEmpty;
}

/// Builds the hierarchy for a tree DocType from its self-referential link
/// field. Pure (no widgets) so the parent/child derivation, cycle handling, and
/// ordering are unit-testable. Port of the private `buildTree`/ordering logic in
/// Swift `UIShell/RecordTreeView.swift`.
class RecordTree {
  const RecordTree._();

  /// The key of the `.link` field that points back at this DocType — e.g.
  /// `parent_account` for `Account`. Prefers an explicit [DocType.parentField],
  /// then falls back to the first self-referential link field (matching Swift).
  static String? parentFieldKey(DocType docType) {
    final declared = docType.parentField;
    if (declared != null && declared.isNotEmpty) return declared;
    for (final f in docType.fields) {
      if (f.type == FieldType.link && f.linkDocType == docType.id) return f.key;
    }
    return null;
  }

  /// A numeric code/number field to order siblings by (so a chart of accounts
  /// reads 1010, 1020, 2010…). Null when the DocType has none.
  static String? sortFieldKey(DocType docType) {
    for (final f in docType.fields) {
      if (f.key.contains('number') || f.key.contains('code')) return f.key;
    }
    return null;
  }

  /// Roots of the tree, each with its descendants attached. A document whose
  /// parent id is absent, points at itself, or isn't in [documents] is treated
  /// as a root — so a broken parent link surfaces the row rather than hiding it,
  /// and a parent cycle simply leaves both nodes out of the descent.
  static List<RecordTreeNode> build(DocType docType, List<Document> documents) {
    final parentKey = parentFieldKey(docType);
    final ids = documents.map((d) => d.id).toSet();
    final childrenByParent = <String, List<Document>>{};
    final roots = <Document>[];

    for (final doc in documents) {
      final parent = parentKey == null ? null : _stringValue(doc.payload[parentKey]);
      if (parent != null && parent != doc.id && ids.contains(parent)) {
        (childrenByParent[parent] ??= []).add(doc);
      } else {
        roots.add(doc);
      }
    }

    final order = _orderer(docType);
    RecordTreeNode node(Document doc) {
      final kids = (childrenByParent[doc.id] ?? [])..sort(order);
      return RecordTreeNode(doc, kids.map(node).toList());
    }

    return (roots..sort(order)).map(node).toList();
  }

  static int Function(Document, Document) _orderer(DocType docType) {
    final sortKey = sortFieldKey(docType);
    return (a, b) {
      if (sortKey != null) {
        final av = _stringValue(a.payload[sortKey]) ?? '';
        final bv = _stringValue(b.payload[sortKey]) ?? '';
        if (av != bv) return av.compareTo(bv);
      }
      return _title(docType, a).toLowerCase().compareTo(_title(docType, b).toLowerCase());
    };
  }

  static String _title(DocType docType, Document doc) =>
      MetadataDisplay.titleFor(docType, doc);

  static String? codeFor(DocType docType, Document doc) {
    final key = sortFieldKey(docType);
    if (key == null) return null;
    return _stringValue(doc.payload[key]);
  }

  static String? _stringValue(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// A hierarchical (outline) presentation of a tree DocType's records — e.g. the
/// Chart of Accounts. Parent rows carry a disclosure control that expands to
/// reveal their children (derived from the DocType's self-referential link
/// field); tapping any row drives [onSelect], the same hook the list view uses
/// to open a record. Groups start expanded, matching SwiftUI's `OutlineGroup`.
///
/// Port of Swift `UIShell/RecordTreeView.swift`.
class RecordTreeView extends StatefulWidget {
  const RecordTreeView({
    super.key,
    required this.docType,
    required this.documents,
    required this.selectedDocumentId,
    required this.onSelect,
  });

  final DocType docType;
  final List<Document> documents;
  final String? selectedDocumentId;
  final ValueChanged<Document> onSelect;

  @override
  State<RecordTreeView> createState() => _RecordTreeViewState();
}

class _RecordTreeViewState extends State<RecordTreeView> {
  /// Ids of collapsed parents. Empty = everything expanded (the default), so a
  /// freshly opened tree shows its full structure like SwiftUI's OutlineGroup.
  final Set<String> _collapsed = {};

  void _toggle(String id) => setState(() {
        // remove() returns false when the id wasn't collapsed → expand it.
        if (!_collapsed.remove(id)) _collapsed.add(id);
      });

  /// Depth-first flatten of the visible rows: a node, then (unless collapsed)
  /// its children. Done once per build so the list is a flat, scrollable run
  /// rather than nested slivers.
  void _flatten(RecordTreeNode node, int depth, List<_VisibleRow> out) {
    final expanded = !_collapsed.contains(node.id);
    out.add(_VisibleRow(node, depth, expanded));
    if (expanded) {
      for (final child in node.children) {
        _flatten(child, depth + 1, out);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roots = RecordTree.build(widget.docType, widget.documents);
    if (roots.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined,
                size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text('No records', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    }

    final rows = <_VisibleRow>[];
    for (final node in roots) {
      _flatten(node, 0, rows);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rows.length,
      itemBuilder: (context, i) => _TreeRowTile(
        row: rows[i],
        docType: widget.docType,
        isSelected: rows[i].node.id == widget.selectedDocumentId,
        onTap: () => widget.onSelect(rows[i].node.document),
        onToggle: () => _toggle(rows[i].node.id),
      ),
    );
  }
}

class _VisibleRow {
  _VisibleRow(this.node, this.depth, this.expanded);
  final RecordTreeNode node;
  final int depth;
  final bool expanded;
}

class _TreeRowTile extends StatelessWidget {
  const _TreeRowTile({
    required this.row,
    required this.docType,
    required this.isSelected,
    required this.onTap,
    required this.onToggle,
  });

  final _VisibleRow row;
  final DocType docType;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final node = row.node;
    final indent = 8.0 + row.depth * 16.0;

    final code = RecordTree.codeFor(docType, node.document);
    final disclosure = node.hasChildren
        ? IconButton(
            icon: Icon(row.expanded
                ? Icons.keyboard_arrow_down
                : Icons.keyboard_arrow_right),
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            tooltip: row.expanded ? 'Collapse' : 'Expand',
            onPressed: onToggle,
          )
        // Keep leaves aligned under their siblings' labels.
        : const SizedBox(width: 40);

    return ListTile(
      contentPadding: EdgeInsets.only(left: indent, right: 16),
      dense: true,
      selected: isSelected,
      leading: disclosure,
      title: Text(
        MetadataDisplay.titleFor(docType, node.document),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: node.hasChildren ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: code == null
          ? null
          : Text(
              code,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      onTap: onTap,
    );
  }
}
