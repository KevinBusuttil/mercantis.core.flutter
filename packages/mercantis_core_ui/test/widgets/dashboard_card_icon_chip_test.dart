import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Phase 5 core polish: the KPI / list / dashboard cards used to hand-roll their
/// tinted leading icon-chip Container. They now delegate to the shared
/// [AtlasIconChip]. These pin that collapse so the chip can't drift back to a
/// bespoke Container.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: MercantisTheme.light(),
        home: Scaffold(body: child),
      );

  testWidgets('KpiCard renders its leading glyph via AtlasIconChip',
      (tester) async {
    await tester.pumpWidget(wrap(const KpiCard(
      title: 'Sales',
      value: '1,234',
      icon: Icons.trending_up,
      accentColor: Color(0xFF3355FF),
    )));
    expect(find.byType(AtlasIconChip), findsOneWidget);
    expect(find.byIcon(Icons.trending_up), findsOneWidget);
  });

  testWidgets('ListCard renders its leading glyph via AtlasIconChip',
      (tester) async {
    await tester.pumpWidget(wrap(const ListCard(
      title: 'Recent',
      icon: Icons.receipt_long,
      rows: [],
    )));
    expect(find.byType(AtlasIconChip), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long), findsOneWidget);
  });

  testWidgets('DashboardCard renders its leading glyph via AtlasIconChip',
      (tester) async {
    await tester.pumpWidget(wrap(const DashboardCard(
      title: 'Approvals',
      icon: Icons.rule,
      child: SizedBox.shrink(),
    )));
    expect(find.byType(AtlasIconChip), findsOneWidget);
    expect(find.byIcon(Icons.rule), findsOneWidget);
  });
}
