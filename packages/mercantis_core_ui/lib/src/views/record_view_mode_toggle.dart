import 'package:flutter/material.dart';

import 'record_view_mode.dart';

/// List ↔ Tree switcher shown only for hierarchical (`isTree`) DocTypes. Shared
/// by the studio [GenericListView] and the hub [MetadataListView] so the two
/// stay identical.
class RecordViewModeToggle extends StatelessWidget {
  const RecordViewModeToggle({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final RecordViewMode mode;
  final ValueChanged<RecordViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<RecordViewMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: RecordViewMode.list,
              icon: Icon(Icons.view_list_outlined),
              label: Text('List'),
            ),
            ButtonSegment(
              value: RecordViewMode.tree,
              icon: Icon(Icons.account_tree_outlined),
              label: Text('Tree'),
            ),
          ],
          selected: {
            mode == RecordViewMode.tree
                ? RecordViewMode.tree
                : RecordViewMode.list
          },
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ),
    );
  }
}
