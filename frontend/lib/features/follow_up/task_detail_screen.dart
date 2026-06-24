import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/error_state.dart';
import '../../providers/follow_up_provider.dart';

// ---------------------------------------------------------------------------
// Notes provider
// ---------------------------------------------------------------------------

class FollowUpNote {
  final String id;
  final String taskId;
  final String content;
  final DateTime createdAt;
  final String? authorName;

  const FollowUpNote({
    required this.id,
    required this.taskId,
    required this.content,
    required this.createdAt,
    this.authorName,
  });

  factory FollowUpNote.fromJson(Map<String, dynamic> json) {
    return FollowUpNote(
      id: json['id'] ?? '',
      taskId: json['task_id'] ?? '',
      content: json['content'] ?? '',
      createdAt: DateTime.parse(
          json['created_at'] ?? DateTime.now().toIso8601String()),
      authorName: json['author_name'],
    );
  }
}

final taskNotesProvider =
    FutureProvider.family<List<FollowUpNote>, String>((ref, taskId) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get('/follow-up/notes/$taskId');
  final data = response.data['data'] as List;
  return data.map((e) => FollowUpNote.fromJson(e)).toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class TaskDetailScreen extends ConsumerStatefulWidget {
  final String taskId;

  const TaskDetailScreen({super.key, required this.taskId});

  @override
  ConsumerState<TaskDetailScreen> createState() =>
      _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  bool _isActionLoading = false;
  final _noteController = TextEditingController();
  FollowUpStage? _selectedStage;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final taskAsync =
        ref.watch(followUpTaskDetailProvider(widget.taskId));

    return ShellLayout(
      title: 'Task Detail',
      child: taskAsync.when(
        loading: () => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SkeletonBox(height: 200),
              const SizedBox(height: 16),
              const SkeletonBox(height: 300),
            ],
          ),
        ),
        error: (e, _) => ErrorState(
          message: e.toString().contains('403')
              ? 'Access Denied'
              : 'Failed to load task',
          onRetry: () => ref.invalidate(
              followUpTaskDetailProvider(widget.taskId)),
        ),
        data: (task) => _buildContent(context, task),
      ),
    );
  }

  Widget _buildContent(BuildContext context, FollowUpTask task) {
    final notesAsync = ref.watch(taskNotesProvider(task.id));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Contact info card
          _ContactInfoCard(task: task),
          const SizedBox(height: 16),
          // Stage progression
          _StageProgressCard(task: task),
          const SizedBox(height: 16),
          // Actions card
          _buildActionsCard(context, task),
          const SizedBox(height: 16),
          // Notes section
          _NotesSection(
            notesAsync: notesAsync,
            taskId: task.id,
            noteController: _noteController,
            onAddNote: (content) => _addNote(task.id, content),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard(BuildContext context, FollowUpTask task) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Actions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          // Stage update
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<FollowUpStage>(
                  value: _selectedStage ?? task.stage,
                  decoration: const InputDecoration(
                    labelText: 'Update Stage',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  items: FollowUpStage.values
                      .where((s) => s != FollowUpStage.lost)
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(s.label),
                        ),
                      )
                      .toList(),
                  onChanged: (s) => setState(() => _selectedStage = s),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _isActionLoading ||
                        (_selectedStage == null ||
                            _selectedStage == task.stage)
                    ? null
                    : () => _updateStage(task.id, _selectedStage!),
                child: const Text('Update'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (!task.isCompleted)
                ElevatedButton.icon(
                  icon: _isActionLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.white),
                        )
                      : const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Complete Task'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: AppColors.white,
                  ),
                  onPressed: _isActionLoading
                      ? null
                      : () => _completeTask(task.id),
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.escalator_warning_outlined, size: 18),
                label: const Text('Escalate'),
                onPressed: () => _showEscalateDialog(context, task.id),
              ),
            ],
          ),
          if (task.isCompleted)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 18, color: AppColors.success),
                  const SizedBox(width: 8),
                  Text(
                    'Completed on ${task.completedAt != null ? _formatDate(task.completedAt!) : "N/A"}',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.success),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _completeTask(String taskId) async {
    setState(() => _isActionLoading = true);
    try {
      await ref.read(followUpProvider.notifier).completeTask(taskId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task marked as complete'),
            backgroundColor: AppColors.success,
          ),
        );
        ref.invalidate(followUpTaskDetailProvider(taskId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to complete task: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _updateStage(
      String taskId, FollowUpStage stage) async {
    setState(() => _isActionLoading = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.put(
        ApiEndpoints.followUpTaskById(taskId),
        data: {'stage': stage.value},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stage updated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        ref.invalidate(followUpTaskDetailProvider(taskId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update stage: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _addNote(String taskId, String content) async {
    if (content.trim().isEmpty) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/follow-up/notes', data: {
        'task_id': taskId,
        'content': content.trim(),
      });
      _noteController.clear();
      ref.invalidate(taskNotesProvider(taskId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add note: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _showEscalateDialog(
      BuildContext context, String taskId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Escalate Task'),
        content: const Text(
            'Are you sure you want to escalate this follow-up task to your supervisor?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Escalate'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task escalated to supervisor')),
      );
    }
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ---------------------------------------------------------------------------
// Contact info card
// ---------------------------------------------------------------------------

class _ContactInfoCard extends StatelessWidget {
  final FollowUpTask task;

  const _ContactInfoCard({required this.task});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Contact Information',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _InfoRow(
              icon: Icons.person_outline,
              label: 'Name',
              value: task.convertName),
          if (task.convertPhone != null)
            _InfoRow(
                icon: Icons.phone_outlined,
                label: 'Phone',
                value: task.convertPhone!),
          if (task.notes != null)
            _InfoRow(
                icon: Icons.notes_outlined,
                label: 'Notes',
                value: task.notes!),
          _InfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Due Date',
            value:
                '${task.dueDate.day}/${task.dueDate.month}/${task.dueDate.year}',
          ),
          if (task.assignedToName != null)
            _InfoRow(
              icon: Icons.person_pin_outlined,
              label: 'Assigned To',
              value: task.assignedToName!,
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stage progress card
// ---------------------------------------------------------------------------

class _StageProgressCard extends StatelessWidget {
  final FollowUpTask task;

  const _StageProgressCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final stages = [
      FollowUpStage.initial,
      FollowUpStage.firstContact,
      FollowUpStage.secondContact,
      FollowUpStage.thirdContact,
      FollowUpStage.integrated,
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Follow-up Progress',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 20),
          Row(
            children: stages.asMap().entries.map((entry) {
              final i = entry.key;
              final stage = entry.value;
              final isCompleted =
                  stage.stepIndex <= task.stage.stepIndex;
              final isCurrent = stage == task.stage;

              return Expanded(
                child: Row(
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isCompleted
                                ? AppColors.primary
                                : AppColors.surfaceVariant,
                            shape: BoxShape.circle,
                            border: isCurrent
                                ? Border.all(
                                    color: AppColors.secondary, width: 2)
                                : null,
                          ),
                          child: Icon(
                            isCompleted
                                ? Icons.check
                                : Icons.circle_outlined,
                            size: 16,
                            color: isCompleted
                                ? AppColors.white
                                : AppColors.textDisabled,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          stage.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isCurrent
                                ? FontWeight.w700
                                : FontWeight.normal,
                            color: isCompleted
                                ? AppColors.primary
                                : AppColors.textDisabled,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                    if (i < stages.length - 1)
                      Expanded(
                        child: Container(
                          height: 2,
                          color: isCompleted &&
                                  stages[i + 1].stepIndex <=
                                      task.stage.stepIndex
                              ? AppColors.primary
                              : AppColors.surfaceVariant,
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notes section
// ---------------------------------------------------------------------------

class _NotesSection extends StatelessWidget {
  final AsyncValue<List<FollowUpNote>> notesAsync;
  final String taskId;
  final TextEditingController noteController;
  final Future<void> Function(String) onAddNote;

  const _NotesSection({
    required this.notesAsync,
    required this.taskId,
    required this.noteController,
    required this.onAddNote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notes', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          // Add note
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Add a note...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                onPressed: () => onAddNote(noteController.text),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          // Notes list
          notesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => const Text(
              'Failed to load notes',
              style: TextStyle(color: AppColors.error),
            ),
            data: (notes) => notes.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No notes yet',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  )
                : Column(
                    children: notes
                        .map((note) => _NoteItem(note: note))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NoteItem extends StatelessWidget {
  final FollowUpNote note;

  const _NoteItem({required this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: AppColors.primary, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                note.authorName ?? 'Unknown',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              Text(
                '${note.createdAt.day}/${note.createdAt.month}/${note.createdAt.year}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            note.content,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
