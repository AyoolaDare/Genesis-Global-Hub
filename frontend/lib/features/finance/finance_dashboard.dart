import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/error_state.dart';

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
    return FinanceDashboardData(
      totalSponsors: json['total_sponsors'] ?? 0,
      activeSponsors: json['active_sponsors'] ?? 0,
      monthlyRevenue: (json['monthly_revenue'] ?? 0.0).toDouble(),
      annualRevenue: (json['annual_revenue'] ?? 0.0).toDouble(),
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
        onRefresh: () => ref.refresh(financeDashboardProvider.future),
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
                  message: e.toString().contains('403')
                      ? 'Access Denied'
                      : 'Failed to load dashboard',
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
        value: _formatCurrency(data.monthlyRevenue),
        icon: Icons.trending_up_outlined,
        color: AppColors.info,
        subtitle: 'This month',
      ),
      _StatItem(
        label: 'Annual Revenue',
        value: _formatCurrency(data.annualRevenue),
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

  String _formatCurrency(double amount) {
    if (amount >= 1000000) {
      return '₦${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '₦${(amount / 1000).toStringAsFixed(1)}K';
    }
    return '₦${amount.toStringAsFixed(0)}';
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
                              '₦${(p['amount'] ?? 0).toStringAsFixed(0)}',
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
