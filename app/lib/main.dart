import 'package:flutter/material.dart';

import 'core/auth_session.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const ClaimSettlementApp());
}

class ClaimSettlementApp extends StatelessWidget {
  const ClaimSettlementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Claim Settlement',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const _StartupGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Routes to the sign-in screen if no token is stored yet, otherwise
/// straight to the app shell.
class _StartupGate extends StatelessWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AuthSession.instance.isLoggedIn,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data! ? const HomeShell() : const LoginScreen();
      },
    );
  }
}
