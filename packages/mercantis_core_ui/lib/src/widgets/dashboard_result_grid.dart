import 'package:flutter/material.dart';
import 'package:mercantis_core/mercantis_core.dart';

import 'dashboard_card.dart';
import 'kpi_card.dart';
import 'list_card.dart';

/// Renders a resolved [DashboardResult] as a responsive grid of tiles — KPIs
/// (count/sum), lists, shortcuts and mini chart tables — with per-widget error
/// isolation. Composable: place in any scrollable-friendly parent.
class DashboardResultGrid extends StatelessWidget {
  const DashboardResultGrid({super.key, required this.result, this.onShortcut});

  final DashboardResult result;
  final void Function(String route)? onShortcut;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width > 640;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [for (final w in result.widgets) _tile(context, w, wide)],
      ),
    );
  }

  Widget _tile(BuildContext context, DashboardWidgetResult w, bool wide) {
    final small = wide ? 240.0 : double.infinity;
    final large = wide ? 380.0 : double.infinity;

    if (w.isError) {
      return SizedBox(
        width: small,
        child: DashboardCard(
          title: w.label,
          child: Text(w.error ?? 'Failed', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      );
    }

    switch (w.type) {
      case 'count':
        return SizedBox(width: small, child: KpiCard(title: w.label, value: '${w.count ?? 0}'));
      case 'sum':
        return SizedBox(width: small, child: KpiCard(title: w.label, value: w.display ?? '${w.total ?? 0}'));
      case 'list':
        return SizedBox(
          width: large,
          child: ListCard(
            title: w.label,
            rows: [for (final m in w.rows ?? const <Map<String, String?>>[]) _row(m)],
          ),
        );
      case 'shortcut':
        return SizedBox(
          width: small,
          child: DashboardCard(
            title: w.label,
            onTap: (w.route != null && onShortcut != null) ? () => onShortcut!(w.route!) : null,
            child: const Text('Open'),
          ),
        );
      case 'chart':
        return SizedBox(
          width: large,
          child: DashboardCard(
            title: w.label,
            child: w.chart == null ? const SizedBox.shrink() : _miniTable(w.chart!),
          ),
        );
      default:
        return SizedBox(width: small, child: DashboardCard(title: w.label, child: const SizedBox.shrink()));
    }
  }

  ListCardRow _row(Map<String, String?> m) {
    final values = [for (final v in m.values) if (v != null && v.isNotEmpty) v];
    return ListCardRow(
      title: values.isEmpty ? '—' : values.first,
      subtitle: values.length > 1 ? values.sublist(1).join(' · ') : null,
    );
  }

  Widget _miniTable(ReportResult r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in r.rows.take(5))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(row.map((c) => c ?? '').join('  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }
}
