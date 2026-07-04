import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
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
                onStartFlutterwave: () =>
                    _showFlutterwavePaymentSheet(context, ref, sponsor),
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

  void _showFlutterwavePaymentSheet(
      BuildContext context, WidgetRef ref, Sponsor sponsor) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _FlutterwavePaymentSheet(
        sponsor: sponsor,
        onCreated: () => ref.invalidate(sponsorDetailProvider(sponsorId)),
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
  final VoidCallback onStartFlutterwave;
  final VoidCallback onSendReminder;

  const _PaymentHistoryCard({
    required this.sponsor,
    required this.onRecordPayment,
    required this.onStartFlutterwave,
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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              Text('Payment History',
                  style: Theme.of(context).textTheme.titleMedium),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.notifications_outlined, size: 16),
                    label: const Text('Send Reminder'),
                    onPressed: onSendReminder,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.credit_card_outlined, size: 16),
                    label: const Text('Flutterwave Link'),
                    onPressed: onStartFlutterwave,
                  ),
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
                  DataColumn(label: Text('Status')),
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
                          DataCell(_PaymentStatusBadge(status: p.status)),
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

class _PaymentStatusBadge extends StatelessWidget {
  final String status;

  const _PaymentStatusBadge({required this.status});

  Color get _color {
    switch (status.toUpperCase()) {
      case 'COMPLETED':
      case 'SUCCESSFUL':
        return AppColors.success;
      case 'PENDING':
        return AppColors.warning;
      case 'FAILED':
      case 'CANCELLED':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withOpacity(0.35)),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Flutterwave payment bottom sheet
// ---------------------------------------------------------------------------

class _FlutterwavePaymentSheet extends ConsumerStatefulWidget {
  final Sponsor sponsor;
  final VoidCallback onCreated;

  const _FlutterwavePaymentSheet({
    required this.sponsor,
    required this.onCreated,
  });

  @override
  ConsumerState<_FlutterwavePaymentSheet> createState() =>
      _FlutterwavePaymentSheetState();
}

class _FlutterwavePaymentSheetState
    extends ConsumerState<_FlutterwavePaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  PaymentInitiation? _initiation;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final amount = widget.sponsor.totalContributions > 0
        ? widget.sponsor.totalContributions
        : 0.0;
    _amountController = TextEditingController(
      text: amount > 0 ? amount.toStringAsFixed(0) : '',
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initiation = _initiation;

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
                Expanded(
                  child: Text(
                    'Flutterwave Payment for ${widget.sponsor.name}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
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
                labelText: 'Amount (NGN) *',
                border: OutlineInputBorder(),
                prefixText: 'NGN ',
              ),
              validator: (v) {
                final amount = double.tryParse((v ?? '').trim());
                if (amount == null || amount <= 0) {
                  return 'Enter a valid amount';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const Icon(Icons.link_outlined, size: 18),
                label: Text(_isSubmitting
                    ? 'Generating...'
                    : 'Generate Flutterwave Link'),
                onPressed: _isSubmitting ? null : _generateLink,
              ),
            ),
            if (initiation != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Checkout link',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      initiation.paymentLink,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Open Checkout'),
                          onPressed: () => html.window.open(
                            initiation.paymentLink,
                            '_blank',
                          ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.copy_outlined, size: 16),
                          label: const Text('Copy Link'),
                          onPressed: () => _copyLink(initiation.paymentLink),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _generateLink() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final dio = ref.read(dioProvider);
      final redirectUrl = '${html.window.location.origin}/#/payment/complete';
      final response = await dio.post(
        ApiEndpoints.initiatePayment,
        data: {
          'sponsor_id': widget.sponsor.id,
          'amount': double.parse(_amountController.text.trim()),
          'redirect_url': redirectUrl,
        },
      );
      final data = Map<String, dynamic>.from(response.data['data'] as Map);
      setState(() => _initiation = PaymentInitiation.fromJson(data));
      widget.onCreated();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Flutterwave payment link generated'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      final message = ApiException.from(e)?.message ??
          'Failed to generate Flutterwave link.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _copyLink(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment link copied'),
          backgroundColor: AppColors.success,
        ),
      );
    }
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
                          value: 'BANK_TRANSFER',
                          child: Text('Bank Transfer')),
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
        ApiEndpoints.sponsorPayments(widget.sponsor.id),
        data: {
          'amount': double.parse(_amountController.text.trim()),
          'payment_method': _method,
          'payment_date': _paymentDate.toIso8601String(),
          if (_referenceController.text.trim().isNotEmpty)
            'notes': _referenceController.text.trim(),
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
