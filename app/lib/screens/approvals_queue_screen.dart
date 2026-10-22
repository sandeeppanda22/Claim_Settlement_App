import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../models/approval.dart';
import '../services/approval_service.dart';

/// GET /approvals/pending — this user's own approval queue. Tapping a row
/// opens the decide dialog with the three outcomes the backend accepts:
/// APPROVED / REJECTED / RETURNED_FOR_REVISION (api/app/schemas/approval.py
/// ApprovalDecisionIn). A cleared/rejected/returned claim drops out of this
/// list on refresh — it's not anyone's queue item anymore.
class ApprovalsQueueScreen extends StatefulWidget {
  const ApprovalsQueueScreen({super.key});

  @override
  State<ApprovalsQueueScreen> createState() => _ApprovalsQueueScreenState();
}

class _ApprovalsQueueScreenState extends State<ApprovalsQueueScreen> {
  late Future<List<PendingApproval>> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _future = ApprovalService.instance.myPendingQueue();
  }

  Future<void> _decide(PendingApproval item) async {
    final commentController = TextEditingController();
    final decision = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.claimTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: commentController,
              decoration: const InputDecoration(labelText: 'Comment (optional)'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'RETURNED_FOR_REVISION'),
            child: const Text('Return'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'REJECTED'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'APPROVED'),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (decision == null) return;

    try {
      await ApprovalService.instance.decide(
        item.claimId,
        decision,
        comment: commentController.text.trim().isEmpty ? null : commentController.text.trim(),
      );
      setState(_refresh);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.detail)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Approvals')),
      body: RefreshIndicator(
        onRefresh: () async => setState(_refresh),
        child: FutureBuilder<List<PendingApproval>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              final message = snapshot.error is ApiException
                  ? (snapshot.error as ApiException).detail
                  : snapshot.error.toString();
              return Center(child: Text(message, style: const TextStyle(color: Colors.red)));
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return const Center(child: Text('Nothing waiting on your decision.'));
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final item = items[i];
                return ListTile(
                  title: Text(item.claimTitle),
                  subtitle: Text(
                    'Level ${item.levelNumber} · '
                    '${NumberFormat.currency(symbol: '${item.claimCurrencyCode} ').format(item.totalAmount)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _decide(item),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
