import '../core/api_client.dart';
import '../models/claim_type.dart';

/// Wraps api/app/api/routes/claim_types.py — list only, for v1 of the
/// claimant-facing app (authoring claim types is a separate admin surface).
class ClaimTypeService {
  ClaimTypeService._();
  static final ClaimTypeService instance = ClaimTypeService._();

  final _api = ApiClient.instance;

  Future<List<ClaimType>> listClaimTypes() async {
    final json = await _api.get('/claim-types');
    return (json as List<dynamic>)
        .map((e) => ClaimType.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
