import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the current session's JWT. Login/token-issuance itself is not yet
/// built on the backend (api/app/core/security.py only verifies a token
/// today — see docs). This class is the client-side slot that flow will
/// write into once it exists; everything else in the app only ever reads
/// the token through here, so wiring real login in later touches one file.
class AuthSession {
  AuthSession._();
  static final AuthSession instance = AuthSession._();

  final _storage = const FlutterSecureStorage();
  static const _tokenKey = 'auth_jwt';

  String? _cachedToken;

  Future<String?> getToken() async {
    _cachedToken ??= await _storage.read(key: _tokenKey);
    return _cachedToken;
  }

  Future<void> setToken(String token) async {
    _cachedToken = token;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> clear() async {
    _cachedToken = null;
    await _storage.delete(key: _tokenKey);
  }

  Future<bool> get isLoggedIn async => (await getToken()) != null;
}
