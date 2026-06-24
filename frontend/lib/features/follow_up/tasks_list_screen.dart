import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../providers/follow_up_provider.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class TasksListScreen extends ConsumerStatefulWidget {
  const TasksListScreen({super.key});

  @override
  ConsumerState<TasksListScreen> createState() => _TasksListScreenState();
}

class _TasksListScreenState extends ConsumerState<TasksListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(followUpProvider);

    return ShellLayout(
      title: 'Follow-up Tasks',
      actions: [
        ElevatedButton.icon(
          icon: const Icon(Icons.person_add_outlined, size: 18),
          label: const Text('New Convert'),
          onPressed: () => context.go('/follow-up/new-convert'),
        ),
        const SizedBox(width: 8),
      ],
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
                Tab(text: 'Today'),
                Tab(text: 'Overdue'),
                Tab(text: 'All Tasks'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _TasksTab(
                  tasksAsync: tasksAsync,
                  filter: 'today',
                  ref: ref,
                ),
                _TasksTab(
                  tasksAsync: tasksAsync,
                  filter: 'overdue',
                  ref: ref,
                ),
                _TasksTab(
                  tasksAsync: tasksAsync,
                  filter: 'all',
                  ref: ref,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tasks tab
// ---------------------------------------------------------------------------

class _TasksTab extends StatelessWidget {
  final AsyncValue<FollowUpTasksList> tasksAsync;
  final String filter;
  final WidgetRef ref;

  const _TasksTab({
    required this.tasksAsync,
    required this.filter,
    required this.ref,
  });

  List<FollowUpTask> _filterTasks(List<FollowUpTask> tasks) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (filter) {
      case 'today':
        return tasks.where((t) {
          final due = DateTime(
              t.dueDate.year, t.dueDate.month, t.dueDate.day);
          return due == today && !t.isCompleted;
        }).toList();
      case 'overdue':
        return tasks.where((t) => t.isOverdue && !t.isCompleted).toList();
      default:
        return tasks;
    }
  }

  @override
  Widget build(BuildContext context) {
    return tasksAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(24),
        child: ListSkeleton(
          count: 5,
          itemBuilder: () => const TaskCardSkeleton(),
        ),
      ),
      error: (e, _) => ErrorState(
        message: e.toString().contains('403')
            ? 'Access Denied'
            : 'Failed to load tasks',
        onRetry: () => ref.invalidate(followUpProvider),
      ),
      data: (tasksList) {
        final filtered = _filterTasks(tasksList.items);
        if (filtered.isEmpty) {
          return EmptyState(
            icon: Icons.task_outlined,
            title: filter == 'today'
                ? 'No tasks due today'
                : filter == 'overdue'
                    ? 'No overdue tasks'
                    : 'No tasks yet',
            subtitle: filter == 'today'
                ? 'You\'re all caught up for today!'
                : filter == 'overdue'
                    ? 'Great job staying on top of your tasks!'
                    : 'Create a new convert to start follow-up.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _TaskCard(task: filtered[i]),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Task card
// ---------------------------------------------------------------------------

class _TaskCard extends StatelessWidget {
  final FollowUpTask task;

  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/follow-up/tasks/${task.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: task.isOverdue
              ? AppColors.error.withValues(alpha: 0.04)
              : AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: task.isOverdue
              ? Border.all(color: AppColors.error.withValues(alpha: 0.25))
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
              height: 64,
              decoration: BoxDecoration(
                color: _stageColor(task.stage),
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
                          task.convertName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      _StageChip(stage: task.stage),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (task.convertPhone != null)
                    Text(
                      task.convertPhone!,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 14,
                          color: task.isOverdue
                              ? AppColors.error
                              : AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        'Due: ${_formatDate(task.dueDate)}',
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
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'OVERDUE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.error,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (task.assignedToName != null)
                        Text(
                          task.assignedToName!,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right,
                size: 20, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Color _stageColor(FollowUpStage stage) {
    switch (stage) {
      case FollowUpStage.initial:
        return AppColors.textSecondary;
      case FollowUpStage.firstContact:
        return AppColors.info;
      case FollowUpStage.secondContact:
        return AppColors.warning;
      case FollowUpStage.thirdContact:
        return AppColors.secondary;
      case FollowUpStage.integrated:
        return AppColors.success;
      case FollowUpStage.lost:
        return AppColors.error;
    }
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ---------------------------------------------------------------------------
// Stage chip
// ---------------------------------------------------------------------------

class _StageChip extends StatelessWidget {
  final FollowUpStage stage;

  const _StageChip({required this.stage});

  Color get _color {
    switch (stage) {
      case FollowUpStage.initial:
        return AppColors.textSecondary;
      case FollowUpStage.firstContact:
        return AppColors.info;
      case FollowUpStage.secondContact:
        return AppColors.warning;
      case FollowUpStage.thirdContact:
        return AppColors.secondary;
      case FollowUpStage.integrated:
        return AppColors.success;
      case FollowUpStage.lost:
        return AppColors.error;
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
        stage.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _color,
        ),
      ),
    );
  }
}
