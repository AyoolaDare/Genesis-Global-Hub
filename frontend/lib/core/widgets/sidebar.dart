import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../auth/user_model.dart';
import '../theme/app_colors.dart';

// ---------------------------------------------------------------------------
// Sidebar item model
// ---------------------------------------------------------------------------

class SidebarItem {
  final String label;
  final IconData icon;
  final String route;
  final List<SidebarItem> children;

  const SidebarItem({
    required this.label,
    required this.icon,
    required this.route,
    this.children = const [],
  });
}

// ---------------------------------------------------------------------------
// Role-based sidebar config
// ---------------------------------------------------------------------------

Map<UserRole, List<SidebarItem>> _sidebarConfig = {
  UserRole.superAdmin: [
    const SidebarItem(label: 'Dashboard', icon: Icons.dashboard_outlined, route: '/admin'),
    const SidebarItem(label: 'Members', icon: Icons.people_outline, route: '/admin/members'),
    const SidebarItem(label: 'Pending Approvals', icon: Icons.pending_actions_outlined, route: '/admin/pending'),
    const SidebarItem(label: 'Departments', icon: Icons.business_outlined, route: '/admin/departments'),
    const SidebarItem(label: 'KPI Config', icon: Icons.track_changes_outlined, route: '/admin/kpi'),
    const SidebarItem(label: 'Audit Logs', icon: Icons.history_outlined, route: '/admin/audit'),
    const SidebarItem(label: 'Sponsor', icon: Icons.volunteer_activism_outlined, route: '/finance'),
    const SidebarItem(label: 'HR', icon: Icons.badge_outlined, route: '/hr'),
    const SidebarItem(label: 'Medical', icon: Icons.local_hospital_outlined, route: '/medical'),
  ],
  UserRole.pastor: [
    const SidebarItem(label: 'Dashboard', icon: Icons.dashboard_outlined, route: '/admin'),
    const SidebarItem(label: 'Members', icon: Icons.people_outline, route: '/admin/members'),
    const SidebarItem(label: 'Departments', icon: Icons.business_outlined, route: '/admin/departments'),
    const SidebarItem(label: 'KPI Reports', icon: Icons.track_changes_outlined, route: '/admin/kpi'),
  ],
  UserRole.departmentHead: [
    const SidebarItem(label: 'Dashboard', icon: Icons.dashboard_outlined, route: '/dept'),
    const SidebarItem(label: 'My Members', icon: Icons.people_outline, route: '/dept/members'),
    const SidebarItem(label: 'KPIs', icon: Icons.track_changes_outlined, route: '/dept/kpi'),
  ],
  UserRole.teamLeader: [
    const SidebarItem(label: 'Dashboard', icon: Icons.dashboard_outlined, route: '/team'),
    const SidebarItem(label: 'My Members', icon: Icons.people_outline, route: '/team/members'),
    const SidebarItem(label: 'Tasks', icon: Icons.task_outlined, route: '/team/tasks'),
  ],
  UserRole.groupLeader: [
    const SidebarItem(label: 'Dashboard', icon: Icons.dashboard_outlined, route: '/group'),
    const SidebarItem(label: 'My Members', icon: Icons.people_outline, route: '/group/members'),
    const SidebarItem(label: 'Attendance', icon: Icons.how_to_reg_outlined, route: '/group/attendance'),
  ],
  UserRole.followUp: [
    const SidebarItem(label: 'Dashboard', icon: Icons.dashboard_outlined, route: '/follow-up'),
    const SidebarItem(label: 'My Tasks', icon: Icons.task_outlined, route: '/follow-up/tasks'),
    const SidebarItem(label: 'New Convert', icon: Icons.person_add_outlined, route: '/follow-up/new-convert'),
    const SidebarItem(label: 'Member Search', icon: Icons.search_outlined, route: '/follow-up/search'),
  ],
  UserRole.medical: [
    const SidebarItem(label: 'Dashboard', icon: Icons.dashboard_outlined, route: '/medical'),
    const SidebarItem(label: 'My Patients', icon: Icons.sick_outlined, route: '/medical/patients'),
    const SidebarItem(label: 'New Patient', icon: Icons.person_add_outlined, route: '/medical/patients/new'),
  ],
  UserRole.financeAdmin: [
    const SidebarItem(label: 'Dashboard', icon: Icons.dashboard_outlined, route: '/finance'),
    const SidebarItem(label: 'Sponsors', icon: Icons.volunteer_activism_outlined, route: '/finance/sponsors'),
    const SidebarItem(label: 'Payments', icon: Icons.payment_outlined, route: '/finance/payments'),
  ],
  UserRole.hrAdmin: [
    const SidebarItem(label: 'Dashboard', icon: Icons.dashboard_outlined, route: '/hr'),
    const SidebarItem(label: 'Workers', icon: Icons.badge_outlined, route: '/hr/workers'),
    const SidebarItem(label: 'Performance', icon: Icons.analytics_outlined, route: '/hr/performance'),
  ],
  UserRole.member: [
    const SidebarItem(label: 'My Profile', icon: Icons.person_outline, route: '/profile'),
    const SidebarItem(label: 'My Groups', icon: Icons.group_outlined, route: '/my-groups'),
  ],
};

// ---------------------------------------------------------------------------
// Sidebar widget
// ---------------------------------------------------------------------------

class AppSidebar extends ConsumerStatefulWidget {
  final bool isCollapsed;
  final VoidCallback? onToggle;

  const AppSidebar({
    super.key,
    this.isCollapsed = false,
    this.onToggle,
  });

  @override
  ConsumerState<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends ConsumerState<AppSidebar> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final role = authState.role;
    final user = authState.user;
    final items = _sidebarConfig[role] ?? [];
    final currentLocation = GoRouterState.of(context).matchedLocation;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: widget.isCollapsed ? 72 : 260,
      decoration: const BoxDecoration(
        color: AppColors.sidebarBg,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 8,
            offset: Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          _SidebarHeader(
            user: user,
            role: role,
            isCollapsed: widget.isCollapsed,
            onToggle: widget.onToggle,
          ),
          const Divider(color: AppColors.primaryLight, height: 1),
          // Nav items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: items
                  .map((item) => _SidebarNavItem(
                        item: item,
                        isCollapsed: widget.isCollapsed,
                        isActive: _isActive(currentLocation, item.route),
                      ))
                  .toList(),
            ),
          ),
          const Divider(color: AppColors.primaryLight, height: 1),
          // Logout
          _LogoutButton(isCollapsed: widget.isCollapsed),
        ],
      ),
    );
  }

  bool _isActive(String currentLocation, String route) {
    if (route == '/admin' || route == '/dept' || route == '/team' ||
        route == '/group' || route == '/follow-up' || route == '/medical' ||
        route == '/finance' || route == '/hr') {
      return currentLocation == route;
    }
    return currentLocation.startsWith(route);
  }
}

// ---------------------------------------------------------------------------
// Sidebar header
// ---------------------------------------------------------------------------

class _SidebarHeader extends StatelessWidget {
  final dynamic user;
  final UserRole role;
  final bool isCollapsed;
  final VoidCallback? onToggle;

  const _SidebarHeader({
    required this.user,
    required this.role,
    required this.isCollapsed,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCollapsed ? 12 : 16,
        vertical: 16,
      ),
      child: Row(
        children: [
          if (!isCollapsed) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  'GG',
                  style: TextStyle(
                    color: AppColors.textOnSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Genesis Global',
                    style: TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    role.displayName,
                    style: const TextStyle(
                      color: AppColors.sidebarAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  'GG',
                  style: TextStyle(
                    color: AppColors.textOnSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
          IconButton(
            icon: Icon(
              isCollapsed ? Icons.chevron_right : Icons.chevron_left,
              color: AppColors.sidebarText,
              size: 20,
            ),
            onPressed: onToggle,
            splashRadius: 20,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Nav item
// ---------------------------------------------------------------------------

class _SidebarNavItem extends StatelessWidget {
  final SidebarItem item;
  final bool isCollapsed;
  final bool isActive;

  const _SidebarNavItem({
    required this.item,
    required this.isCollapsed,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isCollapsed ? item.label : '',
      child: InkWell(
        onTap: () => context.go(item.route),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: EdgeInsets.symmetric(
            horizontal: isCollapsed ? 8 : 8,
            vertical: 2,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: isCollapsed ? 0 : 12,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: isActive ? AppColors.sidebarActive : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isActive
                ? const Border(
                    left: BorderSide(color: AppColors.secondary, width: 3),
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: isCollapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(
                item.icon,
                size: 22,
                color: isActive
                    ? AppColors.sidebarActiveText
                    : AppColors.sidebarText,
              ),
              if (!isCollapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: isActive
                          ? AppColors.sidebarActiveText
                          : AppColors.sidebarText,
                      fontSize: 14,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Logout button
// ---------------------------------------------------------------------------

class _LogoutButton extends ConsumerWidget {
  final bool isCollapsed;

  const _LogoutButton({required this.isCollapsed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      message: isCollapsed ? 'Logout' : '',
      child: InkWell(
        onTap: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Logout'),
              content: const Text('Are you sure you want to logout?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Logout'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await ref.read(authProvider.notifier).logout();
          }
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCollapsed ? 0 : 20,
            vertical: 16,
          ),
          child: Row(
            mainAxisAlignment: isCollapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              const Icon(
                Icons.logout_outlined,
                size: 22,
                color: AppColors.sidebarText,
              ),
              if (!isCollapsed) ...[
                const SizedBox(width: 12),
                const Text(
                  'Logout',
                  style: TextStyle(
                    color: AppColors.sidebarText,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shell layout (sidebar + content)
// ---------------------------------------------------------------------------

class ShellLayout extends ConsumerStatefulWidget {
  final Widget child;
  final String title;
  final List<Widget>? actions;

  const ShellLayout({
    super.key,
    required this.child,
    required this.title,
    this.actions,
  });

  @override
  ConsumerState<ShellLayout> createState() => _ShellLayoutState();
}

class _ShellLayoutState extends ConsumerState<ShellLayout> {
  bool _sidebarCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;
    final isTablet = screenWidth >= 768 && screenWidth < 1024;

    if (isMobile) {
      return _MobileLayout(
        title: widget.title,
        actions: widget.actions,
        child: widget.child,
      );
    }

    return Scaffold(
      body: Row(
        children: [
          AppSidebar(
            isCollapsed: isTablet || _sidebarCollapsed,
            onToggle: () {
              setState(() => _sidebarCollapsed = !_sidebarCollapsed);
            },
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  title: widget.title,
                  actions: widget.actions,
                ),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final List<Widget>? actions;

  const _TopBar({required this.title, this.actions});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Spacer(),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}

class _MobileLayout extends ConsumerWidget {
  final String title;
  final List<Widget>? actions;
  final Widget child;

  const _MobileLayout({
    required this.title,
    this.actions,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: actions,
      ),
      drawer: Drawer(
        child: AppSidebar(
          isCollapsed: false,
          onToggle: () => Navigator.of(context).pop(),
        ),
      ),
      body: child,
    );
  }
}
