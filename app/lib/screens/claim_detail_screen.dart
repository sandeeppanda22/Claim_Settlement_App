import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../models/claim.dart';
import '../services/approval_service.dart';
import '../services/claim_service.dart';
import '../widgets/payment_section.dart';
import '../widgets/status_badge.dart';

/// GET /claims/{id}, plus whichever of submit/resubmit/Finance actions the
/// claim's current status allows. Decide (approve/reject/return) lives in
/// ApprovalsQueueScreen instead — that's the approver's own queue, not
/// this claimant-facing detail view.
class ClaimDetailScreen extends StatefulWidget {
  final String claimId;
  const ClaimDetailScreen({super.key, required this.claimId});

  @override
  State<ClaimDetailScreen> createState() => _ClaimDetailScreenState();
}

class _ClaimDetailScreenState extends State<ClaimDetailScreen> {
  late Future<Claim> _future;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = ClaimService.instance.getClaim(widget.claimId);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      setState(_load);
    } on ApiException catch (e) {
      setState(() => _error = e.detail);
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Claim')),
      body: FutureBuilder<Claim>(
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
          final claim = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(claim.title, style: Theme.of(context).textTheme.titleLarge)),
                  StatusBadge(status: claim.status),
                ],
              ),
              if (claim.description != null) Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(claim.description!),
              ),
              const SizedBox(height: 12),
              Text(
                'Total: ${NumberFormat.currency(symbol: '${claim.claimCurrencyCode} ').format(claim.totalAmount)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('Line items', style: TextStyle(fontWeight: FontWeight.bold)),
              for (final item in claim.lineItems)
                ListTile(
                  dense: true,
                  title: Text(item.category),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(item.expenseDate)),
                  trailing: Text(item.amount.toStringAsFixed(2)),
                ),
              const SizedBox(height: 16),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              if (claim.status == 'DRAFT')
                FilledButton(
                  onPressed: _busy ? null : () => _run(() => ApprovalService.instance.submit(claim.id)),
                  child: const Text('Submit for Approval'),
                ),
              if (claim.status == 'RETURNED_FOR_REVISION')
                FilledButton(
                  onPressed: _busy ? null : () => _run(() => ApprovalService.instance.resubmit(claim.id)),
                  child: const Text('Resubmit'),
                ),
              PaymentSection(
                claimId: claim.id,
                claimStatus: claim.status,
                onChanged: () => setState(_load),
              ),
            ],
          );
        },
      ),
    );
  }
}
