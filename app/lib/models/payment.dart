/// Mirrors api/app/schemas/payment.py — PaymentOut, ClaimStatusOut.
class Payment {
  final String id;
  final String claimId;
  final String status;
  final String payoutCurrencyCode;
  final double payoutAmount;
  final double? payoutFxRate;
  final String method;
  final String? referenceNumber;
  final int initiatedByUserId;
  final DateTime initiatedAt;
  final DateTime? paidAt;
  final DateTime createdAt;

  Payment({
    required this.id,
    required this.claimId,
    required this.status,
    required this.payoutCurrencyCode,
    required this.payoutAmount,
    this.payoutFxRate,
    required this.method,
    this.referenceNumber,
    required this.initiatedByUserId,
    required this.initiatedAt,
    this.paidAt,
    required this.createdAt,
  });

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: json['id'] as String,
        claimId: json['claim_id'] as String,
        status: json['status'] as String,
        payoutCurrencyCode: json['payout_currency_code'] as String,
        payoutAmount: (json['payout_amount'] as num).toDouble(),
        payoutFxRate: (json['payout_fx_rate'] as num?)?.toDouble(),
        method: json['method'] as String,
        referenceNumber: json['reference_number'] as String?,
        initiatedByUserId: json['initiated_by_user_id'] as int,
        initiatedAt: DateTime.parse(json['initiated_at'] as String),
        paidAt: json['paid_at'] == null ? null : DateTime.parse(json['paid_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class ClaimStatus {
  final String claimId;
  final String status;
  ClaimStatus({required this.claimId, required this.status});

  factory ClaimStatus.fromJson(Map<String, dynamic> json) =>
      ClaimStatus(claimId: json['claim_id'] as String, status: json['status'] as String);
}
