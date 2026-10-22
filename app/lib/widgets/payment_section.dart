import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../models/payment.dart';
import '../services/payment_service.dart';

/// Finance-side actions for one claim — Approved -> Pending Finance Review
/// -> Payment Initiated -> Reimbursed -> Closed. Shown inline on
/// ClaimDetailScreen rather than a separate screen since the whole
/// lifecycle is short and claim-scoped. No role gating here, matching the
/// backend (api/app/api/routes/payments.py) — not invented client-side
/// either.
class PaymentSection extends StatefulWidget {
  final String claimId;
  final String claimStatus;
  final VoidCallback onChanged;

  const PaymentSection({
    super.key,
    required this.claimId,
    required this.claimStatus,
    required this.onChanged,
  });

  @override
  State<PaymentSection> createState() => _PaymentSectionState();
}

class _PaymentSectionState extends State<PaymentSection> {
  final _service = PaymentService.instance;
  List<Payment> _payments = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.claimStatus == 'PAYMENT_INITIATED' || widget.claimStatus == 'REIMBURSED') {
      _loadPayments();
    }
  }

  Future<void> _loadPayments() async {
    final payments = await _service.listPayments(widget.claimId);
    setState(() => _payments = payments);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      widget.onChanged();
    } on ApiException catch (e) {
      setState(() => _error = e.detail);
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _initiatePayment() async {
    final amountController = TextEditingController();
    final methodController = TextEditingController(text: 'BANK_TRANSFER');
    final currencyController = TextEditingController(text: 'USD');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Initiate Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: amountController, decoration: const InputDecoration(labelText: 'Payout amount')),
            TextField(controller: currencyController, decoration: const InputDecoration(labelText: 'Payout currency')),
            TextField(controller: methodController, decoration: const InputDecoration(labelText: 'Method')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Initiate')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => _service.initiatePayment(
          widget.claimId,
          payoutCurrencyCode: currencyController.text.trim().toUpperCase(),
          payoutAmount: double.tryParse(amountController.text) ?? 0,
          method: methodController.text.trim(),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.claimStatus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        if (status == 'APPROVED')
          FilledButton.tonal(
            onPressed: _busy ? null : () => _run(() => _service.startFinanceReview(widget.claimId)),
            child: const Text('Start Finance Review'),
          ),
        if (status == 'PENDING_FINANCE_REVIEW')
          FilledButton.tonal(
            onPressed: _busy ? null : _initiatePayment,
            child: const Text('Initiate Payment'),
          ),
        if (status == 'PAYMENT_INITIATED' || status == 'REIMBURSED')
          for (final p in _payments)
            Card(
              child: ListTile(
                title: Text('${p.payoutCurrencyCode} ${p.payoutAmount.toStringAsFixed(2)} · ${p.method}'),
                subtitle: Text('Status: ${p.status}'),
                trailing: p.status == 'INITIATED'
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.green),
                            onPressed: _busy
                                ? null
                                : () => _run(() async {
                                      await _service.markPaid(widget.claimId, p.id);
                                      await _loadPayments();
                                    }),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: _busy
                                ? null
                                : () => _run(() async {
                                      await _service.markFailed(widget.claimId, p.id);
                                      await _loadPayments();
                                    }),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
        if (status == 'REIMBURSED')
          FilledButton.tonal(
            onPressed: _busy ? null : () => _run(() => _service.closeClaim(widget.claimId)),
            child: const Text('Close Claim'),
          ),
      ],
    );
  }
}
