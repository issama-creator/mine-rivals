import 'package:flutter_test/flutter_test.dart';
import 'package:mineriv/main.dart';

void main() {
  testWidgets('Mine Rivals boots to menu', (tester) async {
    await tester.pumpWidget(const MineRivalsApp());
    expect(find.text('RIVALS'), findsOneWidget);
    expect(find.text('НАЧАТЬ ИГРУ'), findsOneWidget);
    expect(find.text('НАСТРОЙКИ'), findsOneWidget);
  });
}
