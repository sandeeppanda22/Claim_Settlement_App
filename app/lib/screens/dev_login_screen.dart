import 'package:flutter/material.dart';

import '../core/auth_session.dart';
import 'home_shell.dart';

/// Stand-in for real login. api/app/core/security.py only verifies a JWT
/// today — nothing on the backend issues one yet (no /auth/login route
/// exists). Until that slice is built, this screen lets you paste a token
/// minted some other way (e.g. a short-lived test JWT signed with the same
/// JWT_SECRET as your local .env) so the rest of the app is testable.
/// Replace this screen's body, not its purpose, once real login exists —
/// everything downstream only ever reads the token via AuthSession.
class DevLoginScreen extends StatefulWidget {
  const DevLoginScreen({super.key});

  @override
  State<DevLoginScreen> createState() => _DevLoginScreenState();
}

class _DevLoginScreenState extends State<DevLoginScreen> {
  final _tokenController = TextEditingController();
  bool _saving = false;

  Future<void> _save() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) return;
    setState(() => _saving = true);
    await AuthSession.instance.setToken(token);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dev sign-in')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No login endpoint exists on the backend yet. Paste a JWT '
              '(matching api/app/core/config.py JWT_SECRET/JWT_ALGORITHM, '
              'claims: sub, company_id, role_id, email) to use the app '
              'against your local API.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tokenController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'JWT',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
