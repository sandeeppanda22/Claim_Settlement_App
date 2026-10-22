import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_session.dart';

/// Thrown for any non-2xx response. Carries the backend's own
/// human-readable `detail` string straight through — FastAPI's error
/// bodies are already meaningful (BUSINESS_RULES.md "no silent failure"
/// principle extends to the client: never replace a real backend message
/// with a generic "Something went wrong").
class ApiException implements Exception {
  final int statusCode;
  final String detail;
  ApiException(this.statusCode, this.detail);

  @override
  String toString() => detail;
}

/// Thin HTTP wrapper — attaches the bearer token, decodes JSON, and turns
/// non-2xx responses into ApiException with the backend's own detail
/// message. All services (claim_service, approval_service, payment_service)
/// go through this; no raw `http` calls elsewhere.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);

  Future<Map<String, String>> _headers() async {
    final token = await AuthSession.instance.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  dynamic _decode(http.Response response) {
    final body = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }
    final detail = (body is Map && body['detail'] != null)
        ? body['detail'].toString()
        : 'Request failed (${response.statusCode}).';
    throw ApiException(response.statusCode, detail);
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    final response = await http.get(_uri(path, query), headers: await _headers());
    return _decode(response);
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final response = await http.post(
      _uri(path),
      headers: await _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(response);
  }
}
