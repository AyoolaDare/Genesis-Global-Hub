import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/pagination_footer.dart';
import '../../core/widgets/search_bar.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/members_provider.dart';

class MembersListScreen extends ConsumerStatefulWidget {
  const MembersListScreen({super.key});

  @override
  ConsumerState<MembersListScreen> createState() =>
      _MembersListScreenState();
}

class _MembersListScreenState extends ConsumerState<MembersListScreen> {
  Timer? _debounce;
  String _searchQuery = '';
  String? _statusFilter;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String value) {
    setState(() {
      _searchQuery = value;
    });
    ref.read(membersProvider.notifier).refresh(
          page: 1,
          search: value.isEmpty ? null : value,
          status: _statusFilter,
        );
  }

  void _onFilterChange(String? status) {
    setState(() {
      _statusFilter = status;
    });
    ref.read(membersProvider.notifier).refresh(
          page: 1,
          search: _searchQuery.isEmpty ? null : _searchQuery,
          status: status,
        );
  }

  void _onPageChange(int page) {
    ref.read(membersProvider.notifier).refresh(
          page: page,
          search: _searchQuery.isEmpty ? null : _searchQuery,
          status: _statusFilter,
        );
  }

  @override
  Widget build(BuildContext context) {
    return ShellLayout(
      title: 'Members',
      actions: [
        ElevatedButton.icon(
          onPressed: () => context.push('/admin/members/create'),
          icon: const Icon(Icons.person_add_outlined, size: 18),
          label: const Text('Add Member'),
        ),
        const SizedBox(width: 16),
      ],
      child: Column(
        children: [
          _buildFilters(),
          Expanded(child: _buildList()),
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
            child: DebouncedSearchBar(
              hintText: 'Search members by name, phone, email...',
              onSearch: _onSearch,
            ),
          ),
          const SizedBox(width: 16),
          _StatusFilterChips(
            selected: _statusFilter,
            onChanged: _onFilterChange,
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final membersAsync = ref.watch(membersProvider);
    return membersAsync.when(
      loading: () => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 8,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: MemberCardSkeleton(),
        ),
      ),
      error: (error, _) => ErrorState(
        message: 'Failed to load members',
        details: error.toString(),
        onRetry: () => ref.read(membersProvider.notifier).refresh(),
      ),
      data: (membersList) {
        if (membersList.items.isEmpty) {
          return EmptyState(
            icon: Icons.people_outline,
            title: _searchQuery.isNotEmpty
                ? 'No members found for "$_searchQuery"'
                : 'No members yet',
            subtitle: _searchQuery.isEmpty
                ? 'Add a new member to get started'
                : null,
            actionLabel: _searchQuery.isEmpty ? 'Add Member' : null,
            onAction: _searchQuery.isEmpty
                ? () => context.push('/admin/members/create')
                : null,
          );
        }
        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: membersList.items.length,
                itemBuilder: (_, i) =>
                    _MemberCard(member: membersList.items[i]),
              ),
            ),
            PaginationFooter(
              currentPage: membersList.page,
              totalPages: membersList.totalPages,
              totalItems: membersList.total,
              pageSize: 20,
              onPageChanged: _onPageChange,
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Status filter chips
// ---------------------------------------------------------------------------

class _StatusFilterChips extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _StatusFilterChips({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FilterChip(
          label: 'All',
          isSelected: selected == null,
          onTap: () => onChanged(null),
        ),
        const SizedBox(width: 8),
        _FilterChip(
          label: 'Active',
          isSelected: selected == 'ACTIVE',
          color: AppColors.statusActive,
          onTap: () => onChanged(selected == 'ACTIVE' ? null : 'ACTIVE'),
        ),
        const SizedBox(width: 8),
        _FilterChip(
          label: 'Pending',
          isSelected: selected == 'PENDING',
          color: AppColors.statusPending,
          onTap: () =>
              onChanged(selected == 'PENDING' ? null : 'PENDING'),
        ),
        const SizedBox(width: 8),
        _FilterChip(
          label: 'Inactive',
          isSelected: selected == 'INACTIVE',
          color: AppColors.statusInactive,
          onTap: () =>
              onChanged(selected == 'INACTIVE' ? null : 'INACTIVE'),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : AppColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? AppColors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Member card
// ---------------------------------------------------------------------------

class _MemberCard extends StatelessWidget {
  final Member member;

  const _MemberCard({required this.member});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => context.push('/admin/members/${member.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _MemberAvatar(member: member),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            member.fullName,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        _StatusBadge(status: member.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (member.phone != null)
                      Row(
                        children: [
                          const Icon(Icons.phone_outlined,
                              size: 14,
                              color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            member.phone!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _RoleBadge(role: member.role),
                        if (member.isDuplicateFlagged) ...[
                          const SizedBox(width: 8),
                          _DuplicateBadge(),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  final Member member;

  const _MemberAvatar({required this.member});

  @override
  Widget build(BuildContext context) {
    if (member.photoUrl != null) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: member.photoUrl!,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          placeholder: (_, __) => _initials(context),
          errorWidget: (_, __, ___) => _initials(context),
        ),
      );
    }
    return _initials(context);
  }

  Widget _initials(BuildContext context) {
    final initials =
        '${member.firstName[0]}${member.lastName[0]}'.toUpperCase();
    return Container(
      width: 48,
      height: 48,
      decoration: const BoxDecoration(
        color: AppColors.primaryLight,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: AppColors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final MemberStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case MemberStatus.active:
        color = AppColors.statusActive;
        label = 'Active';
        break;
      case MemberStatus.pending:
        color = AppColors.statusPending;
        label = 'Pending';
        break;
      case MemberStatus.inactive:
        color = AppColors.statusInactive;
        label = 'Inactive';
        break;
      case MemberStatus.rejected:
        color = AppColors.statusRejected;
        label = 'Rejected';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;

  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        role.replaceAll('_', ' '),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _DuplicateBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 12, color: AppColors.error),
          SizedBox(width: 4),
          Text(
            'Duplicate',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}
