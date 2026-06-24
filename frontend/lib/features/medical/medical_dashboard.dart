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

class MedicalDashboardData {
  final int totalPatients;
  final int visitsThisMonth;
  final int pendingFollowUps;
  final List<Map<String, dynamic>> recentVisits;

  const MedicalDashboardData({
    required this.totalPatients,
    required this.visitsThisMonth,
    required this.pendingFollowUps,
    required this.recentVisits,
  });

  factory MedicalDashboardData.fromJson(Map<String, dynamic> json) {
    return MedicalDashboardData(
      totalPatients: json['total_patients'] ?? 0,
      visitsThisMonth: json['visits_this_month'] ?? 0,
      pendingFollowUps: json['pending_follow_ups'] ?? 0,
      recentVisits: json['recent_visits'] != null
          ? List<Map<String, dynamic>>.from(json['recent_visits'])
          : [],
    );
  }
}

final medicalDashboardProvider =
    FutureProvider<MedicalDashboardData>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.medicalDashboard);
  return MedicalDashboardData.fromJson(response.data['data']);
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class MedicalDashboard extends ConsumerWidget {
  const MedicalDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShellLayout(
      title: 'Medical Dashboard',
      actions: [
        ElevatedButton.icon(
          icon: const Icon(Icons.person_add_outlined, size: 18),
          label: const Text('Add Patient'),
          onPressed: () => context.go('/medical/patients/new'),
        ),
        const SizedBox(width: 8),
      ],
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(medicalDashboardProvider.future),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ref.watch(medicalDashboardProvider).when(
                loading: () => Column(
                  children: [
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.8,
                      children: List.generate(
                          3, (_) => const DashboardStatSkeleton()),
                    ),
                  ],
                ),
                error: (e, _) => ErrorState(
                  message: e.toString().contains('403')
                      ? 'Access Denied'
                      : 'Failed to load dashboard',
                  onRetry: () =>
                      ref.invalidate(medicalDashboardProvider),
                ),
                data: (data) => _buildContent(context, data),
              ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, MedicalDashboardData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Medical Overview',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        _buildStatsGrid(context, data),
        const SizedBox(height: 24),
        _buildRecentVisits(context, data.recentVisits),
        const SizedBox(height: 24),
        _buildQuickActions(context),
      ],
    );
  }

  Widget _buildStatsGrid(BuildContext context, MedicalDashboardData data) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 900 ? 3 : 2;

    final items = [
      _StatItem(
        label: 'Total Patients',
        value: '${data.totalPatients}',
        icon: Icons.sick_outlined,
        color: AppColors.primary,
        subtitle: 'All time',
      ),
      _StatItem(
        label: 'Visits This Month',
        value: '${data.visitsThisMonth}',
        icon: Icons.medical_services_outlined,
        color: AppColors.info,
      ),
      _StatItem(
        label: 'Pending Follow-ups',
        value: '${data.pendingFollowUps}',
        icon: Icons.assignment_late_outlined,
        color: AppColors.warning,
        subtitle: 'Need attention',
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

  Widget _buildRecentVisits(
      BuildContext context, List<Map<String, dynamic>> visits) {
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
              Text('Recent Visits',
                  style: Theme.of(context).textTheme.titleMedium),
              TextButton(
                onPressed: () => context.go('/medical/patients'),
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (visits.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No recent visits',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(3),
              },
              children: [
                TableRow(
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                  ),
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Text('Patient',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary)),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Text('Date',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary)),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Text('Diagnosis',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary)),
                    ),
                  ],
                ),
                ...visits.take(8).map(
                      (visit) => TableRow(
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: AppColors.border),
                          ),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(
                              visit['patient_name'] ?? '',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(
                              visit['date'] ?? '',
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(
                              visit['diagnosis'] ?? '',
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
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

  Widget _buildQuickActions(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _QuickAction(
          label: 'My Patients',
          icon: Icons.sick_outlined,
          onTap: () => context.go('/medical/patients'),
        ),
        _QuickAction(
          label: 'Add Patient',
          icon: Icons.person_add_outlined,
          onTap: () => context.go('/medical/patients/new'),
        ),
      ],
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
