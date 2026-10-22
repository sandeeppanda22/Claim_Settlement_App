import '../core/api_client.dart';
import '../models/approval.dart';

/// Wraps api/app/api/routes/approvals.py.
/// `decision` is one of 'APPROVED' | 'REJECTED' | 'RETURNED_FOR_REVISION' —
/// the backend's ApprovalDecisionIn enum is the source of truth; this layer
/// doesn't duplicate it as a Dart enum to avoid drift if the backend adds
/// a value later.
class ApprovalService {
  ApprovalService._();
  static final ApprovalService instance = ApprovalService._();

  final _api = ApiClient.instance;

  Future<ClaimApprovalState> submit(String claimId) async {
    final json = await _api.post('/claims/$claimId/submit');
    return ClaimApprovalState.fromJson(json as Map<String, dynamic>);
  }

  Future<ClaimApprovalState> resubmit(String claimId) async {
    final json = await _api.post('/claims/$claimId/resubmit');
    return ClaimApprovalState.fromJson(json as Map<String, dynamic>);
  }

  Future<ClaimApprovalState> decide(
    String claimId,
    String decision, {
    String? comment,
  }) async {
    final json = await _api.post(
      '/claims/$claimId/decide',
      body: {'decision': decision, 'comment': comment},
    );
    return ClaimApprovalState.fromJson(json as Map<String, dynamic>);
  }

  Future<List<PendingApproval>> myPendingQueue() async {
    final json = await _api.get('/approvals/pending');
    return (json as List<dynamic>)
        .map((e) => PendingApproval.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
