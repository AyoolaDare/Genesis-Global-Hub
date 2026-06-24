import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/error_state.dart';
import '../../providers/sponsor_provider.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class SponsorDetailScreen extends ConsumerWidget {
  final String sponsorId;

  const SponsorDetailScreen({super.key, required this.sponsorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sponsorAsync = ref.watch(sponsorDetailProvider(sponsorId));

    return ShellLayout(
      title: 'Sponsor Detail',
      child: sponsorAsync.when(
        loading: () => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SkeletonBox(height: 200),
              const SizedBox(height: 16),
              const SkeletonBox(height: 300),
            ],
          ),
        ),
        error: (e, _) => ErrorState(
          message: e.toString().contains('403')
              ? 'Access Denied'
              : 'Failed to load sponsor',
          onRetry: () =>
              ref.invalidate(sponsorDetailProvider(sponsorId)),
        ),
        data: (sponsor) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SponsorInfoCard(sponsor: sponsor),
              const SizedBox(height: 16),
              _PaymentHistoryCard(
                sponsor: sponsor,
                onRecordPayment: () =>
                    _showRecordPaymentSheet(context, ref, sponsor),
                onSendReminder: () => _sendReminder(context, sponsor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRecordPaymentSheet(
      BuildContext context, WidgetRef ref, Sponsor sponsor) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _RecordPaymentSheet(
        sponsor: sponsor,
        onSaved: () => ref.invalidate(sponsorDetailProvider(sponsorId)),
      ),
    );
  }

  void _sendReminder(BuildContext context, Sponsor sponsor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reminder sent to ${sponsor.name}'),
        backgroundColor: AppColors.success,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sponsor info card
// ---------------------------------------------------------------------------

class _SponsorInfoCard extends StatelessWidget {
  final Sponsor sponsor;

  const _SponsorInfoCard({required this.sponsor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.secondary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.volunteer_activism_outlined,
                    size: 30, color: AppColors.secondary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sponsor.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (sponsor.category != null) ...[
                      const SizedBox(height: 4),
                      _TierBadge(tier: sponsor.category!),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₦${sponsor.totalContributions.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                  const Text(
                    'Total contributions',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              if (sponsor.phone != null)
                _InfoChip(
                    icon: Icons.phone_outlined, value: sponsor.phone!),
              if (sponsor.email != null)
                _InfoChip(
                    icon: Icons.email_outlined, value: sponsor.email!),
              if (sponsor.address != null)
                _InfoChip(
                    icon: Icons.location_on_outlined,
                    value: sponsor.address!),
              _InfoChip(
                icon: Icons.calendar_today_outlined,
                value:
                    'Since ${sponsor.createdAt.day}/${sponsor.createdAt.month}/${sponsor.createdAt.year}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String value;

  const _InfoChip({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(
              fontSize: 13, color: AppColors.textPrimary),
        ),
      ],
    );
  }
}

class _TierBadge extends StatelessWidget {
  final String tier;

  const _TierBadge({required this.tier});

  Color get _color {
    switch (tier.toUpperCase()) {
      case 'ANNUAL':
        return AppColors.secondary;
      case 'QUARTERLY':
        return AppColors.primary;
      case 'MONTHLY':
        return AppColors.info;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withOpacity(0.3)),
      ),
      child: Text(
        tier.replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment history card
// ---------------------------------------------------------------------------

class _PaymentHistoryCard extends StatelessWidget {
  final Sponsor sponsor;
  final VoidCallback onRecordPayment;
  final VoidCallback onSendReminder;

  const _PaymentHistoryCard({
    required this.sponsor,
    required this.onRecordPayment,
    required this.onSendReminder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Payment History',
                  style: Theme.of(context).textTheme.titleMedium),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.notifications_outlined,
                        size: 16),
                    label: const Text('Send Reminder'),
                    onPressed: onSendReminder,
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Record Payment'),
                    onPressed: onRecordPayment,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (sponsor.payments.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No payments recorded yet',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor:
                    MaterialStateProperty.all(AppColors.surface),
                columns: const [
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Amount')),
                  DataColumn(label: Text('Method')),
                  DataColumn(label: Text('Reference')),
                ],
                rows: sponsor.payments
                    .map(
                      (p) => DataRow(
                        cells: [
                          DataCell(Text(
                              '${p.paymentDate.day}/${p.paymentDate.month}/${p.paymentDate.year}')),
                          DataCell(Text(
                            '₦${p.amount.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.success,
                            ),
                          )),
                          DataCell(Text(p.method)),
                          DataCell(Text(p.reference ?? '—')),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Record payment bottom sheet
// ---------------------------------------------------------------------------

class _RecordPaymentSheet extends ConsumerStatefulWidget {
  final Sponsor sponsor;
  final VoidCallback onSaved;

  const _RecordPaymentSheet(
      {required this.sponsor, required this.onSaved});

  @override
  ConsumerState<_RecordPaymentSheet> createState() =>
      _RecordPaymentSheetState();
}

class _RecordPaymentSheetState
    extends ConsumerState<_RecordPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  String _method = 'CASH';
  DateTime _paymentDate = DateTime.now();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Record Payment for ${widget.sponsor.name}',
                    style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (₦) *',
                border: OutlineInputBorder(),
                prefixText: '₦ ',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Amount is required';
                }
                if (double.tryParse(v.trim()) == null) {
                  return 'Enter a valid number';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _method,
                    decoration: const InputDecoration(
                      labelText: 'Payment Method',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 15),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'CASH', child: Text('Cash')),
                      DropdownMenuItem(
                          value: 'TRANSFER',
                          child: Text('Bank Transfer')),
                      DropdownMenuItem(
                          value: 'CHEQUE', child: Text('Cheque')),
                      DropdownMenuItem(
                          value: 'POS', child: Text('POS')),
                    ],
                    onChanged: (v) =>
                        setState(() => _method = v ?? 'CASH'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickDate(context),
                    child: AbsorbPointer(
                      child: TextFormField(
                        decoration: InputDecoration(
                          labelText: 'Payment Date',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(
                              Icons.calendar_today_outlined,
                              size: 18),
                          hintText:
                              '${_paymentDate.day}/${_paymentDate.month}/${_paymentDate.year}',
                        ),
                        controller: TextEditingController(
                          text:
                              '${_paymentDate.day}/${_paymentDate.month}/${_paymentDate.year}',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _referenceController,
              decoration: const InputDecoration(
                labelText: 'Reference / Receipt No.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.white),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label:
                    Text(_isSubmitting ? 'Saving...' : 'Save Payment'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _isSubmitting ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _paymentDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(
        '${ApiEndpoints.sponsorById(widget.sponsor.id)}/payments',
        data: {
          'amount': double.parse(_amountController.text.trim()),
          'method': _method,
          'payment_date': _paymentDate.toIso8601String(),
          if (_referenceController.text.trim().isNotEmpty)
            'reference': _referenceController.text.trim(),
        },
      );
      widget.onSaved();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment recorded successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to record payment: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
