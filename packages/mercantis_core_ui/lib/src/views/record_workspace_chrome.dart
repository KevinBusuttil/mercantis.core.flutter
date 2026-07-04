import 'package:flutter/material.dart';
import '../theme/atlas/atlas.dart';
import '../widgets/attachments_panel.dart';
import '../widgets/document_timeline_view.dart';
import '../widgets/print_record_button.dart';
import 'command_bar_view.dart';
import 'customize_fields_sheet.dart';

/// At or above this width the record keeps Timeline + Attachments visible as a
/// persistent side panel next to the form (desktop / large tablet-landscape)
/// instead of hiding them behind tabs. Measured on the record's own width.
const double _kSidePanelMinWidth = 1024;

/// Fixed width of that side panel. Chosen so a 1200px window still leaves the
/// form >= 840px — its own two-column breakpoint — so the side panel doesn't
/// collapse the form back to a single column at common desktop widths.
const double _kSidePanelWidth = 320;

class RecordWorkspaceChrome extends StatefulWidget {
  const RecordWorkspaceChrome({
    super.key,
    required this.docTypeName,
    required this.documentName,
    required this.isDirty,
    required this.isSaving,
    required this.isSubmittable,
    required this.docStatus,
    required this.onSave,
    required this.onSubmit,
    required this.child,
    this.onCancel,
    this.onAmend,
    this.error,
    this.extraActions = const <Widget>[],
  });

  final String docTypeName;
  final String? documentName;
  final bool isDirty;
  final bool isSaving;
  final bool isSubmittable;
  final int docStatus;
  final VoidCallback onSave;
  final VoidCallback onSubmit;
  final VoidCallback? onCancel;
  final VoidCallback? onAmend;
  final String? error;

  /// Host-contributed command-bar actions, forwarded to [CommandBarView].
  final List<Widget> extraActions;
  final Widget child;

  @override
  State<RecordWorkspaceChrome> createState() => _RecordWorkspaceChromeState();
}

class _RecordWorkspaceChromeState extends State<RecordWorkspaceChrome>
    with TickerProviderStateMixin {
  // Narrow layout: Form / Timeline / Attachments as three peer tabs.
  late final TabController _tabs;
  // Wide layout: the side panel carries Timeline / Attachments as two sub-tabs
  // while the form owns the main area.
  late final TabController _sideTabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _sideTabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _sideTabs.dispose();
    super.dispose();
  }

  Widget _timeline() =>
      DocumentTimelineView(documentId: widget.documentName);

  Widget _attachments() => AttachmentsPanel(
        documentId: widget.documentName,
        docType: widget.docTypeName,
      );

  @override
  Widget build(BuildContext context) {
    // Base the side-panel breakpoint on the record chrome's OWN width, not the
    // window. In constrained shells (the medium rail shell, the /list
    // ResponsiveSplit detail pane) the record pane is narrower than the window,
    // so MediaQuery would pick the wide layout — and the fixed 320px side panel
    // would cramp or overflow the form — even though the pane can't fit it.
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _kSidePanelMinWidth;
        return Scaffold(
          appBar: AtlasHeader(
            title: widget.documentName ?? 'New ${widget.docTypeName}',
            actions: [
              PrintRecordButton(
                docType: widget.docTypeName,
                documentId: widget.documentName,
              ),
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'Customize fields',
                onPressed: () => showCustomizeFieldsDialog(
                  context,
                  docTypeName: widget.docTypeName,
                ),
              ),
            ],
            // On wide panes the timeline/attachments live in the side panel, so
            // the main tab bar collapses to just the form (i.e. no tab bar).
            bottom: wide
                ? null
                : AtlasTabs(
                    controller: _tabs,
                    labels: const ['Form', 'Timeline', 'Attachments'],
                  ),
          ),
          body: Column(
            children: [
              CommandBarView(
                docTypeName: widget.docTypeName,
                documentName: widget.documentName,
                isDirty: widget.isDirty,
                isSaving: widget.isSaving,
                isSubmittable: widget.isSubmittable,
                docStatus: widget.docStatus,
                onSave: widget.onSave,
                onSubmit: widget.onSubmit,
                onCancel: widget.onCancel,
                onAmend: widget.onAmend,
                error: widget.error,
                extraActions: widget.extraActions,
              ),
              Expanded(child: wide ? _wideBody(context) : _tabbedBody()),
            ],
          ),
        );
      },
    );
  }

  Widget _tabbedBody() => TabBarView(
        controller: _tabs,
        children: [widget.child, _timeline(), _attachments()],
      );

  Widget _wideBody(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: widget.child),
        VerticalDivider(width: 1, color: theme.dividerColor),
        SizedBox(
          width: _kSidePanelWidth,
          child: Column(
            children: [
              Material(
                color: theme.colorScheme.surfaceContainerLow,
                child: AtlasTabs(
                  controller: _sideTabs,
                  labels: const ['Timeline', 'Attachments'],
                ),
              ),
              Divider(height: 1, color: theme.dividerColor),
              Expanded(
                child: TabBarView(
                  controller: _sideTabs,
                  children: [_timeline(), _attachments()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

