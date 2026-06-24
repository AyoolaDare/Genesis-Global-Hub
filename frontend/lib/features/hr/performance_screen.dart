import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/empty_state.dart';
import '../../providers/hr_provider.dart';

// ---------------------------------------------------------------------------
// Workers pending review provider
// ---------------------------------------------------------------------------

final workersPendingReviewProvider =
    FutureProvider<List<Worker>>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(
    ApiEndpoints.workers,
    queryParameters: {'status': 'ACTIVE', 'needs_review': true},
  );
  final data = response.data['data'] as List;
  return data.map((e) => Worker.fromJson(e)).toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class PerformanceScreen extends ConsumerStatefulWidget {
  final String? preselectedWorkerId;

  const PerformanceScreen({super.key, this.preselectedWorkerId});

  @override
  ConsumerState<PerformanceScreen> createState() =>
      _PerformanceScreenState();
}

class _PerformanceScreenState
    extends ConsumerState<PerformanceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShellLayout(
      title: 'Performance Reviews',
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: 'Create Review'),
              Tab(text: 'Past Reviews'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _CreateReviewTab(
                    preselectedWorkerId: widget.preselectedWorkerId),
                _PastReviewsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create review tab
// ---------------------------------------------------------------------------

class _CreateReviewTab extends ConsumerStatefulWidget {
  final String? preselectedWorkerId;

  const _CreateReviewTab({this.preselectedWorkerId});

  @override
  ConsumerState<_CreateReviewTab> createState() =>
      _CreateReviewTabState();
}

class _CreateReviewTabState
    extends ConsumerState<_CreateReviewTab> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedWorkerId;
  final _periodController = TextEditingController();
  final _strengthsController = TextEditingController();
  final _areasController = TextEditingController();
  final _commentsController = TextEditingController();

  // Individual score sliders (1–5)
  double _attendanceScore = 3;
  double _performanceScore = 3;
  double _teamworkScore = 3;
  double _initiativeScore = 3;

  bool _isSubmitting = false;

  double get _avgScore =>
      (_attendanceScore + _performanceScore + _teamworkScore + _initiativeScore) / 4;

  @override
  void initState() {
    super.initState();
    _selectedWorkerId = widget.preselectedWorkerId;
  }

  @override
  void dispose() {
    _periodController.dispose();
    _strengthsController.dispose();
    _areasController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workersAsync = ref.watch(hrProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Worker selection
                _buildCard(
                  context,
                  title: 'Select Worker',
                  child: workersAsync.when(
                    loading: () => const SkeletonBox(height: 56),
                    error: (_, __) => const Text('Failed to load workers',
                        style: TextStyle(color: AppColors.error)),
                    data: (workers) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String>(
                        value: _selectedWorkerId,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        hint: const Text('Choose a worker',
                            style: TextStyle(
                                color: AppColors.textSecondary)),
                        items: workers.items
                            .map((w) => DropdownMenuItem(
                                value: w.id,
                                child: Text(w.fullName)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedWorkerId = v),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Review period
                _buildCard(
                  context,
                  title: 'Review Period',
                  child: TextFormField(
                    controller: _periodController,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Q1 2026, January 2026',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty
                            ? 'Period is required'
                            : null,
                  ),
                ),
                const SizedBox(height: 16),
                // Scores
                _buildCard(
                  context,
                  title: 'Scores (1 = Poor, 5 = Excellent)',
                  child: Column(
                    children: [
                      _ScoreSlider(
                        label: 'Attendance & Punctuality',
                        value: _attendanceScore,
                        onChanged: (v) =>
                            setState(() => _attendanceScore = v),
                      ),
                      const SizedBox(height: 12),
                      _ScoreSlider(
                        label: 'Job Performance',
                        value: _performanceScore,
                        onChanged: (v) =>
                            setState(() => _performanceScore = v),
                      ),
                      const SizedBox(height: 12),
                      _ScoreSlider(
                        label: 'Teamwork & Collaboration',
                        value: _teamworkScore,
                        onChanged: (v) =>
                            setState(() => _teamworkScore = v),
                      ),
                      const SizedBox(height: 12),
                      _ScoreSlider(
                        label: 'Initiative & Leadership',
                        value: _initiativeScore,
                        onChanged: (v) =>
                            setState(() => _initiativeScore = v),
                      ),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Overall Average',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600)),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _scoreColor(_avgScore)
                                  .withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _avgScore.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: _scoreColor(_avgScore),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Strengths & areas
                _buildCard(
                  context,
                  title: 'Written Feedback',
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _strengthsController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Strengths',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                          hintText:
                              'What is this worker doing well?',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _areasController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Areas for Growth',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                          hintText:
                              'Where can this worker improve?',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _commentsController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Additional Comments',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.white),
                          )
                        : const Icon(Icons.save_outlined, size: 20),
                    label: Text(_isSubmitting
                        ? 'Submitting...'
                        : 'Submit Review'),
                    style: ElevatedButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _isSubmitting ? null : _submit,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context,
      {required String title, required Widget child}) {
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
          Text(title,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Color _scoreColor(double score) {
    if (score >= 4) return AppColors.success;
    if (score >= 3) return AppColors.warning;
    return AppColors.error;
  }

  Future<void> _submit() async {
    if (_selectedWorkerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a worker'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(ApiEndpoints.performance, data: {
        'worker_id': _selectedWorkerId,
        'period': _periodController.text.trim(),
        'score': _avgScore,
        'attendance_score': _attendanceScore,
        'performance_score': _performanceScore,
        'teamwork_score': _teamworkScore,
        'initiative_score': _initiativeScore,
        if (_strengthsController.text.trim().isNotEmpty)
          'strengths': _strengthsController.text.trim(),
        if (_areasController.text.trim().isNotEmpty)
          'areas_for_growth': _areasController.text.trim(),
        if (_commentsController.text.trim().isNotEmpty)
          'comments': _commentsController.text.trim(),
      });
      ref.invalidate(performanceProvider);
      ref.invalidate(workersPendingReviewProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Performance review submitted'),
            backgroundColor: AppColors.success,
          ),
        );
        // Reset form
        setState(() {
          _selectedWorkerId = null;
          _periodController.clear();
          _strengthsController.clear();
          _areasController.clear();
          _commentsController.clear();
          _attendanceScore = 3;
          _performanceScore = 3;
          _teamworkScore = 3;
          _initiativeScore = 3;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit review: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Score slider widget
// ---------------------------------------------------------------------------

class _ScoreSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _ScoreSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  Color get _color {
    if (value >= 4) return AppColors.success;
    if (value >= 3) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary)),
        ),
        Expanded(
          flex: 4,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _color,
              thumbColor: _color,
              overlayColor: _color.withOpacity(0.12),
              inactiveTrackColor: AppColors.border,
            ),
            child: Slider(
              value: value,
              min: 1,
              max: 5,
              divisions: 4,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 28,
          child: Text(
            value.toStringAsFixed(0),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _color,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Past reviews tab
// ---------------------------------------------------------------------------

class _PastReviewsTab extends ConsumerWidget {
  const _PastReviewsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(performanceProvider);

    return reviewsAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(24),
        child: ListSkeleton(
          count: 4,
          itemBuilder: () => const SkeletonBox(height: 80),
        ),
      ),
      error: (e, _) => ErrorState(
        message: e.toString().contains('403')
            ? 'Access Denied'
            : 'Failed to load reviews',
        onRetry: () => ref.invalidate(performanceProvider),
      ),
      data: (reviews) => reviews.isEmpty
          ? const EmptyState(
              icon: Icons.assessment_outlined,
              title: 'No reviews yet',
              subtitle: 'Create a performance review to get started.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: reviews.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) =>
                  _PastReviewCard(review: reviews[i]),
            ),
    );
  }
}

class _PastReviewCard extends StatelessWidget {
  final PerformanceReview review;

  const _PastReviewCard({required this.review});

  Color get _scoreColor {
    if (review.score >= 4) return AppColors.success;
    if (review.score >= 3) return AppColors.warning;
    return AppColors.error;
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
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _scoreColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                review.score.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _scoreColor,
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
                  review.workerName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  review.period,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                if (review.comments != null)
                  Text(
                    review.comments!,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                    maxLines: 1,
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
