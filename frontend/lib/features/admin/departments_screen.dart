import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/structure_provider.dart';

class DepartmentsScreen extends ConsumerWidget {
  const DepartmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deptAsync = ref.watch(departmentsProvider);
    return ShellLayout(
      title: 'Departments',
      actions: [
        ElevatedButton.icon(
          onPressed: () => _showCreateDialog(context),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New Department'),
        ),
        const SizedBox(width: 16),
      ],
      child: deptAsync.when(
        loading: () => GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.5,
          ),
          itemCount: 6,
          itemBuilder: (_, __) => const DashboardStatSkeleton(),
        ),
        error: (e, _) => ErrorState(
          message: 'Failed to load departments',
          onRetry: () => ref.invalidate(departmentsProvider),
        ),
        data: (departments) {
          if (departments.isEmpty) {
            return const EmptyState(
              icon: Icons.business_outlined,
              title: 'No departments yet',
              subtitle: 'Create a department to get started',
            );
          }
          final screenWidth = MediaQuery.of(context).size.width;
          final crossAxisCount = screenWidth > 1200 ? 3 : screenWidth > 800 ? 2 : 1;
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.6,
            ),
            itemCount: departments.length,
            itemBuilder: (_, i) =>
                _DepartmentCard(department: departments[i]),
          );
        },
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Create Department'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Department Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _DepartmentCard extends StatelessWidget {
  final Department department;

  const _DepartmentCard({required this.department});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
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
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.business,
                    color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  department.name,
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (department.description != null)
            Text(
              department.description!,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const Spacer(),
          Row(
            children: [
              _InfoChip(
                  label: '${department.memberCount} members',
                  icon: Icons.people_outline),
              const SizedBox(width: 8),
              _InfoChip(
                  label: '${department.teamCount} teams',
                  icon: Icons.groups_outlined),
            ],
          ),
          if (department.headName != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person_outline,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  department.headName!,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _InfoChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
