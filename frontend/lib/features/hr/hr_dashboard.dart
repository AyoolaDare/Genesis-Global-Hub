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

class HrDashboardData {
  final int totalWorkers;
  final int activeWorkers;
  final int volunteers;
  final int pendingLeave;
  final List<Map<String, dynamic>> deptBreakdown;
  final List<Map<String, dynamic>> pendingLeaveRequests;

  const HrDashboardData({
    required this.totalWorkers,
    required this.activeWorkers,
    required this.volunteers,
    required this.pendingLeave,
    required this.deptBreakdown,
    required this.pendingLeaveRequests,
  });

  factory HrDashboardData.fromJson(Map<String, dynamic> json) {
    return HrDashboardData(
      totalWorkers: json['total_workers'] ?? 0,
      activeWorkers: json['active_workers'] ?? 0,
      volunteers: json['volunteers'] ?? 0,
      pendingLeave: json['pending_leave'] ?? 0,
      deptBreakdown: json['dept_breakdown'] != null
          ? List<Map<String, dynamic>>.from(json['dept_breakdown'])
          : [],
      pendingLeaveRequests: json['pending_leave_requests'] != null
          ? List<Map<String, dynamic>>.from(json['pending_leave_requests'])
          : [],
    );
  }
}

final hrDashboardProvider = FutureProvider<HrDashboardData>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.hrDashboard);
  return HrDashboardData.fromJson(response.data['data']);
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class HrDashboard extends ConsumerWidget {
  const HrDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShellLayout(
      title: 'HR Dashboard',
      actions: [
        ElevatedButton.icon(
          icon: const Icon(Icons.people_outline, size: 18),
          label: const Text('Workers'),
          onPressed: () => context.go('/hr/workers'),
        ),
        const SizedBox(width: 8),
      ],
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(hrDashboardProvider.future),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ref.watch(hrDashboardProvider).when(
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
                    const SizedBox(height: 24),
                    const SkeletonBox(height: 240),
                  ],
                ),
                error: (e, _) => ErrorState(
                  message: e.toString().contains('403')
                      ? 'Access Denied'
                      : 'Failed to load HR dashboard',
                  onRetry: () => ref.invalidate(hrDashboardProvider),
                ),
                data: (data) => _buildContent(context, ref, data),
              ),
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, WidgetRef ref, HrDashboardData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('HR Overview',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        _buildStatsGrid(context, data),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _DeptBreakdownCard(
                  breakdown: data.deptBreakdown,
                  total: data.totalWorkers),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _PendingLeaveCard(
                requests: data.pendingLeaveRequests,
                onViewAll: () => context.go('/hr/workers'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsGrid(BuildContext context, HrDashboardData data) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 900 ? 4 : 2;

    final items = [
      _StatItem(
        label: 'Total Workers',
        value: '${data.totalWorkers}',
        icon: Icons.people_outline,
        color: AppColors.primary,
      ),
      _StatItem(
        label: 'Active',
        value: '${data.activeWorkers}',
        icon: Icons.check_circle_outline,
        color: AppColors.success,
      ),
      _StatItem(
        label: 'Volunteers',
        value: '${data.volunteers}',
        icon: Icons.volunteer_activism_outlined,
        color: AppColors.secondary,
      ),
      _StatItem(
        label: 'Pending Leave',
        value: '${data.pendingLeave}',
        icon: Icons.event_busy_outlined,
        color: AppColors.warning,
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
// Department breakdown card with bar chart
// ---------------------------------------------------------------------------

class _DeptBreakdownCard extends StatelessWidget {
  final List<Map<String, dynamic>> breakdown;
  final int total;

  const _DeptBreakdownCard(
      {required this.breakdown, required this.total});

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
          Text('Department Breakdown',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 20),
          if (breakdown.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No department data',
                    style:
                        TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ...breakdown.map((dept) => _DeptBar(
                  dept: dept['name'] ?? 'Unknown',
                  count: dept['count'] ?? 0,
                  total: total,
                )),
        ],
      ),
    );
  }
}

class _DeptBar extends StatelessWidget {
  final String dept;
  final int count;
  final int total;

  const _DeptBar(
      {required this.dept, required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(dept,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
              Text('$count',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            backgroundColor: AppColors.border,
            valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pending leave requests card
// ---------------------------------------------------------------------------

class _PendingLeaveCard extends StatelessWidget {
  final List<Map<String, dynamic>> requests;
  final VoidCallback onViewAll;

  const _PendingLeaveCard(
      {required this.requests, required this.onViewAll});

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
              Text('Pending Leave',
                  style: Theme.of(context).textTheme.titleMedium),
              TextButton(
                  onPressed: onViewAll,
                  child: const Text('View All')),
            ],
          ),
          const SizedBox(height: 16),
          if (requests.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No pending requests',
                    style:
                        TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ...requests
                .take(6)
                .map((r) => _LeaveRequestRow(request: r)),
        ],
      ),
    );
  }
}

class _LeaveRequestRow extends StatelessWidget {
  final Map<String, dynamic> request;

  const _LeaveRequestRow({required this.request});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: AppColors.warning.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request['worker_name'] ?? '',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  request['leave_type'] ?? '',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            request['days'] != null ? '${request["days"]}d' : '',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.warning),
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

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
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
            style:
                Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
          ),
        ],
      ),
    );
  }
}
