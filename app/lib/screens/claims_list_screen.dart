import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../models/claim.dart';
import '../services/claim_service.dart';
import '../widgets/status_badge.dart';
import 'claim_detail_screen.dart';
import 'new_claim_screen.dart';

/// GET /claims — this user's own claims only (claims.py explicitly scopes
/// it that way for v1). Pull-to-refresh since claim status changes
/// server-side (an approver deciding) without this screen knowing.
class ClaimsListScreen extends StatefulWidget {
  const ClaimsListScreen({super.key});

  @override
  State<ClaimsListScreen> createState() => _ClaimsListScreenState();
}

class _ClaimsListScreenState extends State<ClaimsListScreen> {
  late Future<List<Claim>> _future;

  @override
  void initState() {
    super.initState();
    _future = ClaimService.instance.listMyClaims();
  }

  Future<void> _refresh() async {
    setState(() => _future = ClaimService.instance.listMyClaims());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Claims')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const NewClaimScreen()),
          );
          if (created == true) _refresh();
        },
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Claim>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              final message = snapshot.error is ApiException
                  ? (snapshot.error as ApiException).detail
                  : snapshot.error.toString();
              return Center(child: Text(message, style: const TextStyle(color: Colors.red)));
            }
            final claims = snapshot.data ?? [];
            if (claims.isEmpty) {
              return const Center(child: Text('No claims yet — tap + to create one.'));
            }
            return ListView.separated(
              itemCount: claims.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final claim = claims[i];
                return ListTile(
                  title: Text(claim.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${NumberFormat.currency(symbol: '${claim.claimCurrencyCode} ').format(claim.totalAmount)}'
                    '  ·  ${claim.lineItems.length} line item(s)',
                  ),
                  trailing: StatusBadge(status: claim.status),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ClaimDetailScreen(claimId: claim.id)),
                    );
                    _refresh();
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
