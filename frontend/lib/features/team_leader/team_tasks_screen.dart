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
// Model
// ---------------------------------------------------------------------------

class TeamTask {
  final String id;
  final String title;
  final String? description;
  final String assignedToName;
  final String status;
  final DateTime dueDate;

  const TeamTask({
    required this.id,
    required this.title,
    this.description,
    required this.assignedToName,
    required this.status,
    required this.dueDate,
  });

  bool get isOverdue =>
      status != 'DONE' && dueDate.isBefore(DateTime.now());

  factory TeamTask.fromJson(Map<String, dynamic> json) {
    return TeamTask(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'],
      assignedToName: json['assigned_to_name'] ?? '',
      status: json['status'] ?? 'PENDING',
      dueDate: DateTime.parse(
          json['due_date'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class TeamTasksList {
  final List<TeamTask> items;
  final int total;
  final int page;
  final int totalPages;

  const TeamTasksList({
    required this.items,
    required this.total,
    required this.page,
    required this.totalPages,
  });
}

final teamTasksProvider =
    FutureProvider.family<TeamTasksList, Map<String, dynamic>>(
  (ref, params) async {
    final dio = ref.read(dioProvider);
    final teamId = params['team_id'] as String?;
    final endpoint =
        teamId != null ? ApiEndpoints.teamTasks(teamId) : ApiEndpoints.teams;
    final response = await dio.get(
      endpoint,
      queryParameters: {
        'page': params['page'] ?? 1,
        'page_size': 20,
        if (params['status'] != null) 'status': params['status'],
      },
    );
    final data = response.data['data'] as List;
    final meta = response.data['meta'] ?? {};
    return TeamTasksList(
      items: data.map((e) => TeamTask.fromJson(e)).toList(),
      total: meta['total'] ?? data.length,
      page: meta['page'] ?? 1,
      totalPages: meta['total_pages'] ?? 1,
    );
  },
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class TeamTasksScreen extends ConsumerStatefulWidget {
  const TeamTasksScreen({super.key});

  @override
  ConsumerState<TeamTasksScreen> createState() => _TeamTasksScreenState();
}

class _TeamTasksScreenState extends ConsumerState<TeamTasksScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _page = 1);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String? get _statusFilter {
    switch (_tabController.index) {
      case 1:
        return 'IN_PROGRESS';
      case 2:
        return 'DONE';
      default:
        return null;
    }
  }

  Map<String, dynamic> get _params => {
        'page': _page,
        if (_statusFilter != null) 'status': _statusFilter,
      };

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(teamTasksProvider(_params));

    return ShellLayout(
      title: 'Team Tasks',
      child: Column(
        children: [
          Container(
            color: AppColors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: 'All Tasks'),
                Tab(text: 'In Progress'),
                Tab(text: 'Completed'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: List.generate(
                3,
                (_) => tasksAsync.when(
                  loading: () => Padding(
                    padding: const EdgeInsets.all(24),
                    child: ListSkeleton(
                      count: 5,
                      itemBuilder: () => const SkeletonBox(height: 80),
                    ),
                  ),
                  error: (e, _) => ErrorState(
                    message: e.toString().contains('403')
                        ? 'Access Denied'
                        : 'Failed to load tasks',
                    onRetry: () =>
                        ref.invalidate(teamTasksProvider(_params)),
                  ),
                  data: (tasks) => tasks.items.isEmpty
                      ? const EmptyState(
                          icon: Icons.task_outlined,
                          title: 'No tasks found',
                          subtitle: 'No tasks match the current filter.',
                        )
                      : _buildTaskList(tasks.items),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(List<TeamTask> tasks) {
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _TaskCard(task: tasks[i]),
    );
  }
}

// ---------------------------------------------------------------------------
// Task Card
// ---------------------------------------------------------------------------

class _TaskCard extends StatelessWidget {
  final TeamTask task;

  const _TaskCard({required this.task});

  Color get _statusColor {
    switch (task.status) {
      case 'DONE':
        return AppColors.success;
      case 'IN_PROGRESS':
        return AppColors.info;
      case 'PENDING':
        return task.isOverdue ? AppColors.error : AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: task.isOverdue
            ? AppColors.error.withValues(alpha: 0.04)
            : AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: task.isOverdue
            ? Border.all(color: AppColors.error.withValues(alpha: 0.3))
            : null,
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
          Container(
            width: 4,
            height: 60,
            decoration: BoxDecoration(
              color: _statusColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    _StatusChip(
                        status: task.status, color: _statusColor),
                  ],
                ),
                if (task.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    task.description!,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.person_outline,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      task.assignedToName,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.calendar_today_outlined,
                        size: 14,
                        color: task.isOverdue
                            ? AppColors.error
                            : AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(task.dueDate),
                      style: TextStyle(
                        fontSize: 12,
                        color: task.isOverdue
                            ? AppColors.error
                            : AppColors.textSecondary,
                        fontWeight: task.isOverdue
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    if (task.isOverdue) ...[
                      const SizedBox(width: 6),
                      const Text(
                        'OVERDUE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.error,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _StatusChip extends StatelessWidget {
  final String status;
  final Color color;

  const _StatusChip({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
