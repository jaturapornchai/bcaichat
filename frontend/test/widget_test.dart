import 'package:bcaichat_app/main.dart';
import 'package:bcaichat_app/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('BC Ai Chat app & LoginScreen render Ban Chiang & 5 Demo cards', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BCAiChatApp());
    expect(find.byType(BCAiChatApp), findsOneWidget);

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(onLoggedIn: (_) {}),
      ),
    );
    await tester.pump();

    expect(find.text('BC Ai Chat'), findsWidgets);
    expect(find.textContaining('ลุงจืด'), findsWidgets);
    for (var i = 1; i <= 5; i++) {
      expect(find.textContaining('demo$i@bcaichat.local'), findsOneWidget);
    }
    expect(find.textContaining('Server URL:'), findsOneWidget);
  });
}
