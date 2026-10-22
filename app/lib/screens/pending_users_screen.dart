import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../models/auth.dart';
import '../services/auth_service.dart';

/// Admin-only pending-registration queue — GET /auth/pending-users plus the
/// approve/reject actions (api/app/api/routes/auth.py admin_router).
///
/// Visible to every signed-in user, same as the rest of HomeShell's tabs
/// (see home_shell.dart's own comment on this) — there is no client-side
/// role gating. A non-Admin caller simply gets require_admin's 403 back as
/// an ApiException, which this screen surfaces like any other API error.
///
/// There is no backend endpoint yet to list a company's roles, so approval
/// asks the admin to type the numeric role_id directly — the same stand-in
/// pattern already used for company_id elsewhere in this app (login/register
/// screens) until a proper roles-lookup endpoint exists.
class PendingUsersScreen extends StatefulWidget {
  const PendingUsersScreen({super.key});

  @override
  State<PendingUsersScreen> createState() => _PendingUsersScreenState();
}

class _PendingUsersScreenState extends State<PendingUsersScreen> {
  late Future<List<PendingUser>> _future;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<PendingUser>> _load() async {
    setState(() => _error = null);
    try {
      return await AuthService.instance.listPendingUsers();
    } on ApiException catch (e) {
      setState(() => _error = e.detail);
      return [];
    }
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  Future<void> _approve(PendingUser user) async {
    final roleId = await _promptForInt(
      title: 'Approve ${user.fullName}',
      label: 'Role ID',
      helperText: 'The numeric id of the role to assign this user.',
      confirmLabel: 'Approve',
    );
    if (roleId == null) return;
    try {
      await AuthService.instance.approvePendingUser(user.companyUserId, roleId);
      _refresh();
    } on ApiException catch (e) {
      _showError(e.detail);
    }
  }

  Future<void> _reject(PendingUser user) async {
    final reason = await _promptForText(
      title: 'Reject ${user.fullName}',
      label: 'Reason (optional)',
      confirmLabel: 'Reject',
    );
    if (reason == _cancelledSentinel) return;
    try {
      await AuthService.instance.rejectPendingUser(
        user.companyUserId,
        reason: (reason == null || reason.isEmpty) ? null : reason,
      );
      _refresh();
    } on ApiException catch (e) {
      _showError(e.detail);
    }
  }

  void _showError(String detail) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail)));
  }

  static const _cancelledSentinel = '__cancelled__';

  Future<int?> _promptForInt({
    required String title,
    required String label,
    required String confirmLabel,
    String? helperText,
  }) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: label, helperText: helperText),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required.';
              if (int.tryParse(v.trim()) == null) return 'Must be a number.';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(dialogContext).pop(int.parse(controller.text.trim()));
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptForText({
    required String title,
    required String label,
    required String confirmLabel,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(_cancelledSentinel),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? _cancelledSentinel;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Approvals'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<PendingUser>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_error != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              );
            }
            final users = snapshot.data ?? [];
            if (users.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No pending registrations.')),
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: users.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final user = users[index];
                return ListTile(
                  title: Text(user.fullName),
                  subtitle: Text(
                    '${user.email}\n'
                    '${user.userType == UserType.employee ? "Employee" : "Non-employee"} · '
                    'Registered ${user.createdAt.toLocal()}',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Approve',
                        icon: const Icon(Icons.check_circle, color: Colors.green),
                        onPressed: () => _approve(user),
                      ),
                      IconButton(
                        tooltip: 'Reject',
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        onPressed: () => _reject(user),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
