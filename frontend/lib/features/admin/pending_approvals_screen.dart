import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/members_provider.dart';

class PendingApprovalsScreen extends ConsumerWidget {
  const PendingApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingMembersProvider);
    return ShellLayout(
      title: 'Pending Approvals',
      child: pendingAsync.when(
        loading: () => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 5,
          itemBuilder: (_, __) => const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: MemberCardSkeleton(),
          ),
        ),
        error: (e, _) => ErrorState(
          message: 'Failed to load pending approvals',
          details: e.toString(),
          onRetry: () => ref.invalidate(pendingMembersProvider),
        ),
        data: (members) {
          if (members.isEmpty) {
            return const EmptyState(
              icon: Icons.check_circle_outline,
              title: 'All caught up!',
              subtitle: 'No pending member approvals at this time.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: members.length,
            itemBuilder: (_, i) => _PendingMemberCard(member: members[i]),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pending member card
// ---------------------------------------------------------------------------

class _PendingMemberCard extends ConsumerStatefulWidget {
  final Member member;

  const _PendingMemberCard({required this.member});

  @override
  ConsumerState<_PendingMemberCard> createState() =>
      _PendingMemberCardState();
}

class _PendingMemberCardState extends ConsumerState<_PendingMemberCard> {
  bool _isExpanded = false;
  bool _isActioning = false;

  Future<void> _approve() async {
    final confirmed = await _confirm(
      context,
      'Approve Member',
      'Approve ${widget.member.fullName} as an active member?',
    );
    if (!confirmed) return;
    setState(() => _isActioning = true);
    try {
      await ref
          .read(membersProvider.notifier)
          .approveMember(widget.member.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.member.fullName} approved'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActioning = false);
    }
  }

  Future<void> _reject() async {
    final reason = await _getRejectionReason();
    if (reason == null) return;
    setState(() => _isActioning = true);
    try {
      await ref
          .read(membersProvider.notifier)
          .rejectMember(widget.member.id, reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.member.fullName} rejected'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActioning = false);
    }
  }

  Future<bool> _confirm(
      BuildContext context, String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<String?> _getRejectionReason() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject Member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                'Please provide a reason for rejecting ${widget.member.fullName}:'),
            const SizedBox(height: 16),
            TextFormField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Reason for rejection...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.of(context).pop(controller.text.trim());
              }
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                widget.member.fullName,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              if (widget.member.isDuplicateFlagged) ...[
                                const SizedBox(width: 8),
                                _DuplicateBadge(),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Submitted by: ${widget.member.submittedByName ?? "Unknown"}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (widget.member.submittedAt != null)
                            Text(
                              dateFormat.format(widget.member.submittedAt!),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textDisabled,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                          _isExpanded
                              ? Icons.expand_less
                              : Icons.expand_more),
                      onPressed: () =>
                          setState(() => _isExpanded = !_isExpanded),
                    ),
                  ],
                ),

                // Details (expanded)
                if (_isExpanded) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 12),
                  _DetailRow('Phone', widget.member.phone ?? 'N/A'),
                  _DetailRow('Email', widget.member.email ?? 'N/A'),
                  _DetailRow('Gender', widget.member.gender ?? 'N/A'),
                  if (widget.member.notes != null)
                    _DetailRow('Notes', widget.member.notes!),
                ],

                const SizedBox(height: 16),
                // Action buttons
                if (_isActioning)
                  const Center(child: CircularProgressIndicator())
                else
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _approve,
                          icon: const Icon(Icons.check_circle_outline,
                              size: 16),
                          label: const Text('Approve'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _reject,
                          icon: const Icon(Icons.cancel_outlined,
                              size: 16),
                          label: const Text('Reject'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side:
                                const BorderSide(color: AppColors.error),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () {},
                        child: const Text('Info'),
                      ),
                      if (widget.member.isDuplicateFlagged) ...[
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () =>
                              _showMergeDialog(context),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.warning),
                          child: const Text('Merge'),
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

  void _showMergeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Merge Duplicate Records'),
        content: const Text(
          'This will merge the duplicate record. Select which fields to keep from each record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Proceed to Merge'),
          ),
        ],
      ),
    );
  }
}

class _DuplicateBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 12, color: AppColors.error),
          SizedBox(width: 4),
          Text(
            'Duplicate',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
