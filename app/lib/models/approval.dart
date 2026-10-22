/// Mirrors api/app/schemas/approval.py — ClaimApprovalStateOut,
/// PendingApprovalOut. DecideRequest's enum (APPROVED/REJECTED/
/// RETURNED_FOR_REVISION) is passed as a plain String here; the backend
/// is the single source of truth for valid values, no duplicate enum to
/// drift out of sync.
class ClaimApprovalState {
  final String claimId;
  final String status;
  final int? currentLevelId;
  final int? currentLevelNumber;

  ClaimApprovalState({
    required this.claimId,
    required this.status,
    this.currentLevelId,
    this.currentLevelNumber,
  });

  factory ClaimApprovalState.fromJson(Map<String, dynamic> json) => ClaimApprovalState(
        claimId: json['claim_id'] as String,
        status: json['status'] as String,
        currentLevelId: json['current_level_id'] as int?,
        currentLevelNumber: json['current_level_number'] as int?,
      );
}

/// One row in GET /approvals/pending — a claim awaiting this user's decision.
class PendingApproval {
  final int stepId;
  final String claimId;
  final String claimTitle;
  final int claimTypeId;
  final double totalAmount;
  final String claimCurrencyCode;
  final int levelId;
  final int levelNumber;
  final DateTime? submittedAt;

  PendingApproval({
    required this.stepId,
    required this.claimId,
    required this.claimTitle,
    required this.claimTypeId,
    required this.totalAmount,
    required this.claimCurrencyCode,
    required this.levelId,
    required this.levelNumber,
    this.submittedAt,
  });

  factory PendingApproval.fromJson(Map<String, dynamic> json) => PendingApproval(
        stepId: json['step_id'] as int,
        claimId: json['claim_id'] as String,
        claimTitle: json['claim_title'] as String,
        claimTypeId: json['claim_type_id'] as int,
        totalAmount: (json['total_amount'] as num).toDouble(),
        claimCurrencyCode: json['claim_currency_code'] as String,
        levelId: json['level_id'] as int,
        levelNumber: json['level_number'] as int,
        submittedAt: json['submitted_at'] == null
            ? null
            : DateTime.parse(json['submitted_at'] as String),
      );
}
