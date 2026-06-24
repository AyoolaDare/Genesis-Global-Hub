import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../providers/attendance_provider.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  bool _showCreateMeeting = false;
  final _titleController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(attendanceProvider.notifier).loadMeetings();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(attendanceProvider);

    return ShellLayout(
      title: 'Attendance',
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New Meeting'),
          onPressed: () =>
              setState(() => _showCreateMeeting = !_showCreateMeeting),
        ),
      ],
      child: state.isLoading && state.meetings.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: ListSkeleton(
                count: 4,
                itemBuilder: () => const SkeletonBox(height: 56),
              ),
            )
          : Column(
              children: [
                if (_showCreateMeeting) _buildCreateMeetingPanel(state),
                if (state.error != null)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.error, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          state.error!,
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Meeting list panel
                      SizedBox(
                        width: 280,
                        child: _MeetingListPanel(
                          meetings: state.meetings,
                          selectedMeeting: state.selectedMeeting,
                          onSelect: (meeting) {
                            ref
                                .read(attendanceProvider.notifier)
                                .selectMeeting(meeting);
                          },
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      // Attendance panel
                      Expanded(
                        child: state.selectedMeeting == null
                            ? const Center(
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.how_to_reg_outlined,
                                      size: 64,
                                      color: AppColors.textSecondary,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Select a meeting to mark attendance',
                                      style: TextStyle(
                                          color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              )
                            : _AttendancePanel(state: state),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCreateMeetingPanel(AttendanceState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Meeting Title',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(
                '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}'),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 30)),
              );
              if (picked != null) setState(() => _selectedDate = picked);
            },
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Create'),
            onPressed: state.isLoading
                ? null
                : () async {
                    final title = _titleController.text.trim();
                    if (title.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Please enter a meeting title')),
                      );
                      return;
                    }
                    await ref
                        .read(attendanceProvider.notifier)
                        .createMeeting(title, _selectedDate);
                    _titleController.clear();
                    setState(() => _showCreateMeeting = false);
                  },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () =>
                setState(() => _showCreateMeeting = false),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Meeting list panel
// ---------------------------------------------------------------------------

class _MeetingListPanel extends StatelessWidget {
  final List<Meeting> meetings;
  final Meeting? selectedMeeting;
  final ValueChanged<Meeting> onSelect;

  const _MeetingListPanel({
    required this.meetings,
    required this.selectedMeeting,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Meetings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: meetings.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No meetings yet.\nCreate one to start marking attendance.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: meetings.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final m = meetings[i];
                    final isSelected =
                        selectedMeeting?.id == m.id;
                    return ListTile(
                      selected: isSelected,
                      selectedTileColor:
                          AppColors.primary.withValues(alpha: 0.08),
                      onTap: () => onSelect(m),
                      title: Text(
                        m.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        '${m.meetingDate.day}/${m.meetingDate.month}/${m.meetingDate.year}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: m.totalExpected != null
                          ? Text(
                              '${m.totalPresent ?? 0}/${m.totalExpected}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            )
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Attendance panel
// ---------------------------------------------------------------------------

class _AttendancePanel extends ConsumerWidget {
  final AttendanceState state;

  const _AttendancePanel({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalCount = state.records.length;
    final presentCount = state.presentCount;
    final excusedCount = state.records
        .where((r) => r.status == AttendanceStatus.excused)
        .length;
    final absentCount =
        totalCount - presentCount - excusedCount;

    return Column(
      children: [
        // Summary bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Text(
                state.selectedMeeting?.title ?? '',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              _SummaryChip(
                label: '$presentCount Present',
                color: AppColors.success,
              ),
              const SizedBox(width: 8),
              _SummaryChip(
                label: '$excusedCount Excused',
                color: AppColors.info,
              ),
              const SizedBox(width: 8),
              _SummaryChip(
                label: '$absentCount Absent',
                color: AppColors.error,
              ),
              const SizedBox(width: 8),
              Text(
                '$presentCount / $totalCount present',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        // Toolbar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.done_all, size: 18),
                label: const Text('Mark All Present'),
                onPressed: () {
                  ref.read(attendanceProvider.notifier).markAllPresent();
                },
              ),
              const Spacer(),
              ElevatedButton.icon(
                icon: state.isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(state.isSaving ? 'Saving...' : 'Submit Attendance'),
                onPressed: state.isSaving
                    ? null
                    : () async {
                        final success = await ref
                            .read(attendanceProvider.notifier)
                            .submitAttendance();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                success
                                    ? 'Attendance saved successfully'
                                    : 'Failed to save attendance',
                              ),
                              backgroundColor:
                                  success ? AppColors.success : AppColors.error,
                            ),
                          );
                        }
                      },
              ),
            ],
          ),
        ),
        // Member list
        Expanded(
          child: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : state.records.isEmpty
                  ? const Center(
                      child: Text(
                        'No members in this group',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 8),
                      itemCount: state.records.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (context, i) =>
                          _AttendanceRow(
                            record: state.records[i],
                            onChanged: (status) {
                              ref
                                  .read(attendanceProvider.notifier)
                                  .updateAttendance(
                                      state.records[i].memberId, status);
                            },
                          ),
                    ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Attendance row
// ---------------------------------------------------------------------------

class _AttendanceRow extends StatelessWidget {
  final AttendanceRecord record;
  final ValueChanged<AttendanceStatus> onChanged;

  const _AttendanceRow({required this.record, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            backgroundImage: record.photoUrl != null
                ? NetworkImage(record.photoUrl!)
                : null,
            child: record.photoUrl == null
                ? Text(
                    record.memberName.isNotEmpty
                        ? record.memberName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              record.memberName,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          _AttendanceToggle(
            current: record.status,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _AttendanceToggle extends StatelessWidget {
  final AttendanceStatus current;
  final ValueChanged<AttendanceStatus> onChanged;

  const _AttendanceToggle(
      {required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<AttendanceStatus>(
      segments: const [
        ButtonSegment(
          value: AttendanceStatus.present,
          label: Text('Present'),
          icon: Icon(Icons.check_circle_outline, size: 16),
        ),
        ButtonSegment(
          value: AttendanceStatus.excused,
          label: Text('Excused'),
          icon: Icon(Icons.info_outline, size: 16),
        ),
        ButtonSegment(
          value: AttendanceStatus.absent,
          label: Text('Absent'),
          icon: Icon(Icons.cancel_outlined, size: 16),
        ),
      ],
      selected: {current},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary chip
// ---------------------------------------------------------------------------

class _SummaryChip extends StatelessWidget {
  final String label;
  final Color color;

  const _SummaryChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
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
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
