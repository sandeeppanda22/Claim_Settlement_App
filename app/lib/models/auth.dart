/// Mirrors api/app/schemas/auth.py — UserTypeIn, RegisterRequest/Response,
/// LoginRequest, TokenResponse, PendingUserOut, ApproveRequest, RejectRequest,
/// RejectedUserOut. Field names match the backend 1:1.
enum UserType { employee, nonEmployee }

extension UserTypeJson on UserType {
  String toJson() => this == UserType.employee ? 'EMPLOYEE' : 'NON_EMPLOYEE';

  static UserType fromJson(String value) =>
      value == 'EMPLOYEE' ? UserType.employee : UserType.nonEmployee;
}

/// Returned by POST /auth/register — account exists but is PENDING, no
/// token issued yet (see auth.py register()).
class RegisterResult {
  final int companyUserId;
  final int companyId;
  final String approvalStatus;

  RegisterResult({
    required this.companyUserId,
    required this.companyId,
    required this.approvalStatus,
  });

  factory RegisterResult.fromJson(Map<String, dynamic> json) => RegisterResult(
        companyUserId: json['company_user_id'] as int,
        companyId: json['company_id'] as int,
        approvalStatus: json['approval_status'] as String,
      );
}

/// One row in a company Admin's pending-registration queue
/// (GET /auth/pending-users).
class PendingUser {
  final int companyUserId;
  final String fullName;
  final String email;
  final UserType userType;
  final DateTime createdAt;

  PendingUser({
    required this.companyUserId,
    required this.fullName,
    required this.email,
    required this.userType,
    required this.createdAt,
  });

  factory PendingUser.fromJson(Map<String, dynamic> json) => PendingUser(
        companyUserId: json['company_user_id'] as int,
        fullName: json['full_name'] as String,
        email: json['email'] as String,
        userType: UserTypeJson.fromJson(json['user_type'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
