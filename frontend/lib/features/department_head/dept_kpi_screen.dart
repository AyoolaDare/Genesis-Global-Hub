import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../providers/kpi_provider.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class DeptKpiScreen extends ConsumerWidget {
  const DeptKpiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpiReportsAsync = ref.watch(kpiReportsProvider);

    return ShellLayout(
      title: 'Department KPIs',
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(kpiReportsProvider.future),
        child: kpiReportsAsync.when(
          loading: () => Padding(
            padding: const EdgeInsets.all(24),
            child: ListSkeleton(
              count: 4,
              itemBuilder: () => const SkeletonBox(height: 120),
            ),
          ),
          error: (e, _) => ErrorState(
            message: e.toString().contains('403')
                ? 'Access Denied'
                : 'Failed to load KPI data',
            onRetry: () => ref.invalidate(kpiReportsProvider),
          ),
          data: (reports) => reports.isEmpty
              ? const EmptyState(
                  icon: Icons.track_changes_outlined,
                  title: 'No KPI data available',
                  subtitle: 'KPI configurations have not been set up yet.',
                )
              : _buildContent(context, reports),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<KpiReport> reports) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('KPI Performance Report',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Current period performance vs targets',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          _SummaryCards(reports: reports),
          const SizedBox(height: 24),
          ...reports.map((r) => _KpiCard(report: r)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary cards
// ---------------------------------------------------------------------------

class _SummaryCards extends StatelessWidget {
  final List<KpiReport> reports;

  const _SummaryCards({required this.reports});

  @override
  Widget build(BuildContext context) {
    final achieved = reports.where((r) => r.achievementRate >= 100).length;
    final onTrack = reports
        .where((r) => r.achievementRate >= 70 && r.achievementRate < 100)
        .length;
    final belowTarget =
        reports.where((r) => r.achievementRate < 70).length;

    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 900 ? 3 : 2;

    final items = [
      _SummaryItem(
        label: 'Achieved',
        value: '$achieved',
        color: AppColors.success,
        icon: Icons.check_circle_outline,
      ),
      _SummaryItem(
        label: 'On Track',
        value: '$onTrack',
        color: AppColors.warning,
        icon: Icons.trending_up_outlined,
      ),
      _SummaryItem(
        label: 'Below Target',
        value: '$belowTarget',
        color: AppColors.error,
        icon: Icons.warning_amber_outlined,
      ),
    ];

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 2.0,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (_, i) => _SummaryCard(item: items[i]),
    );
  }
}

class _SummaryItem {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _SummaryItem({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
}

class _SummaryCard extends StatelessWidget {
  final _SummaryItem item;

  const _SummaryCard({required this.item});

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
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: item.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(item.icon, size: 24, color: item.color),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                item.value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: item.color,
                ),
              ),
              Text(
                item.label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// KPI Card
// ---------------------------------------------------------------------------

class _KpiCard extends StatelessWidget {
  final KpiReport report;

  const _KpiCard({required this.report});

  Color get _rateColor {
    if (report.achievementRate >= 100) return AppColors.success;
    if (report.achievementRate >= 70) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final progressValue = (report.achievementRate / 100).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: _rateColor, width: 4),
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 6,
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.kpiName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${report.departmentName} | ${report.period}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${report.achievementRate.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: _rateColor,
                    ),
                  ),
                  Text(
                    'Achievement',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressValue,
              minHeight: 10,
              backgroundColor: AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(_rateColor),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MetricChip(
                  label: 'Actual',
                  value: report.actual.toStringAsFixed(1),
                  color: _rateColor),
              const SizedBox(width: 12),
              _MetricChip(
                  label: 'Target',
                  value: report.target.toStringAsFixed(1),
                  color: AppColors.primary),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
