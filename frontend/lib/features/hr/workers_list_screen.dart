import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/pagination_footer.dart';
import '../../providers/hr_provider.dart';

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
    'CONTRACT',
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
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search workers...',
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textSecondary),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
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
                  borderSide:
                      const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: AppColors.border),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 180,
            child: _FilterDropdown(
              hint: 'Employment Type',
              selected: _typeFilter,
              items: _employmentTypes
                  .map((t) =>
                      DropdownMenuItem(value: t, child: Text(t.replaceAll('_', ' '))))
                  .toList(),
              onChanged: (v) => setState(() {
                _typeFilter = v;
                _page = 1;
              }),
            ),
          ),
        ],
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
            itemBuilder: (context, i) =>
                _WorkerCard(worker: items[i]),
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

// ---------------------------------------------------------------------------
// Worker card
// ---------------------------------------------------------------------------

class _WorkerCard extends StatelessWidget {
  final Worker worker;

  const _WorkerCard({required this.worker});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/hr/workers/${worker.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: AppColors.cardShadow,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            _Avatar(name: worker.fullName),
            const SizedBox(width: 12),
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
            const SizedBox(width: 4),
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
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
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
      case 'CONTRACT':
        return AppColors.warning;
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
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Text(
        type.replaceAll('_', ' '),
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
