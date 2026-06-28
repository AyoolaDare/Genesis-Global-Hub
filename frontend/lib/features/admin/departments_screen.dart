import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
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
    final teamsAsync = ref.watch(teamsProvider);
    final groupsAsync = ref.watch(groupsProvider);
    return ShellLayout(
      title: 'Church Structure',
      actions: [
        ElevatedButton.icon(
          onPressed: () => _showCreateDialog(context, ref),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New Department'),
        ),
        const SizedBox(width: 16),
      ],
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            Container(
              color: AppColors.white,
              child: const TabBar(
                tabs: [
                  Tab(text: 'Departments'),
                  Tab(text: 'Teams'),
                  Tab(text: 'Groups'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _DepartmentsGrid(
                    deptAsync: deptAsync,
                    onCreate: () => _showCreateDialog(context, ref),
                  ),
                  _StructureList<Team>(
                    asyncValue: teamsAsync,
                    emptyIcon: Icons.groups_outlined,
                    emptyTitle: 'No teams yet',
                    itemIcon: Icons.groups_outlined,
                    titleOf: (team) => team.name,
                    subtitleOf: (team) => 'Department ID: ${team.departmentId}',
                    trailingOf: (team) => '${team.memberCount} members',
                  ),
                  _StructureList<Group>(
                    asyncValue: groupsAsync,
                    emptyIcon: Icons.diversity_3_outlined,
                    emptyTitle: 'No groups yet',
                    itemIcon: Icons.diversity_3_outlined,
                    titleOf: (group) => group.name,
                    subtitleOf: (group) =>
                        group.teamId != null ? 'Team ID: ${group.teamId}' : 'Department ID: ${group.departmentId ?? 'N/A'}',
                    trailingOf: (group) => '${group.memberCount} members',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _CreateDepartmentDialog(
        onCreated: () => ref.invalidate(departmentsProvider),
      ),
    );
  }
}

class _DepartmentsGrid extends StatelessWidget {
  final AsyncValue<List<Department>> deptAsync;
  final VoidCallback onCreate;

  const _DepartmentsGrid({
    required this.deptAsync,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return deptAsync.when(
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
      error: (e, _) => const ErrorState(
        message: 'Failed to load departments',
      ),
      data: (departments) {
        if (departments.isEmpty) {
          return EmptyState(
            icon: Icons.business_outlined,
            title: 'No departments yet',
            subtitle: 'Create a department to get started',
            actionLabel: 'New Department',
            onAction: onCreate,
          );
        }
        final screenWidth = MediaQuery.of(context).size.width;
        final crossAxisCount =
            screenWidth > 1200 ? 3 : screenWidth > 800 ? 2 : 1;
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.6,
          ),
          itemCount: departments.length,
          itemBuilder: (_, i) => _DepartmentCard(department: departments[i]),
        );
      },
    );
  }
}

class _StructureList<T> extends StatelessWidget {
  final AsyncValue<List<T>> asyncValue;
  final IconData emptyIcon;
  final String emptyTitle;
  final IconData itemIcon;
  final String Function(T item) titleOf;
  final String Function(T item) subtitleOf;
  final String Function(T item) trailingOf;

  const _StructureList({
    required this.asyncValue,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.itemIcon,
    required this.titleOf,
    required this.subtitleOf,
    required this.trailingOf,
  });

  @override
  Widget build(BuildContext context) {
    return asyncValue.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(message: 'Failed to load $emptyTitle'),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            icon: emptyIcon,
            title: emptyTitle,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final item = items[i];
            return Card(
              child: ListTile(
                leading: Icon(itemIcon, color: AppColors.primary),
                title: Text(titleOf(item)),
                subtitle: Text(subtitleOf(item)),
                trailing: Text(
                  trailingOf(item),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Create department dialog — handles its own state + API call
// ---------------------------------------------------------------------------

class _CreateDepartmentDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;

  const _CreateDepartmentDialog({required this.onCreated});

  @override
  ConsumerState<_CreateDepartmentDialog> createState() =>
      _CreateDepartmentDialogState();
}

class _CreateDepartmentDialogState
    extends ConsumerState<_CreateDepartmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      await dio.post(ApiEndpoints.departments, data: {
        'name': _nameController.text.trim(),
        if (_descController.text.trim().isNotEmpty)
          'description': _descController.text.trim(),
      });
      widget.onCreated();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final apiError = ApiException.from(e);
      setState(() {
        _isLoading = false;
        if (apiError is ForbiddenException) {
          _error = 'Permission denied. Only super-admins and pastors can create departments.';
        } else if (apiError is UnauthorizedException) {
          _error = 'Your session has expired. Please log in again.';
        } else if (apiError != null &&
            (apiError.statusCode == 409 ||
                apiError.message.toLowerCase().contains('already exists'))) {
          _error = 'A department with this name already exists.';
        } else {
          _error = apiError?.message ?? 'Failed to create department. Please try again.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Department'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.error, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Department Name *',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Name is required' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.white),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Department card
// ---------------------------------------------------------------------------

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
