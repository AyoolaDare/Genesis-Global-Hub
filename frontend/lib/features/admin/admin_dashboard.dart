import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/theme/app_colors.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';

// ---------------------------------------------------------------------------
// Dashboard stats model
// ---------------------------------------------------------------------------

class DashboardStats {
  final int totalMembers;
  final int activeMembers;
  final int pendingApprovals;
  final int totalDepartments;
  final int totalTeams;
  final int totalGroups;
  final int followUpTasks;
  final int todayFollowUps;
  final List<Map<String, dynamic>> memberGrowth;
  final List<Map<String, dynamic>> attendanceTrend;

  const DashboardStats({
    required this.totalMembers,
    required this.activeMembers,
    required this.pendingApprovals,
    required this.totalDepartments,
    required this.totalTeams,
    required this.totalGroups,
    required this.followUpTasks,
    required this.todayFollowUps,
    required this.memberGrowth,
    required this.attendanceTrend,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      totalMembers: json['total_members'] ?? 0,
      activeMembers: json['active_members'] ?? 0,
      pendingApprovals: json['pending_approvals'] ?? 0,
      totalDepartments: json['total_departments'] ?? 0,
      totalTeams: json['total_teams'] ?? 0,
      totalGroups: json['total_groups'] ?? 0,
      followUpTasks: json['follow_up_tasks'] ?? 0,
      todayFollowUps: json['today_follow_ups'] ?? 0,
      memberGrowth: json['member_growth'] != null
          ? List<Map<String, dynamic>>.from(json['member_growth'])
          : [],
      attendanceTrend: json['attendance_trend'] != null
          ? List<Map<String, dynamic>>.from(json['attendance_trend'])
          : [],
    );
  }
}

final adminDashboardProvider = FutureProvider<DashboardStats>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.adminDashboard);
  return DashboardStats.fromJson(response.data['data']);
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShellLayout(
      title: 'Dashboard',
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(adminDashboardProvider.future),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ref.watch(adminDashboardProvider).when(
                loading: () => _buildSkeleton(),
                error: (e, _) => Center(
                  child: Column(
                    children: [
                      Text('Failed to load dashboard: $e'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () =>
                            ref.invalidate(adminDashboardProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (stats) => _buildContent(context, stats),
              ),
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return Column(
      children: [
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.8,
          children: List.generate(
              8, (_) => const DashboardStatSkeleton()),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, DashboardStats stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Overview',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        _StatsGrid(stats: stats),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _MemberGrowthChart(data: stats.memberGrowth),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: _AttendanceChart(data: stats.attendanceTrend),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _QuickActions(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stats grid
// ---------------------------------------------------------------------------

class _StatsGrid extends StatelessWidget {
  final DashboardStats stats;

  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 1200
        ? 4
        : screenWidth > 800
            ? 3
            : 2;

    final statItems = [
      _StatItem(
        label: 'Total Members',
        value: '${stats.totalMembers}',
        icon: Icons.people,
        color: AppColors.primary,
        subtitle: '${stats.activeMembers} active',
      ),
      _StatItem(
        label: 'Pending Approvals',
        value: '${stats.pendingApprovals}',
        icon: Icons.pending_actions,
        color: AppColors.warning,
        subtitle: 'Needs review',
      ),
      _StatItem(
        label: 'Departments',
        value: '${stats.totalDepartments}',
        icon: Icons.business,
        color: AppColors.info,
        subtitle: '${stats.totalTeams} teams',
      ),
      _StatItem(
        label: 'Groups',
        value: '${stats.totalGroups}',
        icon: Icons.group,
        color: AppColors.success,
        subtitle: 'Active groups',
      ),
      _StatItem(
        label: 'Follow-up Tasks',
        value: '${stats.followUpTasks}',
        icon: Icons.task_alt,
        color: AppColors.secondary,
        subtitle: '${stats.todayFollowUps} due today',
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
      itemCount: statItems.length,
      itemBuilder: (_, i) => _StatCard(item: statItems[i]),
    );
  }
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

// ---------------------------------------------------------------------------
// Charts
// ---------------------------------------------------------------------------

class _MemberGrowthChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const _MemberGrowthChart({required this.data});

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
          Text('Member Growth', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Monthly new members',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: data.isEmpty
                ? const Center(child: Text('No data available'))
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) => const FlLine(
                          color: AppColors.border,
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (value, _) => Text(
                              value.toInt().toString(),
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, _) {
                              final idx = value.toInt();
                              if (idx >= 0 && idx < data.length) {
                                return Text(
                                  data[idx]['label']?.toString() ?? '',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textSecondary),
                                );
                              }
                              return const Text('');
                            },
                          ),
                        ),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: data.asMap().entries.map((e) {
                            return FlSpot(e.key.toDouble(),
                                (e.value['value'] ?? 0).toDouble());
                          }).toList(),
                          isCurved: true,
                          color: AppColors.primary,
                          barWidth: 3,
                          belowBarData: BarAreaData(
                            show: true,
                            color: AppColors.primary.withOpacity(0.08),
                          ),
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const _AttendanceChart({required this.data});

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
          Text('Attendance Rate',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Last 6 months',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: data.isEmpty
                ? const Center(child: Text('No data available'))
                : BarChart(
                    BarChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, _) {
                              final idx = value.toInt();
                              if (idx >= 0 && idx < data.length) {
                                return Text(
                                  data[idx]['label']?.toString() ?? '',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textSecondary),
                                );
                              }
                              return const Text('');
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: data.asMap().entries.map((e) {
                        return BarChartGroupData(
                          x: e.key,
                          barRods: [
                            BarChartRodData(
                              toY: (e.value['value'] ?? 0).toDouble(),
                              color: AppColors.secondary,
                              width: 24,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick actions
// ---------------------------------------------------------------------------

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _QuickActionButton(
              label: 'Add Member',
              icon: Icons.person_add_outlined,
              onTap: () => Navigator.of(context)
                  .pushNamed('/admin/members/create'),
            ),
            _QuickActionButton(
              label: 'Pending Approvals',
              icon: Icons.pending_actions_outlined,
              onTap: () =>
                  Navigator.of(context).pushNamed('/admin/pending'),
            ),
            _QuickActionButton(
              label: 'View Audit Log',
              icon: Icons.history_outlined,
              onTap: () =>
                  Navigator.of(context).pushNamed('/admin/audit'),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

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
