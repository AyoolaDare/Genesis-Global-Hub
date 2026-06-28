import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../providers/kpi_provider.dart';
import '../../providers/structure_provider.dart';

class KpiConfigScreen extends ConsumerWidget {
  const KpiConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpiAsync = ref.watch(kpiConfigsProvider);
    return ShellLayout(
      title: 'KPI Configuration',
      actions: [
        ElevatedButton.icon(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const _CreateKpiDialog(),
          ),
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

class _CreateKpiDialog extends ConsumerStatefulWidget {
  const _CreateKpiDialog();

  @override
  ConsumerState<_CreateKpiDialog> createState() => _CreateKpiDialogState();
}

class _CreateKpiDialogState extends ConsumerState<_CreateKpiDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _targetController = TextEditingController();
  final _unitController = TextEditingController();
  String _entityType = 'DEPARTMENT';
  String? _entityId;
  String _period = 'MONTHLY';
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _targetController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_entityId == null) {
      setState(() => _error = 'Please choose where this KPI belongs.');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      await dio.post(ApiEndpoints.kpiConfigs, data: {
        'name': _nameController.text.trim(),
        if (_descriptionController.text.trim().isNotEmpty)
          'description': _descriptionController.text.trim(),
        'entity_type': _entityType,
        'entity_id': _entityId,
        if (_targetController.text.trim().isNotEmpty)
          'target_value': double.tryParse(_targetController.text.trim()) ?? 0,
        if (_unitController.text.trim().isNotEmpty)
          'target_unit': _unitController.text.trim(),
        'period': _period,
        'is_active': true,
      });
      ref.invalidate(kpiConfigsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = ApiException.from(e)?.message ?? 'Failed to create KPI.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final departments = ref.watch(departmentsProvider);
    final teams = ref.watch(teamsProvider);
    final groups = ref.watch(groupsProvider);

    final entityPicker = switch (_entityType) {
      'TEAM' => teams.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Could not load teams'),
          data: (items) => _entityDropdown(
            items.map((e) => MapEntry(e.id, e.name)).toList(),
          ),
        ),
      'GROUP' => groups.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Could not load groups'),
          data: (items) => _entityDropdown(
            items.map((e) => MapEntry(e.id, e.name)).toList(),
          ),
        ),
      _ => departments.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Could not load departments'),
          data: (items) => _entityDropdown(
            items.map((e) => MapEntry(e.id, e.name)).toList(),
          ),
        ),
    };

    return AlertDialog(
      title: const Text('Create KPI'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'KPI Name *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Name is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _entityType,
                  decoration: const InputDecoration(labelText: 'Applies To'),
                  items: const [
                    DropdownMenuItem(value: 'DEPARTMENT', child: Text('Department')),
                    DropdownMenuItem(value: 'TEAM', child: Text('Team')),
                    DropdownMenuItem(value: 'GROUP', child: Text('Group')),
                  ],
                  onChanged: (v) => setState(() {
                    _entityType = v ?? 'DEPARTMENT';
                    _entityId = null;
                  }),
                ),
                const SizedBox(height: 12),
                entityPicker,
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _targetController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Target'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _unitController,
                        decoration: const InputDecoration(labelText: 'Unit'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _period,
                  decoration: const InputDecoration(labelText: 'Period'),
                  items: const [
                    DropdownMenuItem(value: 'MONTHLY', child: Text('Monthly')),
                    DropdownMenuItem(value: 'QUARTERLY', child: Text('Quarterly')),
                    DropdownMenuItem(value: 'ANNUAL', child: Text('Annual')),
                  ],
                  onChanged: (v) => setState(() => _period = v ?? 'MONTHLY'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: Text(_isSaving ? 'Saving...' : 'Create KPI'),
        ),
      ],
    );
  }

  Widget _entityDropdown(List<MapEntry<String, String>> items) {
    return DropdownButtonFormField<String>(
      value: _entityId,
      decoration: const InputDecoration(labelText: 'Select Entity *'),
      items: items
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: (v) => setState(() => _entityId = v),
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
            color: AppColors.secondary.withOpacity(0.15),
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
                    ? AppColors.success.withOpacity(0.1)
                    : AppColors.statusInactive.withOpacity(0.1),
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
