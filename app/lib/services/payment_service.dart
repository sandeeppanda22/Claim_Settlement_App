import '../core/api_client.dart';
import '../models/payment.dart';

/// Wraps api/app/api/routes/payments.py — the Finance-side lifecycle:
/// Approved -> Pending Finance Review -> Payment Initiated -> Reimbursed
/// -> Closed. No role gating client-side either; the backend doesn't
/// enforce it yet (see payments.py docstring) so this layer doesn't fake it.
class PaymentService {
  PaymentService._();
  static final PaymentService instance = PaymentService._();

  final _api = ApiClient.instance;

  Future<ClaimStatus> startFinanceReview(String claimId) async {
    final json = await _api.post('/claims/$claimId/finance-review');
    return ClaimStatus.fromJson(json as Map<String, dynamic>);
  }

  Future<Payment> initiatePayment(
    String claimId, {
    required String payoutCurrencyCode,
    required double payoutAmount,
    double? payoutFxRate,
    required String method,
    String? referenceNumber,
  }) async {
    final json = await _api.post(
      '/claims/$claimId/payments',
      body: {
        'payout_currency_code': payoutCurrencyCode,
        'payout_amount': payoutAmount,
        'payout_fx_rate': payoutFxRate,
        'method': method,
        'reference_number': referenceNumber,
      },
    );
    return Payment.fromJson(json as Map<String, dynamic>);
  }

  Future<List<Payment>> listPayments(String claimId) async {
    final json = await _api.get('/claims/$claimId/payments');
    return (json as List<dynamic>)
        .map((e) => Payment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Payment> markPaid(String claimId, String paymentId) async {
    final json = await _api.post('/claims/$claimId/payments/$paymentId/mark-paid');
    return Payment.fromJson(json as Map<String, dynamic>);
  }

  Future<Payment> markFailed(String claimId, String paymentId) async {
    final json = await _api.post('/claims/$claimId/payments/$paymentId/mark-failed');
    return Payment.fromJson(json as Map<String, dynamic>);
  }

  Future<ClaimStatus> closeClaim(String claimId) async {
    final json = await _api.post('/claims/$claimId/close');
    return ClaimStatus.fromJson(json as Map<String, dynamic>);
  }
}
