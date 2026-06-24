import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/error_state.dart';
import '../../providers/follow_up_provider.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class FollowUpDashboardData {
  final int totalTasks;
  final int todayTasks;
  final int overdueTasks;
  final int completedThisMonth;
  final Map<String, int> tasksByStage;

  const FollowUpDashboardData({
    required this.totalTasks,
    required this.todayTasks,
    required this.overdueTasks,
    required this.completedThisMonth,
    required this.tasksByStage,
  });

  factory FollowUpDashboardData.fromJson(Map<String, dynamic> json) {
    return FollowUpDashboardData(
      totalTasks: json['total_tasks'] ?? 0,
      todayTasks: json['today_tasks'] ?? 0,
      overdueTasks: json['overdue_tasks'] ?? 0,
      completedThisMonth: json['completed_this_month'] ?? 0,
      tasksByStage: json['tasks_by_stage'] != null
          ? Map<String, int>.from(json['tasks_by_stage'])
          : {},
    );
  }
}

final followUpDashboardProvider =
    FutureProvider<FollowUpDashboardData>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.followUpDashboard);
  return FollowUpDashboardData.fromJson(response.data['data']);
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class FollowupDashboard extends ConsumerWidget {
  const FollowupDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShellLayout(
      title: 'Follow-up Dashboard',
      actions: [
        ElevatedButton.icon(
          icon: const Icon(Icons.person_add_outlined, size: 18),
          label: const Text('New Convert'),
          onPressed: () => context.go('/follow-up/new-convert'),
        ),
        const SizedBox(width: 8),
      ],
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(followUpDashboardProvider.future),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ref.watch(followUpDashboardProvider).when(
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
                      ref.invalidate(followUpDashboardProvider),
                ),
                data: (data) => _buildContent(context, data),
              ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, FollowUpDashboardData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('My Overview', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        _buildStatsGrid(context, data),
        const SizedBox(height: 24),
        _buildStageBreakdown(context, data.tasksByStage),
        const SizedBox(height: 24),
        _buildQuickActions(context),
      ],
    );
  }

  Widget _buildStatsGrid(BuildContext context, FollowUpDashboardData data) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 900 ? 4 : 2;

    final items = [
      _StatItem(
        label: 'Total Tasks',
        value: '${data.totalTasks}',
        icon: Icons.task_outlined,
        color: AppColors.primary,
      ),
      _StatItem(
        label: 'Due Today',
        value: '${data.todayTasks}',
        icon: Icons.today_outlined,
        color: AppColors.info,
        subtitle: 'Needs attention',
      ),
      _StatItem(
        label: 'Overdue',
        value: '${data.overdueTasks}',
        icon: Icons.warning_amber_outlined,
        color: AppColors.error,
        subtitle: 'Past due date',
      ),
      _StatItem(
        label: 'Completed',
        value: '${data.completedThisMonth}',
        icon: Icons.check_circle_outline,
        color: AppColors.success,
        subtitle: 'This month',
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

  Widget _buildStageBreakdown(
      BuildContext context, Map<String, int> stageData) {
    final stages = [
      FollowUpStage.initial,
      FollowUpStage.firstContact,
      FollowUpStage.secondContact,
      FollowUpStage.thirdContact,
      FollowUpStage.integrated,
    ];

    final total = stageData.values.fold<int>(0, (a, b) => a + b);

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
          Text('Tasks by Stage',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          if (total == 0)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No tasks',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ...stages.map((stage) {
              final count = stageData[stage.value] ?? 0;
              final rate = total > 0 ? count / total : 0.0;
              return _StagePipelineBar(
                stage: stage,
                count: count,
                rate: rate,
              );
            }),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _QuickAction(
              label: 'View All Tasks',
              icon: Icons.list_alt_outlined,
              onTap: () => context.go('/follow-up/tasks'),
            ),
            _QuickAction(
              label: 'New Convert',
              icon: Icons.person_add_outlined,
              onTap: () => context.go('/follow-up/new-convert'),
            ),
            _QuickAction(
              label: 'Search Member',
              icon: Icons.search_outlined,
              onTap: () => context.go('/follow-up/search'),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stage pipeline bar
// ---------------------------------------------------------------------------

class _StagePipelineBar extends StatelessWidget {
  final FollowUpStage stage;
  final int count;
  final double rate;

  const _StagePipelineBar({
    required this.stage,
    required this.count,
    required this.rate,
  });

  Color get _stageColor {
    switch (stage) {
      case FollowUpStage.initial:
        return AppColors.textSecondary;
      case FollowUpStage.firstContact:
        return AppColors.info;
      case FollowUpStage.secondContact:
        return AppColors.warning;
      case FollowUpStage.thirdContact:
        return AppColors.secondary;
      case FollowUpStage.integrated:
        return AppColors.success;
      case FollowUpStage.lost:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              stage.label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: rate,
                minHeight: 8,
                backgroundColor: AppColors.surfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(_stageColor),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _stageColor,
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
                  color: item.color.withValues(alpha: 0.12),
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

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickAction(
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
