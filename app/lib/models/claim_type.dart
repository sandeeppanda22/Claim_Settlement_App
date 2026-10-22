/// Mirrors api/app/schemas/claim_type.py — ClaimTypeOut, ClaimTypeFieldOut.
/// Read-only on the client for v1 (claim-type authoring is an admin
/// surface, not part of the claimant-facing app yet).
class ClaimTypeField {
  final int id;
  final String fieldKey;
  final String label;
  final String dataType; // 'text' | 'number' | 'date' | 'boolean' | 'select'
  final bool isRequired;
  final int displayOrder;
  final Map<String, dynamic>? validationRule;
  final double? policyLimitAmount;

  ClaimTypeField({
    required this.id,
    required this.fieldKey,
    required this.label,
    required this.dataType,
    required this.isRequired,
    required this.displayOrder,
    this.validationRule,
    this.policyLimitAmount,
  });

  factory ClaimTypeField.fromJson(Map<String, dynamic> json) => ClaimTypeField(
        id: json['id'] as int,
        fieldKey: json['field_key'] as String,
        label: json['label'] as String,
        dataType: json['data_type'] as String,
        isRequired: json['is_required'] as bool,
        displayOrder: json['display_order'] as int,
        validationRule: json['validation_rule'] as Map<String, dynamic>?,
        policyLimitAmount: (json['policy_limit_amount'] as num?)?.toDouble(),
      );
}

class ClaimType {
  final int id;
  final int companyId;
  final String name;
  final String code;
  final String? description;
  final bool isActive;
  final List<ClaimTypeField> fields;

  ClaimType({
    required this.id,
    required this.companyId,
    required this.name,
    required this.code,
    this.description,
    required this.isActive,
    this.fields = const [],
  });

  factory ClaimType.fromJson(Map<String, dynamic> json) => ClaimType(
        id: json['id'] as int,
        companyId: json['company_id'] as int,
        name: json['name'] as String,
        code: json['code'] as String,
        description: json['description'] as String?,
        isActive: json['is_active'] as bool,
        fields: (json['fields'] as List<dynamic>? ?? [])
            .map((e) => ClaimTypeField.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
