/// How a collection of records is presented in a record workspace.
///
/// Port of Swift `UIShell/RecordViewMode.swift`. The Flutter
/// [RecordCollectionView] currently renders [list] and [tree]; [browse] and
/// [detail] (the master/detail split panes) are reserved for a follow-up so the
/// enum already matches its Swift counterpart.
enum RecordViewMode {
  list,
  browse,
  tree,
  detail;

  String get title => switch (this) {
        RecordViewMode.list => 'List',
        RecordViewMode.browse => 'Browse',
        RecordViewMode.tree => 'Tree',
        RecordViewMode.detail => 'Detail',
      };

  static RecordViewMode? fromName(String? name) {
    for (final mode in RecordViewMode.values) {
      if (mode.name == name) return mode;
    }
    return null;
  }
}

/// The view modes a record workspace offers and which it opens on.
///
/// Mirrors Swift `RecordCollectionViewConfiguration`: an empty supported set
/// normalises to `[list]`, and a default that isn't in the supported set falls
/// back to the first supported mode.
class RecordCollectionViewConfiguration {
  final List<RecordViewMode> supportedViewModes;
  final RecordViewMode defaultViewMode;

  const RecordCollectionViewConfiguration._(
      this.supportedViewModes, this.defaultViewMode);

  factory RecordCollectionViewConfiguration({
    List<RecordViewMode> supportedViewModes = const [RecordViewMode.list],
    RecordViewMode defaultViewMode = RecordViewMode.list,
  }) {
    final supported = supportedViewModes.isEmpty
        ? const [RecordViewMode.list]
        : supportedViewModes;
    final fallback =
        supported.contains(defaultViewMode) ? defaultViewMode : supported.first;
    return RecordCollectionViewConfiguration._(supported, fallback);
  }
}
