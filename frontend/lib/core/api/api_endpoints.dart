class ApiEndpoints {
  ApiEndpoints._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api/v1',
  );

  // Auth
  static const String login = '/auth/login';
  static const String logout = '/auth/logout';
  static const String refreshToken = '/auth/refresh';
  static const String forgotPassword = '/auth/forgot-password';
  static const String resetPassword = '/auth/reset-password';
  static const String changePassword = '/auth/change-password';

  // Members
  static const String members = '/members';
  static String memberById(String id) => '/members/$id';
  static String memberApprove(String id) => '/members/$id/approve';
  static String memberReject(String id) => '/members/$id/reject';
  static String memberMerge(String id) => '/members/$id/merge';
  static const String pendingMembers = '/members/pending';
  static String memberPhoto(String id) => '/members/$id/photo';
  static String memberAssign(String id) => '/members/$id/assign';

  // Departments
  static const String departments = '/departments';
  static String departmentById(String id) => '/departments/$id';
  static String departmentMembers(String id) => '/departments/$id/members';
  static String departmentKpis(String id) => '/departments/$id/kpis';

  // Teams
  static const String teams = '/teams';
  static String teamById(String id) => '/teams/$id';
  static String teamMembers(String id) => '/teams/$id/members';
  static String teamTasks(String id) => '/teams/$id/tasks';

  // Groups
  static const String groups = '/groups';
  static String groupById(String id) => '/groups/$id';
  static String groupMembers(String id) => '/groups/$id/members';

  // Attendance
  static const String meetings = '/meetings';
  static String meetingById(String id) => '/meetings/$id';
  static String meetingAttendance(String id) => '/meetings/$id/attendance';
  static const String attendance = '/attendance';
  static String attendanceByMeeting(String meetingId) => '/attendance/meeting/$meetingId';

  // Follow-up
  static const String followUpTasks = '/follow-up/tasks';
  static String followUpTaskById(String id) => '/follow-up/tasks/$id';
  static String followUpTaskComplete(String id) => '/follow-up/tasks/$id/complete';
  static const String newConverts = '/follow-up/new-converts';
  static String newConvertById(String id) => '/follow-up/new-converts/$id';
  static String memberSearch = '/members/search';

  // Medical
  static const String patients = '/medical/patients';
  static String patientById(String id) => '/medical/patients/$id';
  static String patientVisits(String id) => '/medical/patients/$id/visits';
  static String visitById(String patientId, String visitId) =>
      '/medical/patients/$patientId/visits/$visitId';

  // Sponsors / Finance
  static const String sponsors = '/sponsors';
  static String sponsorById(String id) => '/sponsors/$id';
  static const String payments = '/payments';
  static String paymentById(String id) => '/payments/$id';
  static const String financeReports = '/finance/reports';

  // HR
  static const String workers = '/hr/workers';
  static String workerById(String id) => '/hr/workers/$id';
  static const String performance = '/hr/performance';
  static String performanceByWorker(String id) => '/hr/performance/worker/$id';
  static const String leaveRequests = '/hr/leave-requests';

  // KPI
  static const String kpiConfigs = '/kpi/configs';
  static String kpiConfigById(String id) => '/kpi/configs/$id';
  static const String kpiReports = '/kpi/reports';

  // Audit
  static const String auditLogs = '/audit/logs';

  // Dashboard
  static const String adminDashboard = '/dashboard/admin';
  static const String deptDashboard = '/dashboard/department';
  static const String teamDashboard = '/dashboard/team';
  static const String groupDashboard = '/dashboard/group';
  static const String followUpDashboard = '/dashboard/follow-up';
  static const String medicalDashboard = '/medical/dashboard';
  static const String financeDashboard = '/finance/dashboard';
  static const String hrDashboard = '/hr/dashboard';

  // Profile
  static const String myProfile = '/profile/me';
  static const String myGroups = '/profile/my-groups';
}
