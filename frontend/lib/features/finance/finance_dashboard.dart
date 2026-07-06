import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/error_state.dart';
import '../../providers/sponsor_provider.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class FinanceDashboardData {
  final int totalSponsors;
  final int activeSponsors;
  final double monthlyRevenue;
  final double annualRevenue;
  final List<Map<String, dynamic>> overdueSponsors;
  final List<Map<String, dynamic>> recentPayments;

  const FinanceDashboardData({
    required this.totalSponsors,
    required this.activeSponsors,
    required this.monthlyRevenue,
    required this.annualRevenue,
    required this.overdueSponsors,
    required this.recentPayments,
  });

  factory FinanceDashboardData.fromJson(Map<String, dynamic> json) {
    double amount(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    return FinanceDashboardData(
      totalSponsors: json['total_sponsors'] ?? 0,
      activeSponsors: json['active_sponsors'] ?? 0,
      monthlyRevenue: amount(json['monthly_revenue']),
      annualRevenue: amount(json['annual_revenue']),
      overdueSponsors: json['overdue_sponsors'] != null
          ? List<Map<String, dynamic>>.from(json['overdue_sponsors'])
          : [],
      recentPayments: json['recent_payments'] != null
          ? List<Map<String, dynamic>>.from(json['recent_payments'])
          : [],
    );
  }
}

final financeDashboardProvider =
    FutureProvider<FinanceDashboardData>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.financeDashboard);
  return FinanceDashboardData.fromJson(response.data['data']);
});

// ---------------------------------------------------------------------------
// Ops health model + provider
// ---------------------------------------------------------------------------

class FinanceOpsData {
  final bool healthy;
  final int pending;
  final int stuckPending;
  final int? oldestPendingMinutes;
  final int completedToday;
  final int missingThankYou;
  final int queueFailed;
  final int queuePending;
  final Map<String, bool> providers;
  final List<String> alerts;

  const FinanceOpsData({
    required this.healthy,
    required this.pending,
    required this.stuckPending,
    required this.oldestPendingMinutes,
    required this.completedToday,
    required this.missingThankYou,
    required this.queueFailed,
    required this.queuePending,
    required this.providers,
    required this.alerts,
  });

  factory FinanceOpsData.fromJson(Map<String, dynamic> json) {
    final payments = Map<String, dynamic>.from(json['payments'] ?? {});
    final notifications = Map<String, dynamic>.from(json['notifications'] ?? {});
    return FinanceOpsData(
      healthy: json['healthy'] == true,
      pending: (payments['pending'] as num?)?.toInt() ?? 0,
      stuckPending: (payments['stuck_pending'] as num?)?.toInt() ?? 0,
      oldestPendingMinutes:
          (payments['oldest_pending_minutes'] as num?)?.toInt(),
      completedToday: (payments['completed_today'] as num?)?.toInt() ?? 0,
      missingThankYou:
          (payments['missing_thank_you_7_days'] as num?)?.toInt() ?? 0,
      queueFailed: (notifications['failed'] as num?)?.toInt() ?? 0,
      queuePending: (notifications['queued'] as num?)?.toInt() ?? 0,
      providers: Map<String, dynamic>.from(json['providers'] ?? {})
          .map((k, v) => MapEntry(k, v == true)),
      alerts: List<String>.from(json['alerts'] ?? const []),
    );
  }
}

final financeOpsProvider = FutureProvider<FinanceOpsData>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.financeOps);
  return FinanceOpsData.fromJson(response.data['data']);
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class FinanceDashboard extends ConsumerWidget {
  const FinanceDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShellLayout(
      title: 'Sponsor Dashboard',
      actions: [
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Sponsor'),
          onPressed: () => context.go('/finance/sponsors'),
        ),
        const SizedBox(width: 8),
      ],
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(sponsorProvider);
          ref.invalidate(financeDashboardProvider);
          ref.invalidate(financeOpsProvider);
          await ref.read(financeDashboardProvider.future);
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ref.watch(financeDashboardProvider).when(
                loading: () => Column(
                  children: [
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.8,
                      children: List.generate(
                          4, (_) => const DashboardStatSkeleton()),
                    ),
                  ],
                ),
                error: (e, _) => ErrorState(
                  message: ApiException.from(e)?.statusCode == 403
                      ? 'Access Denied'
                      : 'Failed to load dashboard',
                  details: ApiException.from(e)?.message ?? e.toString(),
                  onRetry: () =>
                      ref.invalidate(financeDashboardProvider),
                ),
                data: (data) => _buildContent(context, data),
              ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, FinanceDashboardData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SystemHealthSection(),
        const SizedBox(height: 24),
        Text('Sponsor Overview',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        _buildStatsGrid(context, data),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _OverdueSponsorsSection(
                  sponsors: data.overdueSponsors),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _RecentPaymentsSection(
                  payments: data.recentPayments),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _SponsorDirectorySection(),
      ],
    );
  }

  Widget _buildStatsGrid(BuildContext context, FinanceDashboardData data) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 900 ? 4 : 2;

    final items = [
      _StatItem(
        label: 'Total Sponsors',
        value: '${data.totalSponsors}',
        icon: Icons.volunteer_activism_outlined,
        color: AppColors.primary,
      ),
      _StatItem(
        label: 'Active Sponsors',
        value: '${data.activeSponsors}',
        icon: Icons.check_circle_outline,
        color: AppColors.success,
      ),
      _StatItem(
        label: 'Monthly Revenue',
        value: _formatCurrencyAmount(data.monthlyRevenue),
        icon: Icons.trending_up_outlined,
        color: AppColors.info,
        subtitle: 'This month',
      ),
      _StatItem(
        label: 'Annual Revenue',
        value: _formatCurrencyAmount(data.annualRevenue),
        icon: Icons.account_balance_outlined,
        color: AppColors.secondary,
        subtitle: 'This year',
      ),
    ];

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.8,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (_, i) => _StatCard(item: items[i]),
    );
  }
}

// ---------------------------------------------------------------------------
// System health (ops monitoring) section
// ---------------------------------------------------------------------------

class _SystemHealthSection extends ConsumerWidget {
  const _SystemHealthSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ops = ref.watch(financeOpsProvider);

    return Container(
      width: double.infinity,
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
      child: ops.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Row(
          children: [
            const Icon(Icons.cloud_off_outlined,
                color: AppColors.textSecondary, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('System health unavailable',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () => ref.invalidate(financeOpsProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
        data: (data) => _buildHealth(context, ref, data),
      ),
    );
  }

  Widget _buildHealth(
      BuildContext context, WidgetRef ref, FinanceOpsData data) {
    final statusColor = data.healthy
        ? AppColors.success
        : (data.stuckPending > 0 || data.queueFailed > 0
            ? AppColors.error
            : AppColors.warning);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  data.healthy
                      ? Icons.verified_outlined
                      : Icons.report_problem_outlined,
                  color: statusColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text('System Health',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    data.healthy ? 'All systems operational' : 'Needs attention',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.sync, size: 16),
              label: const Text('Recheck Payments'),
              onPressed: () => _recheckPayments(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _HealthCounter(
              label: 'Pending payments',
              value: '${data.pending}',
              highlight: data.pending > 0,
            ),
            _HealthCounter(
              label: 'Stuck > 30 min',
              value: '${data.stuckPending}',
              highlight: data.stuckPending > 0,
            ),
            _HealthCounter(
              label: 'Completed today',
              value: '${data.completedToday}',
            ),
            _HealthCounter(
              label: 'Thank-you gaps (7d)',
              value: '${data.missingThankYou}',
              highlight: data.missingThankYou > 0,
            ),
            _HealthCounter(
              label: 'Notifications queued',
              value: '${data.queuePending}',
            ),
            _HealthCounter(
              label: 'Notifications failed',
              value: '${data.queueFailed}',
              highlight: data.queueFailed > 0,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ProviderChip(
                label: 'Flutterwave API',
                ok: data.providers['flutterwave_api'] ?? false),
            _ProviderChip(
                label: 'Webhook',
                ok: data.providers['flutterwave_webhook'] ?? false),
            _ProviderChip(
                label: 'SMS (Termii)',
                ok: data.providers['termii_sms'] ?? false),
            _ProviderChip(
                label: 'Email (Brevo)',
                ok: data.providers['brevo_email'] ?? false),
          ],
        ),
        if (data.alerts.isNotEmpty) ...[
          const SizedBox(height: 14),
          ...data.alerts.map(
            (alert) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withOpacity(0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      size: 15, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(alert,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _recheckPayments(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.post(ApiEndpoints.reconcilePending);
      final message = (response.data['message'] as String?)?.trim() ??
          'Recheck completed.';
      ref.invalidate(financeOpsProvider);
      ref.invalidate(financeDashboardProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.success),
      );
    } catch (e) {
      final message =
          ApiException.from(e)?.message ?? 'Failed to recheck payments.';
      messenger.showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
    }
  }
}

class _HealthCounter extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _HealthCounter({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: highlight ? AppColors.error : AppColors.textPrimary,
          ),
        ),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _ProviderChip extends StatelessWidget {
  final String label;
  final bool ok;

  const _ProviderChip({required this.label, required this.ok});

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check_circle : Icons.cancel,
              size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sponsor directory section
// ---------------------------------------------------------------------------

class _SponsorDirectorySection extends ConsumerWidget {
  const _SponsorDirectorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sponsors = ref.watch(sponsorProvider);

    return Container(
      width: double.infinity,
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
              Text('Sponsor Details',
                  style: Theme.of(context).textTheme.titleMedium),
              TextButton.icon(
                onPressed: () => context.go('/finance/sponsors'),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Manage'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          sponsors.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: ErrorState(
                message: 'Failed to load sponsors',
                details: ApiException.from(error)?.message ?? error.toString(),
                onRetry: () => ref.invalidate(sponsorProvider),
              ),
            ),
            data: (data) {
              if (data.items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'No sponsors yet',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                );
              }

              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: data.items.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      color: AppColors.border,
                    ),
                    itemBuilder: (context, index) {
                      return _SponsorDashboardRow(sponsor: data.items[index]);
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SponsorDashboardRow extends StatelessWidget {
  final Sponsor sponsor;

  const _SponsorDashboardRow({required this.sponsor});

  @override
  Widget build(BuildContext context) {
    final tier = sponsor.category ?? 'Sponsor';
    final contact = sponsor.phone?.isNotEmpty == true
        ? sponsor.phone!
        : (sponsor.email?.isNotEmpty == true ? sponsor.email! : 'No contact');

    return InkWell(
      onTap: () => context.go('/finance/sponsors/${sponsor.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primary.withOpacity(0.12),
              foregroundColor: AppColors.primary,
              child: Text(
                _initials(sponsor.name),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sponsor.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    contact,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tier,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _formatCurrencyAmount(sponsor.totalContributions),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
              ),
            ),
            const SizedBox(width: 12),
            _StatusPill(isActive: sponsor.isActive),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'View sponsor',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => context.go('/finance/sponsors/${sponsor.id}'),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.substring(0, 1);
    final second = parts.length > 1 ? parts.last.substring(0, 1) : '';
    return '$first$second'.toUpperCase();
  }
}

class _StatusPill extends StatelessWidget {
  final bool isActive;

  const _StatusPill({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.success : AppColors.textSecondary;
    return Container(
      width: 72,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overdue sponsors section
// ---------------------------------------------------------------------------

class _OverdueSponsorsSection extends StatelessWidget {
  final List<Map<String, dynamic>> sponsors;

  const _OverdueSponsorsSection({required this.sponsors});

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
              const Icon(Icons.warning_amber_outlined,
                  color: AppColors.error, size: 20),
              const SizedBox(width: 8),
              Text('Overdue Sponsors',
                  style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 16),
          if (sponsors.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No overdue sponsors',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ...sponsors.take(6).map((s) => _OverdueSponsorRow(sponsor: s)),
        ],
      ),
    );
  }
}

class _OverdueSponsorRow extends StatelessWidget {
  final Map<String, dynamic> sponsor;

  const _OverdueSponsorRow({required this.sponsor});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: AppColors.error.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sponsor['name'] ?? '',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  sponsor['tier'] ?? '',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            '${sponsor['days_overdue'] ?? 0}d overdue',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent payments section
// ---------------------------------------------------------------------------

class _RecentPaymentsSection extends StatelessWidget {
  final List<Map<String, dynamic>> payments;

  const _RecentPaymentsSection({required this.payments});

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
              Text('Recent Payments',
                  style: Theme.of(context).textTheme.titleMedium),
              TextButton(
                onPressed: () =>
                    GoRouter.of(context).go('/finance/payments'),
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (payments.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No recent payments',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
              },
              children: [
                const TableRow(
                  decoration: BoxDecoration(color: AppColors.surface),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Sponsor',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Amount',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Date',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary)),
                    ),
                  ],
                ),
                ...payments.take(8).map(
                      (p) => TableRow(
                        decoration: const BoxDecoration(
                          border: Border(
                              bottom:
                                  BorderSide(color: AppColors.border)),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(p['sponsor_name'] ?? '',
                                style: const TextStyle(fontSize: 12)),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              '₦${((p['amount'] ?? 0) as num).toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.success,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(p['date'] ?? '',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

String _formatCurrencyAmount(num amount) {
  if (amount >= 1000000) {
    return '\u20a6${(amount / 1000000).toStringAsFixed(1)}M';
  } else if (amount >= 1000) {
    return '\u20a6${(amount / 1000).toStringAsFixed(1)}K';
  }
  return '\u20a6${amount.toStringAsFixed(0)}';
}

class _StatItem {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });
}

class _StatCard extends StatelessWidget {
  final _StatItem item;

  const _StatCard({required this.item});

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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  item.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: item.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.icon, size: 20, color: item.color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
          ),
          if (item.subtitle != null)
            Text(
              item.subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
        ],
      ),
    );
  }
}
