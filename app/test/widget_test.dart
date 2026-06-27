import 'package:flutter_test/flutter_test.dart';
import 'package:hanium_app/main.dart';

void main() {
  testWidgets('guardian login screen is shown', (tester) async {
    await tester.pumpWidget(const HaniumApp());

    expect(find.text('보호자 로그인'), findsOneWidget);
    expect(find.text('카메라 없이,\n가족의 안전을 확인하세요'), findsOneWidget);
  });
}
