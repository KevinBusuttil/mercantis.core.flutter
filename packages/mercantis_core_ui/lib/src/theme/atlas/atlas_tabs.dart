import 'package:flutter/material.dart';

/// Themed tab bar for Atlas chrome. Builds [Tab]s from plain string [labels] and
/// otherwise defers to the app `TabBarTheme`, so every tabbed surface reads the
/// same. Implements [PreferredSizeWidget] so it drops straight into an
/// [AppBar.bottom] / [AtlasHeader.bottom], and it also stands alone inside a
/// side panel.
class AtlasTabs extends StatelessWidget implements PreferredSizeWidget {
  const AtlasTabs({
    super.key,
    required this.controller,
    required this.labels,
    this.isScrollable = false,
  });

  final TabController controller;
  final List<String> labels;
  final bool isScrollable;

  @override
  Size get preferredSize => const Size.fromHeight(kTextTabBarHeight);

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: controller,
      isScrollable: isScrollable,
      tabs: [for (final label in labels) Tab(text: label)],
    );
  }
}
