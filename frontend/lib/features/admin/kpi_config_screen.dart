import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/kpi_provider.dart';

class KpiConfigScreen extends ConsumerWidget {
  const KpiConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpiAsync = ref.watch(kpiConfigsProvider);
    return ShellLayout(
      title: 'KPI Configuration',
      actions: [
        ElevatedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add KPI'),
        ),
        const SizedBox(width: 16),
      ],
      child: kpiAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: 'Failed to load KPI configs',
          onRetry: () => ref.invalidate(kpiConfigsProvider),
        ),
        data: (configs) {
          if (configs.isEmpty) {
            return const EmptyState(
              icon: Icons.track_changes_outlined,
              title: 'No KPIs configured',
              subtitle: 'Add KPI configurations for departments',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: configs.length,
            itemBuilder: (_, i) => _KpiConfigCard(config: configs[i]),
          );
        },
      ),
    );
  }
}

class _KpiConfigCard extends StatelessWidget {
  final KpiConfig config;

  const _KpiConfigCard({required this.config});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.track_changes,
              color: AppColors.secondary),
        ),
        title: Text(config.name,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(config.description),
            const SizedBox(height: 4),
            Text(
              'Target: ${config.target} ${config.unit} | ${config.frequency}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: config.isActive
                    ? AppColors.success.withValues(alpha: 0.1)
                    : AppColors.statusInactive.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                config.isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: config.isActive
                      ? AppColors.success
                      : AppColors.statusInactive,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  size: 18, color: AppColors.textSecondary),
              onPressed: () {},
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}
