import 'package:flutter/material.dart';

import 'approvals_queue_screen.dart';
import 'claims_list_screen.dart';
import 'pending_users_screen.dart';

/// Bottom-nav shell: Claims (claimant view), Approvals (approver view), and
/// Pending Approvals (admin's user-registration queue). All three tabs are
/// visible to every signed-in user for v1 — there's no role-based UI gating
/// yet (mirrors the backend, which doesn't enforce RBAC on these routes
/// either; see api/app/api/routes/payments.py docstring for the same gap
/// called out server-side). For Pending Approvals specifically, a non-Admin
/// caller gets require_admin's 403 back as an ApiException, surfaced inline
/// by PendingUsersScreen.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = [
    ClaimsListScreen(),
    ApprovalsQueueScreen(),
    PendingUsersScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'My Claims'),
          NavigationDestination(icon: Icon(Icons.fact_check), label: 'Approvals'),
          NavigationDestination(icon: Icon(Icons.how_to_reg), label: 'Pending Approvals'),
        ],
      ),
    );
  }
}
