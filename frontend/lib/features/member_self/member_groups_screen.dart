import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';

// ---------------------------------------------------------------------------
// Model & provider
// ---------------------------------------------------------------------------

class MemberGroupMembership {
  final String id;
  final String name;
  final String type; // GROUP | TEAM | DEPARTMENT
  final String roleInGroup;
  final DateTime joinedAt;
  final String? description;
  final String? leaderName;

  const MemberGroupMembership({
    required this.id,
    required this.name,
    required this.type,
    required this.roleInGroup,
    required this.joinedAt,
    this.description,
    this.leaderName,
  });

  factory MemberGroupMembership.fromJson(Map<String, dynamic> json) {
    return MemberGroupMembership(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? 'GROUP',
      roleInGroup: json['role_in_group'] ?? json['role'] ?? 'MEMBER',
      joinedAt: DateTime.parse(
          json['joined_at'] ?? DateTime.now().toIso8601String()),
      description: json['description'],
      leaderName: json['leader_name'],
    );
  }
}

class MyGroupsList {
  final List<MemberGroupMembership> groups;
  final List<MemberGroupMembership> teams;
  final List<MemberGroupMembership> departments;

  const MyGroupsList({
    required this.groups,
    required this.teams,
    required this.departments,
  });

  bool get isEmpty =>
      groups.isEmpty && teams.isEmpty && departments.isEmpty;
}

final myGroupsProvider = FutureProvider<MyGroupsList>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.myGroups);
  final data = response.data['data'] as Map<String, dynamic>;

  List<MemberGroupMembership> parse(String key) {
    final list = data[key];
    if (list == null) return [];
    return (list as List)
        .map((e) => MemberGroupMembership.fromJson(e))
        .toList();
  }

  return MyGroupsList(
    groups: parse('groups'),
    teams: parse('teams'),
    departments: parse('departments'),
  );
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class MemberGroupsScreen extends ConsumerWidget {
  const MemberGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(myGroupsProvider);

    return ShellLayout(
      title: 'My Groups & Teams',
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(myGroupsProvider.future),
        child: groupsAsync.when(
          loading: () => Padding(
            padding: const EdgeInsets.all(24),
            child: ListSkeleton(
              count: 4,
              itemBuilder: () => const SkeletonBox(height: 80),
            ),
          ),
          error: (e, _) => ErrorState(
            message: e.toString().contains('403')
                ? 'Access Denied'
                : 'Failed to load groups',
            onRetry: () => ref.invalidate(myGroupsProvider),
          ),
          data: (data) => data.isEmpty
              ? const EmptyState(
                  icon: Icons.group_outlined,
                  title: 'No groups yet',
                  subtitle:
                      'You have not been added to any groups, teams or departments yet. Contact your group leader.',
                )
              : _buildContent(context, data),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, MyGroupsList data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.departments.isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.domain_outlined,
              title: 'Departments',
              count: data.departments.length,
              color: AppColors.primary,
            ),
            const SizedBox(height: 12),
            ...data.departments.map((m) => _MembershipCard(
                  membership: m,
                  accentColor: AppColors.primary,
                )),
            const SizedBox(height: 24),
          ],
          if (data.teams.isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.groups_outlined,
              title: 'Teams',
              count: data.teams.length,
              color: AppColors.info,
            ),
            const SizedBox(height: 12),
            ...data.teams.map((m) => _MembershipCard(
                  membership: m,
                  accentColor: AppColors.info,
                )),
            const SizedBox(height: 24),
          ],
          if (data.groups.isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.people_outline,
              title: 'Small Groups',
              count: data.groups.length,
              color: AppColors.secondary,
            ),
            const SizedBox(height: 12),
            ...data.groups.map((m) => _MembershipCard(
                  membership: m,
                  accentColor: AppColors.secondary,
                )),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
        ),
        const SizedBox(width: 8),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Membership card
// ---------------------------------------------------------------------------

class _MembershipCard extends StatelessWidget {
  final MemberGroupMembership membership;
  final Color accentColor;

  const _MembershipCard({
    required this.membership,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: accentColor, width: 3),
        ),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        membership.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    _RoleBadge(
                        role: membership.roleInGroup,
                        color: accentColor),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 13, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      'Joined ${membership.joinedAt.day}/${membership.joinedAt.month}/${membership.joinedAt.year}',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary),
                    ),
                    if (membership.leaderName != null) ...[
                      const SizedBox(width: 16),
                      const Icon(Icons.person_outline,
                          size: 13,
                          color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        'Leader: ${membership.leaderName}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
                if (membership.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    membership.description!,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  final Color color;

  const _RoleBadge({required this.role, required this.color});

  @override
  Widget build(BuildContext context) {
    final isLeader = role.toUpperCase().contains('LEADER') ||
        role.toUpperCase().contains('HEAD');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isLeader ? AppColors.secondary : color)
            .withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: (isLeader ? AppColors.secondary : color)
              .withOpacity(0.3),
        ),
      ),
      child: Text(
        role.replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color:
              isLeader ? AppColors.secondary : color,
        ),
      ),
    );
  }
}
