import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/auth/auth_provider.dart';
import 'core/auth/user_model.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/forgot_password_screen.dart';
import 'features/admin/admin_dashboard.dart';
import 'features/admin/members_list_screen.dart';
import 'features/admin/member_detail_screen.dart';
import 'features/admin/member_create_screen.dart';
import 'features/admin/pending_approvals_screen.dart';
import 'features/admin/departments_screen.dart';
import 'features/admin/kpi_config_screen.dart';

// ---------------------------------------------------------------------------
// Router provider
// ---------------------------------------------------------------------------

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: _AuthStateNotifier(ref),
    redirect: (context, state) {
      final authState = ref.read(authProvider);

      final isLoading = authState.isLoading;
      if (isLoading) return null;

      final isAuthenticated = authState.isAuthenticated;
      final isLoginRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/forgot-password';

      if (!isAuthenticated && !isLoginRoute) {
        return '/login';
      }

      if (isAuthenticated && isLoginRoute) {
        return authState.role.dashboardRoute;
      }

      // Role-based access control
      final loc = state.matchedLocation;
      final role = authState.role;

      if (loc.startsWith('/admin') &&
          role != UserRole.superAdmin &&
          role != UserRole.pastor) {
        return role.dashboardRoute;
      }
      if (loc.startsWith('/dept') && role != UserRole.departmentHead) {
        return role.dashboardRoute;
      }
      if (loc.startsWith('/team') && role != UserRole.teamLeader) {
        return role.dashboardRoute;
      }
      if (loc.startsWith('/group') && role != UserRole.groupLeader) {
        return role.dashboardRoute;
      }
      if (loc.startsWith('/follow-up') && role != UserRole.followUp) {
        return role.dashboardRoute;
      }
      if (loc.startsWith('/medical') && role != UserRole.medical) {
        return role.dashboardRoute;
      }
      if (loc.startsWith('/finance') && role != UserRole.financeAdmin) {
        return role.dashboardRoute;
      }
      if (loc.startsWith('/hr') && role != UserRole.hrAdmin) {
        return role.dashboardRoute;
      }

      return null;
    },
    routes: [
      // Auth
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),

      // Admin / Pastor
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminDashboard(),
        routes: [
          GoRoute(
            path: 'members',
            builder: (context, state) => const MembersListScreen(),
            routes: [
              GoRoute(
                path: 'create',
                builder: (context, state) => const MemberCreateScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    MemberDetailScreen(memberId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: 'pending',
            builder: (context, state) => const PendingApprovalsScreen(),
          ),
          GoRoute(
            path: 'departments',
            builder: (context, state) => const DepartmentsScreen(),
          ),
          GoRoute(
            path: 'kpi',
            builder: (context, state) => const KpiConfigScreen(),
          ),
          GoRoute(
            path: 'audit',
            builder: (context, state) => const AuditLogsScreen(),
          ),
        ],
      ),

      // Department Head
      GoRoute(
        path: '/dept',
        builder: (context, state) => const DeptDashboard(),
        routes: [
          GoRoute(
            path: 'members',
            builder: (context, state) => const DeptMembersScreen(),
          ),
          GoRoute(
            path: 'kpi',
            builder: (context, state) => const DeptKpiScreen(),
          ),
        ],
      ),

      // Team Leader
      GoRoute(
        path: '/team',
        builder: (context, state) => const TeamDashboard(),
        routes: [
          GoRoute(
            path: 'members',
            builder: (context, state) => const TeamMembersScreen(),
          ),
          GoRoute(
            path: 'tasks',
            builder: (context, state) => const TeamTasksScreen(),
          ),
        ],
      ),

      // Group Leader
      GoRoute(
        path: '/group',
        builder: (context, state) => const GroupDashboard(),
        routes: [
          GoRoute(
            path: 'members',
            builder: (context, state) => const GroupMembersScreen(),
          ),
          GoRoute(
            path: 'attendance',
            builder: (context, state) => const AttendanceScreen(),
          ),
        ],
      ),

      // Follow-up
      GoRoute(
        path: '/follow-up',
        builder: (context, state) => const FollowupDashboard(),
        routes: [
          GoRoute(
            path: 'tasks',
            builder: (context, state) => const TasksListScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    TaskDetailScreen(taskId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: 'new-convert',
            builder: (context, state) => const NewConvertScreen(),
          ),
          GoRoute(
            path: 'search',
            builder: (context, state) => const MemberSearchScreen(),
          ),
        ],
      ),

      // Medical
      GoRoute(
        path: '/medical',
        builder: (context, state) => const MedicalDashboard(),
        routes: [
          GoRoute(
            path: 'patients',
            builder: (context, state) => const PatientsListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const NewPatientScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    PatientDetailScreen(patientId: state.pathParameters['id']!),
                routes: [
                  GoRoute(
                    path: 'visit',
                    builder: (context, state) => VisitFormScreen(
                      patientId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // Finance
      GoRoute(
        path: '/finance',
        builder: (context, state) => const FinanceDashboard(),
        routes: [
          GoRoute(
            path: 'sponsors',
            builder: (context, state) => const SponsorsListScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) => SponsorDetailScreen(
                    sponsorId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: 'payments',
            builder: (context, state) => const PaymentsScreen(),
          ),
        ],
      ),

      // HR
      GoRoute(
        path: '/hr',
        builder: (context, state) => const HrDashboard(),
        routes: [
          GoRoute(
            path: 'workers',
            builder: (context, state) => const WorkersListScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    WorkerDetailScreen(workerId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: 'performance',
            builder: (context, state) => const PerformanceScreen(),
          ),
        ],
      ),

      // Member self-service
      GoRoute(
        path: '/profile',
        builder: (context, state) => const MemberProfileScreen(),
      ),
      GoRoute(
        path: '/my-groups',
        builder: (context, state) => const MemberGroupsScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Page not found',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(state.error?.message ?? 'The requested page does not exist'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/login'),
              child: const Text('Go to Login'),
            ),
          ],
        ),
      ),
    ),
  );
});

// ---------------------------------------------------------------------------
// Listenable wrapper for GoRouter refresh
// ---------------------------------------------------------------------------

class _AuthStateNotifier extends ChangeNotifier {
  _AuthStateNotifier(Ref ref) {
    ref.listen(authProvider, (_, __) {
      notifyListeners();
    });
  }
}

// ---------------------------------------------------------------------------
// Root app widget
// ---------------------------------------------------------------------------

class GenesisGlobalApp extends ConsumerWidget {
  const GenesisGlobalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Genesis Global CMS',
      theme: AppTheme.lightTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              MediaQuery.of(context).textScaler.scale(1.0).clamp(0.8, 1.2),
            ),
          ),
          child: child!,
        );
      },
    );
  }
}

class _ModulePlaceholderScreen extends StatelessWidget {
  final String title;

  const _ModulePlaceholderScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.construction_outlined, size: 48),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'This module route is wired and ready for implementation.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AuditLogsScreen extends _ModulePlaceholderScreen {
  const AuditLogsScreen({super.key}) : super(title: 'Audit Logs');
}

class DeptDashboard extends _ModulePlaceholderScreen {
  const DeptDashboard({super.key}) : super(title: 'Department Dashboard');
}

class DeptMembersScreen extends _ModulePlaceholderScreen {
  const DeptMembersScreen({super.key}) : super(title: 'Department Members');
}

class DeptKpiScreen extends _ModulePlaceholderScreen {
  const DeptKpiScreen({super.key}) : super(title: 'Department KPIs');
}

class TeamDashboard extends _ModulePlaceholderScreen {
  const TeamDashboard({super.key}) : super(title: 'Team Dashboard');
}

class TeamMembersScreen extends _ModulePlaceholderScreen {
  const TeamMembersScreen({super.key}) : super(title: 'Team Members');
}

class TeamTasksScreen extends _ModulePlaceholderScreen {
  const TeamTasksScreen({super.key}) : super(title: 'Team Tasks');
}

class GroupDashboard extends _ModulePlaceholderScreen {
  const GroupDashboard({super.key}) : super(title: 'Group Dashboard');
}

class GroupMembersScreen extends _ModulePlaceholderScreen {
  const GroupMembersScreen({super.key}) : super(title: 'Group Members');
}

class AttendanceScreen extends _ModulePlaceholderScreen {
  const AttendanceScreen({super.key}) : super(title: 'Attendance');
}

class FollowupDashboard extends _ModulePlaceholderScreen {
  const FollowupDashboard({super.key}) : super(title: 'Follow-up Dashboard');
}

class TasksListScreen extends _ModulePlaceholderScreen {
  const TasksListScreen({super.key}) : super(title: 'Follow-up Tasks');
}

class TaskDetailScreen extends _ModulePlaceholderScreen {
  TaskDetailScreen({super.key, required String taskId})
      : super(title: 'Follow-up Task');
}

class NewConvertScreen extends _ModulePlaceholderScreen {
  const NewConvertScreen({super.key}) : super(title: 'New Convert');
}

class MemberSearchScreen extends _ModulePlaceholderScreen {
  const MemberSearchScreen({super.key}) : super(title: 'Member Search');
}

class MedicalDashboard extends _ModulePlaceholderScreen {
  const MedicalDashboard({super.key}) : super(title: 'Medical Dashboard');
}

class PatientsListScreen extends _ModulePlaceholderScreen {
  const PatientsListScreen({super.key}) : super(title: 'Patients');
}

class NewPatientScreen extends _ModulePlaceholderScreen {
  const NewPatientScreen({super.key}) : super(title: 'New Patient');
}

class PatientDetailScreen extends _ModulePlaceholderScreen {
  PatientDetailScreen({super.key, required String patientId})
      : super(title: 'Patient Detail');
}

class VisitFormScreen extends _ModulePlaceholderScreen {
  VisitFormScreen({super.key, required String patientId})
      : super(title: 'Medical Visit');
}

class FinanceDashboard extends _ModulePlaceholderScreen {
  const FinanceDashboard({super.key}) : super(title: 'Finance Dashboard');
}

class SponsorsListScreen extends _ModulePlaceholderScreen {
  const SponsorsListScreen({super.key}) : super(title: 'Sponsors');
}

class SponsorDetailScreen extends _ModulePlaceholderScreen {
  SponsorDetailScreen({super.key, required String sponsorId})
      : super(title: 'Sponsor Detail');
}

class PaymentsScreen extends _ModulePlaceholderScreen {
  const PaymentsScreen({super.key}) : super(title: 'Payments');
}

class HrDashboard extends _ModulePlaceholderScreen {
  const HrDashboard({super.key}) : super(title: 'HR Dashboard');
}

class WorkersListScreen extends _ModulePlaceholderScreen {
  const WorkersListScreen({super.key}) : super(title: 'Workers');
}

class WorkerDetailScreen extends _ModulePlaceholderScreen {
  WorkerDetailScreen({super.key, required String workerId})
      : super(title: 'Worker Detail');
}

class PerformanceScreen extends _ModulePlaceholderScreen {
  const PerformanceScreen({super.key}) : super(title: 'Performance');
}

class MemberProfileScreen extends _ModulePlaceholderScreen {
  const MemberProfileScreen({super.key}) : super(title: 'My Profile');
}

class MemberGroupsScreen extends _ModulePlaceholderScreen {
  const MemberGroupsScreen({super.key}) : super(title: 'My Groups');
}
