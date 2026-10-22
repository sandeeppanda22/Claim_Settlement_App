import 'package:flutter/material.dart';

/// Small, consistent color mapping for claim_status everywhere it's shown.
/// One place to update if the palette changes — never re-derive colors
/// per screen.
class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge({super.key, required this.status});

  Color get _color {
    switch (status) {
      case 'DRAFT':
        return Colors.grey;
      case 'SUBMITTED':
      case 'PENDING_APPROVAL':
      case 'PENDING_FINANCE_REVIEW':
      case 'PAYMENT_INITIATED':
        return Colors.orange;
      case 'APPROVED':
      case 'REIMBURSED':
      case 'CLOSED':
        return Colors.green;
      case 'REJECTED':
      case 'CANCELLED':
        return Colors.red;
      case 'RETURNED_FOR_REVISION':
        return Colors.deepPurple;
      default:
        return Colors.blueGrey;
    }
  }

  String get _label => status.replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        _label,
        style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
      ),
      backgroundColor: _color,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }
}
