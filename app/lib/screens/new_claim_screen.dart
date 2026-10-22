import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../db/local_draft_db.dart';
import '../models/claim.dart';
import '../models/claim_type.dart';
import '../services/claim_service.dart';
import '../services/claim_type_service.dart';

/// POST /claims. The claim id is minted here, client-side, via uuid —
/// not left for the server — so this same code path works offline:
/// if the request fails because there's no connectivity (anything that
/// isn't an ApiException, i.e. we never got a response), the draft is
/// saved to LocalDraftDb instead and synced later. See ARCHITECTURE.md §1.
class NewClaimScreen extends StatefulWidget {
  const NewClaimScreen({super.key});

  @override
  State<NewClaimScreen> createState() => _NewClaimScreenState();
}

class _LineItemForm {
  final titleController = TextEditingController();
  final amountController = TextEditingController();
  DateTime expenseDate = DateTime.now();
}

class _NewClaimScreenState extends State<NewClaimScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _currencyController = TextEditingController(text: 'USD');
  final _lineItems = <_LineItemForm>[_LineItemForm()];

  List<ClaimType> _claimTypes = [];
  ClaimType? _selectedType;
  bool _loadingTypes = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ClaimTypeService.instance.listClaimTypes().then((types) {
      setState(() {
        _claimTypes = types;
        _selectedType = types.isNotEmpty ? types.first : null;
        _loadingTypes = false;
      });
    }).catchError((e) {
      setState(() {
        _loadingTypes = false;
        _error = e is ApiException ? e.detail : e.toString();
      });
    });
  }

  double get _total => _lineItems.fold(
        0,
        (sum, item) => sum + (double.tryParse(item.amountController.text) ?? 0),
      );

  Future<void> _submit() async {
    if (_selectedType == null || _titleController.text.trim().isEmpty) {
      setState(() => _error = 'Title and claim type are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final id = const Uuid().v4();
    final draft = ClaimDraft(
      id: id,
      claimTypeId: _selectedType!.id,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      claimCurrencyCode: _currencyController.text.trim().toUpperCase(),
      lineItems: [
        for (var i = 0; i < _lineItems.length; i++)
          ClaimLineItem(
            lineNumber: i + 1,
            expenseDate: _lineItems[i].expenseDate,
            category: _lineItems[i].titleController.text.trim(),
            amount: double.tryParse(_lineItems[i].amountController.text) ?? 0,
          ),
      ],
    );

    try {
      await ClaimService.instance.createClaim(draft);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() {
        _saving = false;
        _error = e.detail;
      });
    } catch (_) {
      // No response at all — treat as offline, not a hard failure.
      await LocalDraftDb.instance.saveDraft({
        'id': id,
        'claim_type_id': draft.claimTypeId,
        'title': draft.title,
        'description': draft.description,
        'claim_currency_code': draft.claimCurrencyCode,
        'line_items_json': draft.lineItems.map((e) => e.toCreateJson()).toString(),
        'synced': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Claim')),
      body: _loadingTypes
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ClaimType>(
                  initialValue: _selectedType,
                  decoration: const InputDecoration(labelText: 'Claim Type', border: OutlineInputBorder()),
                  items: _claimTypes
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                      .toList(),
                  onChanged: (t) => setState(() => _selectedType = t),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _currencyController,
                  decoration: const InputDecoration(labelText: 'Currency (e.g. USD)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder()),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                const Text('Line items', style: TextStyle(fontWeight: FontWeight.bold)),
                for (final item in _lineItems) _lineItemRow(item),
                TextButton.icon(
                  onPressed: () => setState(() => _lineItems.add(_LineItemForm())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add line item'),
                ),
                const SizedBox(height: 12),
                Text('Total: ${_currencyController.text.toUpperCase()} ${_total.toStringAsFixed(2)}'),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save Draft'),
                ),
              ],
            ),
    );
  }

  Widget _lineItemRow(_LineItemForm item) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: item.titleController,
              decoration: const InputDecoration(labelText: 'Category', isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: item.amountController,
              decoration: const InputDecoration(labelText: 'Amount', isDense: true),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }
}
