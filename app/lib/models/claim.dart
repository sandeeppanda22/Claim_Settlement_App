/// Mirrors api/app/schemas/claim.py — ClaimLineItemCreate/Out, ClaimCreate,
/// ClaimOut. Field names and nullability match the backend 1:1 so JSON
/// round-trips without translation layers.
class ClaimLineItem {
  final String? id; // null for a not-yet-synced offline draft line
  final int lineNumber;
  final DateTime expenseDate;
  final String category;
  final String? description;
  final double amount;
  final Map<String, dynamic>? fieldValues;

  ClaimLineItem({
    this.id,
    required this.lineNumber,
    required this.expenseDate,
    required this.category,
    this.description,
    required this.amount,
    this.fieldValues,
  });

  factory ClaimLineItem.fromJson(Map<String, dynamic> json) => ClaimLineItem(
        id: json['id'] as String?,
        lineNumber: json['line_number'] as int,
        expenseDate: DateTime.parse(json['expense_date'] as String),
        category: json['category'] as String,
        description: json['description'] as String?,
        amount: (json['amount'] as num).toDouble(),
        fieldValues: json['field_values'] as Map<String, dynamic>?,
      );

  /// For POST /claims — only the fields ClaimLineItemCreate accepts.
  Map<String, dynamic> toCreateJson() => {
        'line_number': lineNumber,
        'expense_date': expenseDate.toIso8601String().split('T').first,
        'category': category,
        'description': description,
        'amount': amount,
        'field_values': fieldValues,
      };
}

class Claim {
  final String id;
  final int companyId;
  final int claimTypeId;
  final int companyUserId;
  final String status;
  final String title;
  final String? description;
  final String claimCurrencyCode;
  final double? fxRateToBase;
  final String? baseCurrencyCode;
  final double totalAmount;
  final int? currentLevelId;
  final DateTime? submittedAt;
  final DateTime createdAt;
  final List<ClaimLineItem> lineItems;

  Claim({
    required this.id,
    required this.companyId,
    required this.claimTypeId,
    required this.companyUserId,
    required this.status,
    required this.title,
    this.description,
    required this.claimCurrencyCode,
    this.fxRateToBase,
    this.baseCurrencyCode,
    required this.totalAmount,
    this.currentLevelId,
    this.submittedAt,
    required this.createdAt,
    this.lineItems = const [],
  });

  factory Claim.fromJson(Map<String, dynamic> json) => Claim(
        id: json['id'] as String,
        companyId: json['company_id'] as int,
        claimTypeId: json['claim_type_id'] as int,
        companyUserId: json['company_user_id'] as int,
        status: json['status'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        claimCurrencyCode: json['claim_currency_code'] as String,
        fxRateToBase: (json['fx_rate_to_base'] as num?)?.toDouble(),
        baseCurrencyCode: json['base_currency_code'] as String?,
        totalAmount: (json['total_amount'] as num).toDouble(),
        currentLevelId: json['current_level_id'] as int?,
        submittedAt: json['submitted_at'] == null
            ? null
            : DateTime.parse(json['submitted_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        lineItems: (json['line_items'] as List<dynamic>? ?? [])
            .map((e) => ClaimLineItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// For POST /claims. `id` is included (nullable) so an offline-minted draft
/// keeps the same UUID through sync — the server honors a client-supplied
/// id via COALESCE($1, gen_random_uuid()) (see api/app/api/routes/claims.py).
class ClaimDraft {
  final String? id;
  final int claimTypeId;
  final String title;
  final String? description;
  final String claimCurrencyCode;
  final List<ClaimLineItem> lineItems;

  ClaimDraft({
    this.id,
    required this.claimTypeId,
    required this.title,
    this.description,
    required this.claimCurrencyCode,
    this.lineItems = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'claim_type_id': claimTypeId,
        'title': title,
        'description': description,
        'claim_currency_code': claimCurrencyCode,
        'line_items': lineItems.map((e) => e.toCreateJson()).toList(),
      };
}
