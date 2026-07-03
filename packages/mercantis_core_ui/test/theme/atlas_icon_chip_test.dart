import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// The shared tinted icon chip — one source for the glyph square used by field
/// rows and dashboard cards.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('renders the glyph at the default 36×36 size', (tester) async {
    await tester.pumpWidget(wrap(const AtlasIconChip(icon: Icons.inventory_2_outlined)));
    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    final box = tester.getSize(find.byType(AtlasIconChip));
    expect(box.width, 36);
    expect(box.height, 36);
  });

  testWidgets('honours a custom size and accent', (tester) async {
    await tester.pumpWidget(wrap(const AtlasIconChip(
      icon: Icons.percent,
      size: 40,
      accent: Color(0xFF7B5BFF),
    )));
    final icon = tester.widget<Icon>(find.byIcon(Icons.percent));
    expect(icon.color, const Color(0xFF7B5BFF));
    expect(tester.getSize(find.byType(AtlasIconChip)).width, 40);
  });
}
