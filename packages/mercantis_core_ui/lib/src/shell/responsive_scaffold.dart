import 'package:flutter/material.dart';
import '../theme/tokens/spacing.dart';
import 'breakpoints.dart';

/// A simple content scaffold for workspace-level pages. Provides a wide,
/// padded body with optional title bar and floating actions.
class ResponsiveScaffold extends StatelessWidget {
  const ResponsiveScaffold({
    super.key,
    this.title,
    this.subtitle,
    this.titleWidget,
    this.actions = const [],
    this.leading,
    this.automaticallyImplyLeading = true,
    required this.body,
    this.floatingActionButton,
    this.maxBodyWidth = 1440,
    this.padBody = true,
  });

  final String? title;
  final String? subtitle;
  final Widget? titleWidget;
  final List<Widget> actions;
  final Widget? leading;

  /// Mirrors [AppBar.automaticallyImplyLeading]: when no explicit [leading] is
  /// given and the enclosing route can pop (e.g. the page was pushed from a
  /// Settings tile), a back button is shown. Since this scaffold has no AppBar
  /// to supply one, this keeps pushed pages navigable. Set false to suppress it.
  final bool automaticallyImplyLeading;
  final Widget body;
  final Widget? floatingActionButton;
  final double maxBodyWidth;
  final bool padBody;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bp = Breakpoint.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final hPadding = bp.isPhone ? MercantisSpacing.lg : MercantisSpacing.xxl;
    final vPadding = bp.isPhone ? MercantisSpacing.md : MercantisSpacing.xl;

    // Fall back to a route-pop back button when nothing explicit was supplied.
    final effectiveLeading = leading ??
        (automaticallyImplyLeading && Navigator.of(context).canPop()
            ? const BackButton()
            : null);

    Widget content = body;
    if (padBody) {
      content = Padding(
        padding: EdgeInsets.fromLTRB(hPadding, MercantisSpacing.lg, hPadding, vPadding),
        child: content,
      );
    }
    if (width > maxBodyWidth) {
      content = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxBodyWidth),
          child: content,
        ),
      );
    }

    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null ||
              titleWidget != null ||
              actions.isNotEmpty ||
              effectiveLeading != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                hPadding, MercantisSpacing.xl, hPadding, MercantisSpacing.sm,
              ),
              child: Row(
                children: [
                  if (effectiveLeading != null) ...[
                    effectiveLeading,
                    const SizedBox(width: MercantisSpacing.md),
                  ],
                  Expanded(
                    child: titleWidget ??
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (title != null)
                              Text(title!, style: theme.textTheme.headlineMedium),
                            if (subtitle != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  subtitle!,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                          ],
                        ),
                  ),
                  if (actions.isNotEmpty)
                    Wrap(
                      spacing: MercantisSpacing.sm,
                      children: actions,
                    ),
                ],
              ),
            ),
          Expanded(child: SafeArea(top: false, bottom: false, child: content)),
        ],
      ),
    );
  }
}
