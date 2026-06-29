import 'package:flutter/material.dart';
import '../widgets/attachments_panel.dart';
import '../widgets/document_timeline_view.dart';
import '../widgets/print_record_button.dart';
import 'command_bar_view.dart';
import 'customize_fields_sheet.dart';

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
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.documentName ?? 'New ${widget.docTypeName}'),
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
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Form'),
            Tab(text: 'Timeline'),
            Tab(text: 'Attachments'),
          ],
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
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                widget.child,
                DocumentTimelineView(documentId: widget.documentName),
                AttachmentsPanel(
                  documentId: widget.documentName,
                  docType: widget.docTypeName,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

