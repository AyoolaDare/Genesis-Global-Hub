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

class DeptDashboardData {
  final int memberCount;
  final double attendanceRateThisMonth;
  final List<Map<String, dynamic>> kpiProgress;
  final List<Map<String, dynamic>> recentAttendance;

  const DeptDashboardData({
    required this.memberCount,
    required this.attendanceRateThisMonth,
    required this.kpiProgress,
    required this.recentAttendance,
  });

  factory DeptDashboardData.fromJson(Map<String, dynamic> json) {
    return DeptDashboardData(
      memberCount: json['member_count'] ?? 0,
      attendanceRateThisMonth:
          (json['attendance_rate_this_month'] ?? 0.0).toDouble(),
      kpiProgress: json['kpi_progress'] != null
          ? List<Map<String, dynamic>>.from(json['kpi_progress'])
          : [],
      recentAttendance: json['recent_attendance'] != null
          ? List<Map<String, dynamic>>.from(json['recent_attendance'])
          : [],
    );
  }
}

final deptDashboardProvider = FutureProvider<DeptDashboardData>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.deptDashboard);
  return DeptDashboardData.fromJson(response.data['data']);
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class DeptDashboard extends ConsumerWidget {
  const DeptDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShellLayout(
      title: 'Department Dashboard',
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(deptDashboardProvider.future),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ref.watch(deptDashboardProvider).when(
                loading: () => _buildSkeleton(),
                error: (e, _) => ErrorState(
                  message: e.toString().contains('403')
                      ? 'Access Denied'
                      : 'Failed to load dashboard',
                  onRetry: () => ref.invalidate(deptDashboardProvider),
                ),
                data: (data) => _buildContent(context, data),
              ),
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return Column(
      children: [
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.8,
          children: List.generate(3, (_) => const DashboardStatSkeleton()),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, DeptDashboardData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Overview', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        _buildStatsGrid(context, data),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _KpiProgressSection(kpiProgress: data.kpiProgress),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child:
                  _RecentAttendanceSection(attendance: data.recentAttendance),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildQuickLinks(context),
      ],
    );
  }

  Widget _buildStatsGrid(BuildContext context, DeptDashboardData data) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 900 ? 3 : 2;
    final items = [
      _StatItem(
        label: 'Total Members',
        value: '${data.memberCount}',
        icon: Icons.people_outline,
        color: AppColors.primary,
      ),
      _StatItem(
        label: 'Attendance Rate',
        value: '${data.attendanceRateThisMonth.toStringAsFixed(1)}%',
        icon: Icons.how_to_reg_outlined,
        color: AppColors.success,
        subtitle: 'This month',
      ),
      _StatItem(
        label: 'KPI Metrics',
        value: '${data.kpiProgress.length}',
        icon: Icons.track_changes_outlined,
        color: AppColors.secondary,
        subtitle: 'Active KPIs',
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

  Widget _buildQuickLinks(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Links', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _QuickLink(
              label: 'View Members',
              icon: Icons.people_outline,
              onTap: () => context.go('/dept/members'),
            ),
            _QuickLink(
              label: 'KPI Reports',
              icon: Icons.track_changes_outlined,
              onTap: () => context.go('/dept/kpi'),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// KPI Progress Section
// ---------------------------------------------------------------------------

class _KpiProgressSection extends StatelessWidget {
  final List<Map<String, dynamic>> kpiProgress;

  const _KpiProgressSection({required this.kpiProgress});

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
          Text('KPI Progress',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Current period targets',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          if (kpiProgress.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No KPI data available',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ...kpiProgress.map((kpi) => _KpiProgressBar(kpi: kpi)),
        ],
      ),
    );
  }
}

class _KpiProgressBar extends StatelessWidget {
  final Map<String, dynamic> kpi;

  const _KpiProgressBar({required this.kpi});

  @override
  Widget build(BuildContext context) {
    final name = kpi['name'] ?? '';
    final target = (kpi['target'] ?? 0.0).toDouble();
    final actual = (kpi['actual'] ?? 0.0).toDouble();
    final rate = target > 0 ? (actual / target).clamp(0.0, 1.0) : 0.0;
    final pct = (rate * 100).toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  name,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: rate >= 1.0
                      ? AppColors.success
                      : rate >= 0.7
                          ? AppColors.warning
                          : AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 8,
              backgroundColor: AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(
                rate >= 1.0
                    ? AppColors.success
                    : rate >= 0.7
                        ? AppColors.warning
                        : AppColors.error,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Actual: $actual / Target: $target',
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent Attendance Section
// ---------------------------------------------------------------------------

class _RecentAttendanceSection extends StatelessWidget {
  final List<Map<String, dynamic>> attendance;

  const _RecentAttendanceSection({required this.attendance});

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
          Text('Recent Attendance',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          if (attendance.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No attendance data',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ...attendance.take(5).map((record) => _AttendanceSummaryRow(
                  record: record,
                )),
        ],
      ),
    );
  }
}

class _AttendanceSummaryRow extends StatelessWidget {
  final Map<String, dynamic> record;

  const _AttendanceSummaryRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final date = record['date'] ?? '';
    final present = record['present'] ?? 0;
    final total = record['total'] ?? 0;
    final rate = total > 0 ? (present / total * 100).toStringAsFixed(0) : '0';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              date,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
          Text(
            '$present/$total',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$rate%',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
            ),
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

class _QuickLink extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickLink(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
          color: AppColors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
