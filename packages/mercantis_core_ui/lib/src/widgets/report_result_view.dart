import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mercantis_core/mercantis_core.dart';

import 'erp_data_table.dart';

const _numericTypes = {'currency', 'float', 'number', 'decimal', 'percent', 'int', 'integer'};

/// Renders a [ReportResult] as a scrollable table with a "Copy CSV" action.
/// Composable: drop it into any Scaffold body (it expands to fill height).
class ReportResultView extends StatelessWidget {
  const ReportResultView({super.key, required this.result});

  final ReportResult result;

  @override
  Widget build(BuildContext context) {
    if (result.isEmpty) {
      return const Center(child: Text('No data for this report yet'));
    }
    final columns = [
      for (final c in result.columns)
        ErpDataColumn(label: c.label, numeric: _numericTypes.contains(c.type)),
    ];
    final rows = [
      for (final row in result.rows)
        ErpDataRow(cells: [for (final cell in row) Text(cell ?? '—')]),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(child: Text(result.name, style: Theme.of(context).textTheme.titleMedium)),
              TextButton.icon(
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('Copy CSV'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: result.toCsv()));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Report copied as CSV')),
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(child: ErpDataTable(columns: columns, rows: rows)),
      ],
    );
  }
}
