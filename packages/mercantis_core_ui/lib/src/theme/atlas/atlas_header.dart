import 'package:flutter/material.dart';

/// The Atlas app-bar header. A thin wrapper over the themed [AppBar] that gives
/// every workspace one header construction — a title (with an optional
/// [subtitle] stacked beneath it), trailing [actions], and an optional [bottom]
/// (typically [AtlasTabs]). Styling defers to the app `AppBarTheme`.
///
/// Implements [PreferredSizeWidget] so it slots straight into `Scaffold.appBar`.
class AtlasHeader extends StatelessWidget implements PreferredSizeWidget {
  const AtlasHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
    this.onSearch,
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  /// When set, a leading search action is prepended to [actions] — the tappable
  /// global-search entry point for surfaces (notably phones) that have no
  /// navigation-rail search button.
  final VoidCallback? onSearch;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sub = subtitle?.trim();
    return AppBar(
      leading: leading,
      title: (sub == null || sub.isEmpty)
          ? Text(title)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title),
                Text(
                  sub,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
      actions: [
        if (onSearch != null)
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: onSearch,
          ),
        ...actions,
      ],
      bottom: bottom,
    );
  }
}
