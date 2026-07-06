import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/error_state.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class FunnelDonor {
  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String tier;
  final double amount;
  final String status; // PAID / PENDING / OVERDUE
  final int? daysOverdue;
  final int reminderStage; // 0-3
  final int tenureMonths;
  final String tenureBucket;
  final int paymentsCount;
  final double totalPaid;
  final String? lastPaymentDate;
  final String? nextDueDate;
  final String consistency; // CONSISTENT / REGULAR / NEW / LAPSED

  const FunnelDonor({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    required this.tier,
    required this.amount,
    required this.status,
    this.daysOverdue,
    required this.reminderStage,
    required this.tenureMonths,
    required this.tenureBucket,
    required this.paymentsCount,
    required this.totalPaid,
    this.lastPaymentDate,
    this.nextDueDate,
    required this.consistency,
  });

  factory FunnelDonor.fromJson(Map<String, dynamic> json) => FunnelDonor(
        id: json['id']?.toString() ?? '',
        name: json['full_name'] ?? '',
        phone: json['phone'],
        email: json['email'],
        tier: json['tier'] ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        status: json['status'] ?? 'PENDING',
        daysOverdue: (json['days_overdue'] as num?)?.toInt(),
        reminderStage: (json['reminder_stage'] as num?)?.toInt() ?? 0,
        tenureMonths: (json['tenure_months'] as num?)?.toInt() ?? 0,
        tenureBucket: json['tenure_bucket'] ?? 'NEW',
        paymentsCount: (json['payments_count'] as num?)?.toInt() ?? 0,
        totalPaid: (json['total_paid'] as num?)?.toDouble() ?? 0,
        lastPaymentDate: json['last_payment_date'],
        nextDueDate: json['next_due_date'],
        consistency: json['consistency'] ?? 'NEW',
      );
}

class FunnelData {
  final Map<String, int> summary;
  final Map<String, Map<String, int>> tenureMatrix;
  final List<FunnelDonor> donors;

  const FunnelData({
    required this.summary,
    required this.tenureMatrix,
    required this.donors,
  });

  factory FunnelData.fromJson(Map<String, dynamic> json) {
    final matrix = <String, Map<String, int>>{};
    (json['tenure_matrix'] as Map? ?? {}).forEach((key, value) {
      matrix[key.toString()] = Map<String, dynamic>.from(value as Map)
          .map((k, v) => MapEntry(k, (v as num).toInt()));
    });
    return FunnelData(
      summary: Map<String, dynamic>.from(json['summary'] ?? {})
          .map((k, v) => MapEntry(k, (v as num).toInt())),
      tenureMatrix: matrix,
      donors: (json['donors'] as List? ?? [])
          .map((e) => FunnelDonor.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class FunnelConfig {
  final bool enabled;
  final int stage1DaysBeforeDue;
  final int stage2DaysOverdue;
  final int stage3DaysOverdue;

  const FunnelConfig({
    required this.enabled,
    required this.stage1DaysBeforeDue,
    required this.stage2DaysOverdue,
    required this.stage3DaysOverdue,
  });

  factory FunnelConfig.fromJson(Map<String, dynamic> json) => FunnelConfig(
        enabled: json['enabled'] == true,
        stage1DaysBeforeDue:
            (json['stage1_days_before_due'] as num?)?.toInt() ?? 7,
        stage2DaysOverdue: (json['stage2_days_overdue'] as num?)?.toInt() ?? 14,
        stage3DaysOverdue: (json['stage3_days_overdue'] as num?)?.toInt() ?? 21,
      );
}

final donorFunnelProvider = FutureProvider<FunnelData>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.donorFunnel);
  return FunnelData.fromJson(response.data['data']);
});

final funnelConfigProvider = FutureProvider<FunnelConfig>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.funnelConfig);
  return FunnelConfig.fromJson(response.data['data']);
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class DonorFunnelScreen extends ConsumerStatefulWidget {
  const DonorFunnelScreen({super.key});

  @override
  ConsumerState<DonorFunnelScreen> createState() => _DonorFunnelScreenState();
}

class _DonorFunnelScreenState extends ConsumerState<DonorFunnelScreen> {
  String _statusFilter = 'ALL';
  String _sortBy = 'TENURE'; // TENURE | TOTAL | OVERDUE

  @override
  Widget build(BuildContext context) {
    final funnel = ref.watch(donorFunnelProvider);

    return ShellLayout(
      title: 'Donor Funnel',
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(donorFunnelProvider);
          ref.invalidate(funnelConfigProvider);
          await ref.read(donorFunnelProvider.future);
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: funnel.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => ErrorState(
              message: ApiException.from(e)?.statusCode == 403
                  ? 'Access Denied'
                  : 'Failed to load donor funnel',
              details: ApiException.from(e)?.message ?? e.toString(),
              onRetry: () => ref.invalidate(donorFunnelProvider),
            ),
            data: (data) => _buildContent(context, data),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, FunnelData data) {
    final filtered = _statusFilter == 'ALL'
        ? data.donors
        : data.donors.where((d) => d.status == _statusFilter).toList();

    final sorted = [...filtered];
    switch (_sortBy) {
      case 'TOTAL':
        sorted.sort((a, b) => b.totalPaid.compareTo(a.totalPaid));
        break;
      case 'OVERDUE':
        sorted.sort(
            (a, b) => (b.daysOverdue ?? -1).compareTo(a.daysOverdue ?? -1));
        break;
      default: // TENURE
        sorted.sort((a, b) => b.tenureMonths.compareTo(a.tenureMonths));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryRow(
          summary: data.summary,
          activeFilter: _statusFilter,
          onFilter: (status) => setState(() {
            _statusFilter = _statusFilter == status ? 'ALL' : status;
          }),
        ),
        const SizedBox(height: 20),
        _TenureBreakdown(matrix: data.tenureMatrix),
        const SizedBox(height: 20),
        _ReminderScheduleCard(
          onSaved: () => ref.invalidate(funnelConfigProvider),
        ),
        const SizedBox(height: 20),
        _DonorTable(
          donors: sorted,
          statusFilter: _statusFilter,
          sortBy: _sortBy,
          onSortChanged: (value) => setState(() => _sortBy = value),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Summary row (paid / pending / overdue) — tappable filters
// ---------------------------------------------------------------------------

class _SummaryRow extends StatelessWidget {
  final Map<String, int> summary;
  final String activeFilter;
  final void Function(String status) onFilter;

  const _SummaryRow({
    required this.summary,
    required this.activeFilter,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      ('PAID', 'Paid', summary['paid'] ?? 0, AppColors.success,
          Icons.check_circle_outline),
      ('PENDING', 'Pending', summary['pending'] ?? 0, AppColors.warning,
          Icons.hourglass_top_outlined),
      ('OVERDUE', 'Overdue', summary['overdue'] ?? 0, AppColors.error,
          Icons.warning_amber_outlined),
    ];

    return Row(
      children: [
        for (final (status, label, count, color, icon) in items) ...[
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onFilter(status),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: activeFilter == status
                        ? color
                        : AppColors.border,
                    width: activeFilter == status ? 2 : 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.cardShadow,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$count',
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w800)),
                        Text(label,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (status != 'OVERDUE') const SizedBox(width: 14),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tenure breakdown — stacked bars per bucket
// ---------------------------------------------------------------------------

const _bucketLabels = {
  'NEW': 'New (<1 mo)',
  '1_3_MONTHS': '1–3 months',
  '3_6_MONTHS': '3–6 months',
  '6_12_MONTHS': '6–12 months',
  '1_YEAR_PLUS': '1 year +',
};

class _TenureBreakdown extends StatelessWidget {
  final Map<String, Map<String, int>> matrix;

  const _TenureBreakdown({required this.matrix});

  @override
  Widget build(BuildContext context) {
    final maxTotal = matrix.values
        .map((m) => m['total'] ?? 0)
        .fold<int>(1, (a, b) => a > b ? a : b);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: AppColors.cardShadow, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline_outlined,
                  size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Donors by Giving Tenure',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              const _LegendDot(color: AppColors.success, label: 'Paid'),
              const SizedBox(width: 10),
              const _LegendDot(color: AppColors.warning, label: 'Pending'),
              const SizedBox(width: 10),
              const _LegendDot(color: AppColors.error, label: 'Overdue'),
            ],
          ),
          const SizedBox(height: 16),
          for (final bucket in _bucketLabels.keys) ...[
            _TenureBar(
              label: _bucketLabels[bucket]!,
              counts: matrix[bucket] ?? const {},
              maxTotal: maxTotal,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _TenureBar extends StatelessWidget {
  final String label;
  final Map<String, int> counts;
  final int maxTotal;

  const _TenureBar({
    required this.label,
    required this.counts,
    required this.maxTotal,
  });

  @override
  Widget build(BuildContext context) {
    final paid = counts['paid'] ?? 0;
    final pending = counts['pending'] ?? 0;
    final overdue = counts['overdue'] ?? 0;
    final total = counts['total'] ?? 0;

    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 18,
              child: total == 0
                  ? Container(color: AppColors.surface)
                  : Row(
                      children: [
                        if (paid > 0)
                          Expanded(
                              flex: paid,
                              child: Container(color: AppColors.success)),
                        if (pending > 0)
                          Expanded(
                              flex: pending,
                              child: Container(color: AppColors.warning)),
                        if (overdue > 0)
                          Expanded(
                              flex: overdue,
                              child: Container(color: AppColors.error)),
                        // Pad the bar so lengths are comparable across buckets
                        if (maxTotal > total)
                          Expanded(
                              flex: maxTotal - total,
                              child: Container(color: AppColors.surface)),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 32,
          child: Text('$total',
              textAlign: TextAlign.right,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reminder schedule config card
// ---------------------------------------------------------------------------

class _ReminderScheduleCard extends ConsumerStatefulWidget {
  final VoidCallback onSaved;

  const _ReminderScheduleCard({required this.onSaved});

  @override
  ConsumerState<_ReminderScheduleCard> createState() =>
      _ReminderScheduleCardState();
}

class _ReminderScheduleCardState extends ConsumerState<_ReminderScheduleCard> {
  final _stage1 = TextEditingController();
  final _stage2 = TextEditingController();
  final _stage3 = TextEditingController();
  bool _enabled = true;
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _stage1.dispose();
    _stage2.dispose();
    _stage3.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(funnelConfigProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: AppColors.cardShadow, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: config.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(8),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Text(
          'Could not load reminder schedule: '
          '${ApiException.from(e)?.message ?? e}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        data: (cfg) {
          if (!_initialized) {
            _stage1.text = '${cfg.stage1DaysBeforeDue}';
            _stage2.text = '${cfg.stage2DaysOverdue}';
            _stage3.text = '${cfg.stage3DaysOverdue}';
            _enabled = cfg.enabled;
            _initialized = true;
          }
          return _buildForm(context);
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.schedule_outlined,
                size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('Reminder Schedule',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Row(
              children: [
                const Text('Automated reminders',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                Switch(
                  value: _enabled,
                  activeColor: AppColors.success,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Three reminders per payment cycle. The daily job reads this '
          'schedule on every run — changes apply from the next run.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ScheduleField(
              controller: _stage1,
              label: 'Reminder 1',
              suffix: 'days before due',
            ),
            const Icon(Icons.arrow_forward,
                size: 16, color: AppColors.textSecondary),
            _ScheduleField(
              controller: _stage2,
              label: 'Reminder 2 (nudge)',
              suffix: 'days overdue',
            ),
            const Icon(Icons.arrow_forward,
                size: 16, color: AppColors.textSecondary),
            _ScheduleField(
              controller: _stage3,
              label: 'Final notice',
              suffix: 'days overdue',
            ),
            ElevatedButton.icon(
              icon: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.white))
                  : const Icon(Icons.save_outlined, size: 16),
              label: Text(_saving ? 'Saving…' : 'Save Schedule'),
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final s1 = int.tryParse(_stage1.text.trim());
    final s2 = int.tryParse(_stage2.text.trim());
    final s3 = int.tryParse(_stage3.text.trim());
    if (s1 == null || s2 == null || s3 == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('All schedule values must be whole numbers of days.'),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.put(ApiEndpoints.funnelConfig, data: {
        'enabled': _enabled,
        'stage1_days_before_due': s1,
        'stage2_days_overdue': s2,
        'stage3_days_overdue': s3,
      });
      widget.onSaved();
      messenger.showSnackBar(const SnackBar(
        content: Text('Reminder schedule updated.'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(
            ApiException.from(e)?.message ?? 'Failed to update schedule.'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ScheduleField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String suffix;

  const _ScheduleField({
    required this.controller,
    required this.label,
    required this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          suffixStyle:
              const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Donor table
// ---------------------------------------------------------------------------

class _DonorTable extends StatelessWidget {
  final List<FunnelDonor> donors;
  final String statusFilter;
  final String sortBy;
  final void Function(String) onSortChanged;

  const _DonorTable({
    required this.donors,
    required this.statusFilter,
    required this.sortBy,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: AppColors.cardShadow, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                statusFilter == 'ALL'
                    ? 'All Donors (${donors.length})'
                    : '${statusFilter[0]}${statusFilter.substring(1).toLowerCase()} Donors (${donors.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              const Text('Sort by:',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: sortBy,
                underline: const SizedBox.shrink(),
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600),
                items: const [
                  DropdownMenuItem(value: 'TENURE', child: Text('Tenure')),
                  DropdownMenuItem(value: 'TOTAL', child: Text('Total given')),
                  DropdownMenuItem(
                      value: 'OVERDUE', child: Text('Days overdue')),
                ],
                onChanged: (v) => onSortChanged(v ?? 'TENURE'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (donors.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No donors in this view',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: MaterialStateProperty.all(AppColors.surface),
                columns: const [
                  DataColumn(label: Text('Donor')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Tenure')),
                  DataColumn(label: Text('Payments')),
                  DataColumn(label: Text('Total Given')),
                  DataColumn(label: Text('Next Due')),
                  DataColumn(label: Text('Funnel Stage')),
                ],
                rows: donors
                    .map((d) => DataRow(cells: [
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _ConsistencyFlag(consistency: d.consistency),
                                const SizedBox(width: 6),
                                Text(d.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                            onTap: () => GoRouter.of(context)
                                .go('/finance/sponsors/${d.id}'),
                          ),
                          DataCell(_StatusBadge(
                              status: d.status, daysOverdue: d.daysOverdue)),
                          DataCell(Text(_tenureLabel(d.tenureMonths))),
                          DataCell(Text('${d.paymentsCount}')),
                          DataCell(Text(
                            '₦${d.totalPaid.toStringAsFixed(0)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.success),
                          )),
                          DataCell(Text(d.nextDueDate ?? '—')),
                          DataCell(_StageBadge(stage: d.reminderStage)),
                        ]))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  String _tenureLabel(int months) {
    if (months < 1) return 'New';
    if (months < 12) return '$months mo';
    final years = months ~/ 12;
    final rem = months % 12;
    return rem == 0 ? '$years yr' : '$years yr $rem mo';
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final int? daysOverdue;

  const _StatusBadge({required this.status, this.daysOverdue});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'PAID' => (AppColors.success, 'Paid'),
      'OVERDUE' => (
          AppColors.error,
          daysOverdue != null ? 'Overdue ${daysOverdue}d' : 'Overdue'
        ),
      _ => (AppColors.warning, 'Pending'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _StageBadge extends StatelessWidget {
  final int stage;

  const _StageBadge({required this.stage});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (stage) {
      1 => ('Reminded', AppColors.info),
      2 => ('Nudged (wk 3)', AppColors.warning),
      3 => ('Final notice', AppColors.error),
      _ => ('—', AppColors.textSecondary),
    };
    if (stage == 0) {
      return Text(label,
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

/// Stewardship flag: star for long-term consistent donors, sprout for new,
/// muted flag for lapsed — so appreciation-worthy donors stand out at a glance.
class _ConsistencyFlag extends StatelessWidget {
  final String consistency;

  const _ConsistencyFlag({required this.consistency});

  @override
  Widget build(BuildContext context) {
    final (icon, color, tooltip) = switch (consistency) {
      'CONSISTENT' => (
          Icons.star,
          AppColors.secondary,
          'Consistent long-term donor — consider a thank-you call'
        ),
      'NEW' => (Icons.fiber_new_outlined, AppColors.info, 'New donor'),
      'LAPSED' => (
          Icons.flag_outlined,
          AppColors.error,
          'Lapsed — over 45 days overdue'
        ),
      _ => (Icons.circle, Colors.transparent, ''),
    };
    if (consistency == 'REGULAR') return const SizedBox(width: 16);
    return Tooltip(
      message: tooltip,
      child: Icon(icon, size: 16, color: color),
    );
  }
}
