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
import '../../providers/members_provider.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final groupMembersProvider =
    FutureProvider.family<MembersList, Map<String, dynamic>>(
  (ref, params) async {
    final dio = ref.read(dioProvider);
    final response = await dio.get(
      ApiEndpoints.members,
      queryParameters: {
        'page': params['page'] ?? 1,
        'page_size': 20,
        if (params['search'] != null &&
            (params['search'] as String).isNotEmpty)
          'search': params['search'],
      },
    );
    final data = response.data['data'] as List;
    final meta = response.data['meta'];
    return MembersList(
      items: data.map((e) => Member.fromJson(e)).toList(),
      total: meta['total'] ?? 0,
      page: meta['page'] ?? 1,
      pageSize: meta['page_size'] ?? 20,
      totalPages: meta['total_pages'] ?? 1,
    );
  },
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class GroupMembersScreen extends ConsumerStatefulWidget {
  const GroupMembersScreen({super.key});

  @override
  ConsumerState<GroupMembersScreen> createState() =>
      _GroupMembersScreenState();
}

class _GroupMembersScreenState
    extends ConsumerState<GroupMembersScreen> {
  int _page = 1;
  String _search = '';
  final _searchController = TextEditingController();

  Map<String, dynamic> get _params => {
        'page': _page,
        if (_search.isNotEmpty) 'search': _search,
      };

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
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(groupMembersProvider(_params));

    return ShellLayout(
      title: 'Group Members',
      child: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: membersAsync.when(
              loading: () => Padding(
                padding: const EdgeInsets.all(24),
                child: ListSkeleton(
                  count: 6,
                  itemBuilder: () => const MemberCardSkeleton(),
                ),
              ),
              error: (e, _) => ErrorState(
                message: e.toString().contains('403')
                    ? 'Access Denied'
                    : 'Failed to load members',
                onRetry: () =>
                    ref.invalidate(groupMembersProvider(_params)),
              ),
              data: (members) => members.items.isEmpty
                  ? EmptyState(
                      icon: Icons.people_outline,
                      title: 'No members found',
                      subtitle: _search.isNotEmpty
                          ? 'No members match "$_search"'
                          : 'Your group has no members yet.',
                    )
                  : _buildList(members),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search members...',
          prefixIcon:
              const Icon(Icons.search, color: AppColors.textSecondary),
          suffixIcon: _search.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _search = '';
                      _page = 1;
                    });
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
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildList(MembersList members) {
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: members.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) =>
                _MemberTile(member: members.items[i]),
          ),
        ),
        PaginationFooter(
          currentPage: _page,
          totalPages: members.totalPages,
          totalItems: members.total,
          pageSize: 20,
          onPageChanged: (p) => setState(() => _page = p),
        ),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  final Member member;

  const _MemberTile({required this.member});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/admin/members/${member.id}'),
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
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              backgroundImage: member.photoUrl != null
                  ? NetworkImage(member.photoUrl!)
                  : null,
              child: member.photoUrl == null
                  ? Text(
                      member.fullName.isNotEmpty
                          ? member.fullName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.fullName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (member.phone != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      member.phone!,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _StatusBadge(status: member.status),
                      if (member.joinedAt != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          'Joined ${_fmt(member.joinedAt!)}',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 20, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _StatusBadge extends StatelessWidget {
  final MemberStatus status;

  const _StatusBadge({required this.status});

  Color get _color {
    switch (status) {
      case MemberStatus.active:
        return AppColors.statusActive;
      case MemberStatus.pending:
        return AppColors.statusPending;
      case MemberStatus.inactive:
        return AppColors.statusInactive;
      case MemberStatus.rejected:
        return AppColors.statusRejected;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.value,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _color,
        ),
      ),
    );
  }
}
