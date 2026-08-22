import 'package:bastak_leads/ui/widgets/brand_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpLogo(WidgetTester tester, Widget logo,
      {Brightness brightness = Brightness.light}) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: Center(child: logo)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('all brand logo variants render without error (light)',
      (tester) async {
    for (final logo in const [
      BrandLogo.horizontal(height: 40),
      BrandLogo.stacked(height: 80),
      BrandLogo.mark(height: 40),
    ]) {
      await pumpLogo(tester, logo);
      expect(tester.takeException(), isNull);
      expect(find.byType(BrandLogo), findsOneWidget);
    }
  });

  testWidgets('dark mode selects the white knockout logo without error',
      (tester) async {
    await pumpLogo(tester, const BrandLogo.horizontal(height: 40),
        brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
  });
}
