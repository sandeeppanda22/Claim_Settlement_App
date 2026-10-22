import '../core/api_client.dart';
import '../core/auth_session.dart';
import '../models/auth.dart';

/// Wraps api/app/api/routes/auth.py — register/login are public (no token
/// needed/sent), the pending-users trio are tenant-scoped and admin-only
/// (ApiClient attaches whatever token is already stored; the backend 403s
/// a non-Admin caller — see require_admin in auth.py).
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final _api = ApiClient.instance;

  Future<RegisterResult> register({
    required UserType userType,
    required String fullName,
    required String email,
    required String password,
    int? companyId,
  }) async {
    final json = await _api.post('/auth/register', body: {
      'user_type': userType.toJson(),
      'full_name': fullName,
      'email': email,
      'password': password,
      'company_id': companyId,
    });
    return RegisterResult.fromJson(json as Map<String, dynamic>);
  }

  /// On success, stores the token in AuthSession and returns it — callers
  /// don't need to call AuthSession themselves.
  Future<String> login({
    required UserType userType,
    required String email,
    required String password,
    int? companyId,
  }) async {
    final json = await _api.post('/auth/login', body: {
      'user_type': userType.toJson(),
      'email': email,
      'password': password,
      'company_id': companyId,
    });
    final token = (json as Map<String, dynamic>)['access_token'] as String;
    await AuthSession.instance.setToken(token);
    return token;
  }

  Future<List<PendingUser>> listPendingUsers() async {
    final json = await _api.get('/auth/pending-users');
    return (json as List<dynamic>)
        .map((e) => PendingUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> approvePendingUser(int companyUserId, int roleId) async {
    await _api.post(
      '/auth/pending-users/$companyUserId/approve',
      body: {'role_id': roleId},
    );
  }

  Future<void> rejectPendingUser(int companyUserId, {String? reason}) async {
    await _api.post(
      '/auth/pending-users/$companyUserId/reject',
      body: {'reason': reason},
    );
  }
}
