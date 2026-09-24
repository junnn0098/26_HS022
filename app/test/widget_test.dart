import 'package:flutter_test/flutter_test.dart';
import 'package:hanium_app/app/hanium_app.dart';

void main() {
  testWidgets('role selection screen is shown', (tester) async {
    await tester.pumpWidget(const HaniumApp());

    expect(find.text('한이음 어플'), findsOneWidget);
    expect(find.text('사용할 모드를 선택하세요'), findsOneWidget);
    expect(find.text('보호자'), findsOneWidget);
    expect(find.text('피보호자'), findsOneWidget);
  });
}
