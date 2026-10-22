// Smoke test — confirms the app boots to the real sign-in gate (no stored
// token at test start, per core/auth_session.dart's AuthSession.isLoggedIn
// future checked by main.dart's _StartupGate) without throwing. Real
// screen-level tests belong per-screen once the UI stabilizes; this just
// guards main.dart wiring.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:claim_settlement_app/main.dart';
import 'package:claim_settlement_app/screens/login_screen.dart';

void main() {
  testWidgets('App boots to the sign-in screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ClaimSettlementApp());
    await tester.pumpAndSettle();

    // _StartupGate's FutureBuilder resolves to false (no stored JWT) and
    // renders LoginScreen (screens/login_screen.dart), not HomeShell.
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Sign in'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
