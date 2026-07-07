import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/pagination_footer.dart';
import '../../providers/hr_provider.dart';
import '../../providers/members_provider.dart';

String _formatWorkerType(String type) {
  final words = type.toLowerCase().split('_');
  return words
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class WorkersListScreen extends ConsumerStatefulWidget {
  const WorkersListScreen({super.key});

  @override
  ConsumerState<WorkersListScreen> createState() =>
      _WorkersListScreenState();
}

class _WorkersListScreenState extends ConsumerState<WorkersListScreen> {
  int _page = 1;
  String _search = '';
  String? _deptFilter;
  String? _typeFilter;
  final _searchController = TextEditingController();

  static const List<String> _employmentTypes = [
    'FULL_TIME',
    'PART_TIME',
    'VOLUNTEER',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_searchController.text == value) {
        setState(() {
          _search = value;
          _page = 1;
        });
        ref.read(hrProvider.notifier).refresh(
              search: value.isNotEmpty ? value : null,
            );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final workersAsync = ref.watch(hrProvider);

    return ShellLayout(
      title: 'Workers',
      actions: [
        ElevatedButton.icon(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const _CreateWorkerDialog(),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Worker'),
        ),
        const SizedBox(width: 16),
      ],
      child: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: workersAsync.when(
              loading: () => Padding(
                padding: const EdgeInsets.all(24),
                child: ListSkeleton(
                  count: 5,
                  itemBuilder: () => const MemberCardSkeleton(),
                ),
              ),
              error: (e, _) => ErrorState(
                message: e.toString().contains('403')
                    ? 'Access Denied'
                    : 'Failed to load workers',
                onRetry: () => ref.invalidate(hrProvider),
              ),
              data: (workers) {
                var items = workers.items;
                if (_typeFilter != null) {
                  items = items
                      .where((w) => w.employmentType == _typeFilter)
                      .toList();
                }
                if (_deptFilter != null && _deptFilter!.isNotEmpty) {
                  items = items
                      .where((w) =>
                          w.department?.toLowerCase() ==
                          _deptFilter!.toLowerCase())
                      .toList();
                }
                return items.isEmpty
                    ? EmptyState(
                        icon: Icons.people_outline,
                        title: 'No workers found',
                        subtitle: _search.isNotEmpty
                            ? 'No workers match "$_search"'
                            : 'No workers match the selected filters.',
                      )
                    : _buildList(items, workers);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final search = TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search workers...',
              prefixIcon: const Icon(Icons.search,
                  color: AppColors.textSecondary),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _search = '';
                          _page = 1;
                        });
                        ref.read(hrProvider.notifier).refresh();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            ),
            onChanged: _onSearchChanged,
          );
          final typeFilter = _FilterDropdown(
            hint: 'Employment Type',
            selected: _typeFilter,
            items: _employmentTypes
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(_formatWorkerType(t)),
                    ))
                .toList(),
            onChanged: (v) => setState(() {
              _typeFilter = v;
              _page = 1;
            }),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 12),
                typeFilter,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 12),
              SizedBox(width: 220, child: typeFilter),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(List<Worker> items, WorkersList full) {
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _WorkerCard(
              worker: items[i],
              index: (full.page - 1) * 20 + i + 1,
            ),
          ),
        ),
        PaginationFooter(
          currentPage: _page,
          totalPages: full.totalPages,
          totalItems: full.total,
          pageSize: 20,
          onPageChanged: (p) {
            setState(() => _page = p);
            ref.read(hrProvider.notifier).refresh(page: p);
          },
        ),
      ],
    );
  }
}

class _CreateWorkerDialog extends ConsumerStatefulWidget {
  const _CreateWorkerDialog();

  @override
  ConsumerState<_CreateWorkerDialog> createState() => _CreateWorkerDialogState();
}

class _CreateWorkerDialogState extends ConsumerState<_CreateWorkerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _memberSearchController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _roleController = TextEditingController();
  String _employmentType = 'VOLUNTEER';
  MemberLookupResult? _selectedMember;
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _memberSearchController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _roleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      await dio.post(ApiEndpoints.workers, data: {
        'member_id': _selectedMember?.id,
        'full_name': _nameController.text.trim(),
        if (_phoneController.text.trim().isNotEmpty)
          'phone': _phoneController.text.trim(),
        if (_emailController.text.trim().isNotEmpty)
          'email': _emailController.text.trim(),
        if (_roleController.text.trim().isNotEmpty)
          'role_title': _roleController.text.trim(),
        'employment_type': _employmentType,
      });
      ref.invalidate(hrProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final apiError = ApiException.from(e);
      final message = apiError is ValidationException
          ? apiError.fieldSummary
          : apiError?.message ?? 'Failed to create worker.';
      setState(() {
        _isSaving = false;
        _error = message;
      });
    }
  }

  void _applyMember(MemberLookupResult member) {
    setState(() {
      _selectedMember = member;
      _nameController.text = member.fullName;
      _phoneController.text = member.phone ?? '';
      _emailController.text = member.email ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
      title: const _DialogHeader(),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) ...[
                  _ErrorBanner(message: _error!),
                  const SizedBox(height: 16),
                ],
                _SectionLabel(
                  number: '01',
                  label: _selectedMember == null
                      ? 'Link a church member'
                      : 'Linked church member',
                ),
                const SizedBox(height: 10),
                if (_selectedMember != null) ...[
                  _SelectedMemberPanel(
                    member: _selectedMember!,
                    onClear: () => setState(() => _selectedMember = null),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _memberSearchController,
                  decoration: const InputDecoration(
                    labelText: 'Find member',
                    hintText: 'Search by name or phone',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search_outlined),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _WorkerMemberLookup(
                  query: _memberSearchController.text,
                  selected: _selectedMember,
                  onSelected: _applyMember,
                ),
                const SizedBox(height: 20),
                const _SectionLabel(number: '02', label: 'Worker profile'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Name is required' : null,
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 520;
                    final phone = TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        border: OutlineInputBorder(),
                      ),
                    );
                    final email = TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    );
                    if (compact) {
                      return Column(
                        children: [
                          phone,
                          const SizedBox(height: 12),
                          email,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: phone),
                        const SizedBox(width: 12),
                        Expanded(child: email),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 520;
                    final role = TextFormField(
                      controller: _roleController,
                      decoration: const InputDecoration(
                        labelText: 'Role / Duty',
                        border: OutlineInputBorder(),
                      ),
                    );
                    final type = DropdownButtonFormField<String>(
                      value: _employmentType,
                      decoration: const InputDecoration(
                        labelText: 'Worker Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'VOLUNTEER', child: Text('Volunteer')),
                        DropdownMenuItem(
                            value: 'PART_TIME', child: Text('Part Time')),
                        DropdownMenuItem(
                            value: 'FULL_TIME', child: Text('Full Time')),
                      ],
                      onChanged: (v) =>
                          setState(() => _employmentType = v ?? 'VOLUNTEER'),
                    );
                    if (compact) {
                      return Column(
                        children: [
                          role,
                          const SizedBox(height: 12),
                          type,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: role),
                        const SizedBox(width: 12),
                        SizedBox(width: 210, child: type),
                      ],
                    );
                  },
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
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create Worker'),
        ),
      ],
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(
            'HR',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
        Expanded(
          child: Text(
            'Add Worker',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String number;
  final String label;

  const _SectionLabel({required this.number, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          number,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.only(top: 1),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withOpacity(0.35)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.error, fontSize: 12),
      ),
    );
  }
}

class _SelectedMemberPanel extends StatelessWidget {
  final MemberLookupResult member;
  final VoidCallback onClear;

  const _SelectedMemberPanel({required this.member, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          _Avatar(name: member.fullName),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  member.phone ?? member.email ?? 'No contact detail',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Clear linked member',
            onPressed: onClear,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _WorkerMemberLookup extends ConsumerWidget {
  final String query;
  final MemberLookupResult? selected;
  final ValueChanged<MemberLookupResult> onSelected;

  const _WorkerMemberLookup({
    required this.query,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().length < 2) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: const Text(
          'Search is optional. Leave blank to create a new worker profile.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    }
    final results = ref.watch(memberLookupProvider(query));
    return results.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text(
        'Could not search members: $e',
        style: const TextStyle(color: AppColors.error, fontSize: 12),
      ),
      data: (members) {
        if (members.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text(
              'No matching members found.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          );
        }
        return Column(
          children: members
              .take(5)
              .map(
                (m) => _MemberLookupRow(
                  member: m,
                  selected: selected?.id == m.id,
                  onSelected: () => onSelected(m),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _MemberLookupRow extends StatelessWidget {
  final MemberLookupResult member;
  final bool selected;
  final VoidCallback onSelected;

  const _MemberLookupRow({
    required this.member,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.06) : AppColors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppColors.primary.withOpacity(0.55)
                : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.fullName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    member.phone ?? member.email ?? 'No contact detail',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Worker card
// ---------------------------------------------------------------------------

class _WorkerCard extends StatelessWidget {
  final Worker worker;
  final int index;

  const _WorkerCard({required this.worker, required this.index});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/hr/workers/${worker.id}'),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(
                index.toString().padLeft(2, '0'),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _Avatar(name: worker.fullName),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          worker.fullName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      _TypeBadge(type: worker.employmentType),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    worker.role,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                  if (worker.department != null)
                    Text(
                      worker.department!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
            _StatusDot(status: worker.status),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right,
                size: 20, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;

  const _Avatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().split(' ').take(2).map((s) => s.isNotEmpty ? s[0].toUpperCase() : '').join();
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;

  const _TypeBadge({required this.type});

  Color get _color {
    switch (type.toUpperCase()) {
      case 'FULL_TIME':
        return AppColors.primary;
      case 'PART_TIME':
        return AppColors.info;
      case 'VOLUNTEER':
        return AppColors.secondary;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withOpacity(0.3)),
      ),
      child: Text(
        _formatWorkerType(type),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: _color,
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final String status;

  const _StatusDot({required this.status});

  Color get _color {
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        return AppColors.success;
      case 'INACTIVE':
        return AppColors.error;
      case 'ON_LEAVE':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: _color,
        shape: BoxShape.circle,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable filter dropdown (plain DropdownButton to avoid false positives)
// ---------------------------------------------------------------------------

class _FilterDropdown extends StatelessWidget {
  final String hint;
  final String? selected;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  const _FilterDropdown({
    required this.hint,
    required this.selected,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
        color: AppColors.white,
      ),
      child: DropdownButton<String>(
        value: selected,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        hint: Text(hint,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary)),
        items: [
          DropdownMenuItem<String>(value: null, child: Text(hint)),
          ...items,
        ],
        onChanged: onChanged,
      ),
    );
  }
}
