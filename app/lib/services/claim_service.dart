import '../core/api_client.dart';
import '../models/claim.dart';

/// Wraps api/app/api/routes/claim_types.py and claims.py. One method per
/// endpoint, no business logic here — that lives server-side.
class ClaimService {
  ClaimService._();
  static final ClaimService instance = ClaimService._();

  final _api = ApiClient.instance;

  Future<Claim> createClaim(ClaimDraft draft) async {
    final json = await _api.post('/claims', body: draft.toJson());
    return Claim.fromJson(json as Map<String, dynamic>);
  }

  Future<Claim> getClaim(String claimId) async {
    final json = await _api.get('/claims/$claimId');
    return Claim.fromJson(json as Map<String, dynamic>);
  }

  Future<List<Claim>> listMyClaims() async {
    final json = await _api.get('/claims');
    return (json as List<dynamic>)
        .map((e) => Claim.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
