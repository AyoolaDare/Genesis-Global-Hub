import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/error_state.dart';
import '../../providers/hr_provider.dart';

// ---------------------------------------------------------------------------
// Leave request model & provider
// ---------------------------------------------------------------------------

class LeaveRequest {
  final String id;
  final String leaveType;
  final DateTime startDate;
  final DateTime endDate;
  final int days;
  final String status;
  final String? reason;

  const LeaveRequest({
    required this.id,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.status,
    this.reason,
  });

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    return LeaveRequest(
      id: json['id'] ?? '',
      leaveType: json['leave_type'] ?? '',
      startDate: DateTime.parse(
          json['start_date'] ?? DateTime.now().toIso8601String()),
      endDate: DateTime.parse(
          json['end_date'] ?? DateTime.now().toIso8601String()),
      days: json['days'] ?? 0,
      status: json['status'] ?? 'PENDING',
      reason: json['reason'],
    );
  }
}

final workerLeaveProvider =
    FutureProvider.family<List<LeaveRequest>, String>(
        (ref, workerId) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(
    ApiEndpoints.leaveRequests,
    queryParameters: {'worker_id': workerId},
  );
  final data = response.data['data'] as List;
  return data.map((e) => LeaveRequest.fromJson(e)).toList();
});

final workerPerformanceProvider =
    FutureProvider.family<List<PerformanceReview>, String>(
        (ref, workerId) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(
    ApiEndpoints.performance,
    queryParameters: {'worker_id': workerId},
  );
  final data = response.data['data'] as List;
  return data.map((e) => PerformanceReview.fromJson(e)).toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class WorkerDetailScreen extends ConsumerWidget {
  final String workerId;

  const WorkerDetailScreen({super.key, required this.workerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workerAsync = ref.watch(workerDetailProvider(workerId));

    return ShellLayout(
      title: 'Worker Detail',
      child: workerAsync.when(
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
              : 'Failed to load worker',
          onRetry: () =>
              ref.invalidate(workerDetailProvider(workerId)),
        ),
        data: (worker) => _WorkerDetailView(
          worker: worker,
          workerId: workerId,
        ),
      ),
    );
  }
}

class _WorkerDetailView extends ConsumerStatefulWidget {
  final Worker worker;
  final String workerId;

  const _WorkerDetailView(
      {required this.worker, required this.workerId});

  @override
  ConsumerState<_WorkerDetailView> createState() =>
      _WorkerDetailViewState();
}

class _WorkerDetailViewState
    extends ConsumerState<_WorkerDetailView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(context),
        TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Info'),
            Tab(text: 'Performance'),
            Tab(text: 'Leave'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _InfoTab(worker: widget.worker),
              _PerformanceTab(workerId: widget.workerId),
              _LeaveTab(workerId: widget.workerId),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final w = widget.worker;
    return Container(
      padding: const EdgeInsets.all(20),
      color: AppColors.white,
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                w.fullName
                    .split(' ')
                    .take(2)
                    .map((s) => s.isNotEmpty ? s[0].toUpperCase() : '')
                    .join(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.fullName,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(w.role,
                    style: const TextStyle(
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
          _TypeBadge(type: w.employmentType),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.assessment_outlined, size: 16),
            label: const Text('Add Review'),
            onPressed: () =>
                context.go('/hr/performance?worker=${widget.workerId}'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info tab
// ---------------------------------------------------------------------------

class _InfoTab extends StatelessWidget {
  final Worker worker;

  const _InfoTab({required this.worker});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
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
        child: Wrap(
          spacing: 24,
          runSpacing: 20,
          children: [
            if (worker.email != null)
              _InfoItem(label: 'Email', value: worker.email!),
            if (worker.phone != null)
              _InfoItem(label: 'Phone', value: worker.phone!),
            if (worker.department != null)
              _InfoItem(label: 'Department', value: worker.department!),
            _InfoItem(label: 'Role', value: worker.role),
            _InfoItem(
                label: 'Employment Type',
                value: worker.employmentType.replaceAll('_', ' ')),
            _InfoItem(label: 'Status', value: worker.status),
            if (worker.startDate != null)
              _InfoItem(
                label: 'Start Date',
                value:
                    '${worker.startDate!.day}/${worker.startDate!.month}/${worker.startDate!.year}',
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;

  const _InfoItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Performance tab
// ---------------------------------------------------------------------------

class _PerformanceTab extends ConsumerWidget {
  final String workerId;

  const _PerformanceTab({required this.workerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync =
        ref.watch(workerPerformanceProvider(workerId));

    return reviewsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(
        message: 'Failed to load reviews',
        onRetry: () =>
            ref.invalidate(workerPerformanceProvider(workerId)),
      ),
      data: (reviews) => reviews.isEmpty
          ? const Center(
              child: Text('No performance reviews yet',
                  style: TextStyle(color: AppColors.textSecondary)),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: reviews.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) =>
                  _ReviewCard(review: reviews[i]),
            ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final PerformanceReview review;

  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final scoreColor = review.score >= 4
        ? AppColors.success
        : review.score >= 3
            ? AppColors.warning
            : AppColors.error;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
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
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scoreColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                review.score.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: scoreColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  review.period,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (review.comments != null)
                  Text(
                    review.comments!,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Text(
            '${review.reviewDate.day}/${review.reviewDate.month}/${review.reviewDate.year}',
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Leave tab
// ---------------------------------------------------------------------------

class _LeaveTab extends ConsumerWidget {
  final String workerId;

  const _LeaveTab({required this.workerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaveAsync = ref.watch(workerLeaveProvider(workerId));

    return leaveAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(
        message: 'Failed to load leave requests',
        onRetry: () => ref.invalidate(workerLeaveProvider(workerId)),
      ),
      data: (requests) => requests.isEmpty
          ? const Center(
              child: Text('No leave requests',
                  style: TextStyle(color: AppColors.textSecondary)),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: requests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) =>
                  _LeaveCard(request: requests[i]),
            ),
    );
  }
}

class _LeaveCard extends StatelessWidget {
  final LeaveRequest request;

  const _LeaveCard({required this.request});

  Color get _statusColor {
    switch (request.status.toUpperCase()) {
      case 'APPROVED':
        return AppColors.success;
      case 'REJECTED':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
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
                Text(
                  request.leaveType.replaceAll('_', ' '),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${request.startDate.day}/${request.startDate.month}/${request.startDate.year} — ${request.endDate.day}/${request.endDate.month}/${request.endDate.year}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary),
                ),
                if (request.reason != null)
                  Text(
                    request.reason!,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  request.status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _statusColor,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${request.days}d',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

class _TypeBadge extends StatelessWidget {
  final String type;

  const _TypeBadge({required this.type});

  Color get _color {
    switch (type.toUpperCase()) {
      case 'FULL_TIME':
        return AppColors.primary;
      case 'PART_TIME':
        return AppColors.info;
      case 'CONTRACT':
        return AppColors.warning;
      case 'VOLUNTEER':
        return AppColors.secondary;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withOpacity(0.3)),
      ),
      child: Text(
        type.replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _color,
        ),
      ),
    );
  }
}
