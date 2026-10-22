import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../models/auth.dart';
import '../services/auth_service.dart';
import 'home_shell.dart';
import 'register_screen.dart';

/// Real sign-in, replacing the dev-login JWT-paste stand-in (see
/// screens/dev_login_screen.dart, now unused). Mirrors api/app/schemas/
/// auth.py LoginRequest: user_type, email, password, and company_id (only
/// required for NON_EMPLOYEE — an EMPLOYEE's company is resolved server-side
/// from the email domain via company_email_domain).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _companyIdController = TextEditingController();

  UserType _userType = UserType.employee;
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await AuthService.instance.login(
        userType: _userType,
        email: _emailController.text.trim(),
        password: _passwordController.text,
        companyId: _userType == UserType.nonEmployee
            ? int.parse(_companyIdController.text.trim())
            : null,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<UserType>(
                    segments: const [
                      ButtonSegment(value: UserType.employee, label: Text('Employee')),
                      ButtonSegment(value: UserType.nonEmployee, label: Text('Non-employee')),
                    ],
                    selected: {_userType},
                    onSelectionChanged: (s) => setState(() => _userType = s.first),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Email is required.' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Password is required.' : null,
                  ),
                  if (_userType == UserType.nonEmployee) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _companyIdController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Company ID',
                        helperText: 'Given to you by the company you are claiming against.',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Company ID is required.';
                        if (int.tryParse(v.trim()) == null) return 'Must be a number.';
                        return null;
                      },
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign in'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const RegisterScreen()),
                            ),
                    child: const Text("Don't have an account? Register"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
