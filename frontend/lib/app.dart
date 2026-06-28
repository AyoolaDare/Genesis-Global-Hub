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
import 'features/admin/audit_logs_screen.dart';
import 'features/department_head/dept_dashboard.dart';
import 'features/department_head/dept_members_screen.dart';
import 'features/department_head/dept_kpi_screen.dart';
import 'features/team_leader/team_dashboard.dart';
import 'features/team_leader/team_members_screen.dart';
import 'features/team_leader/team_tasks_screen.dart';
import 'features/group_leader/group_dashboard.dart';
import 'features/group_leader/group_members_screen.dart';
import 'features/group_leader/attendance_screen.dart';
import 'features/follow_up/followup_dashboard.dart';
import 'features/follow_up/tasks_list_screen.dart';
import 'features/follow_up/task_detail_screen.dart';
import 'features/follow_up/new_convert_screen.dart';
import 'features/follow_up/member_search_screen.dart';
import 'features/medical/medical_dashboard.dart';
import 'features/medical/patients_list_screen.dart';
import 'features/medical/new_patient_screen.dart';
import 'features/medical/patient_detail_screen.dart';
import 'features/medical/visit_form_screen.dart';
import 'features/finance/finance_dashboard.dart';
import 'features/finance/sponsors_list_screen.dart';
import 'features/finance/sponsor_detail_screen.dart';
import 'features/finance/payments_screen.dart';
import 'features/hr/hr_dashboard.dart';
import 'features/hr/workers_list_screen.dart';
import 'features/hr/worker_detail_screen.dart';
import 'features/hr/performance_screen.dart';
import 'features/member_self/member_profile_screen.dart';
import 'features/member_self/member_groups_screen.dart';

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
      if (loc.startsWith('/medical') &&
          role != UserRole.superAdmin &&
          role != UserRole.medical) {
        return role.dashboardRoute;
      }
      if (loc.startsWith('/finance') &&
          role != UserRole.superAdmin &&
          role != UserRole.financeAdmin) {
        return role.dashboardRoute;
      }
      if (loc.startsWith('/hr') &&
          role != UserRole.superAdmin &&
          role != UserRole.hrAdmin) {
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
