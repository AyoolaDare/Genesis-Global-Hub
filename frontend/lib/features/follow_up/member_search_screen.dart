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
// Model (limited fields for follow-up role)
// ---------------------------------------------------------------------------

class MemberSearchResult {
  final String id;
  final String fullName;
  final String? phone;
  final String status;

  const MemberSearchResult({
    required this.id,
    required this.fullName,
    this.phone,
    required this.status,
  });

  factory MemberSearchResult.fromJson(Map<String, dynamic> json) {
    return MemberSearchResult(
      id: json['id'] ?? '',
      fullName: '${json['first_name'] ?? ''} ${json['last_name'] ?? ''}'.trim(),
      phone: json['phone'],
      status: json['status'] ?? 'ACTIVE',
    );
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final memberSearchResultsProvider =
    FutureProvider.family<List<MemberSearchResult>, String>(
  (ref, query) async {
    if (query.trim().length < 2) return [];
    final dio = ref.read(dioProvider);
    final response = await dio.get(
      ApiEndpoints.memberSearch,
      queryParameters: {'q': query.trim(), 'limit': 20},
    );
    final data = response.data['data'] as List;
    return data.map((e) => MemberSearchResult.fromJson(e)).toList();
  },
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class MemberSearchScreen extends ConsumerStatefulWidget {
  const MemberSearchScreen({super.key});

  @override
  ConsumerState<MemberSearchScreen> createState() =>
      _MemberSearchScreenState();
}

class _MemberSearchScreenState extends ConsumerState<MemberSearchScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _hasSearched = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_searchController.text == value) {
        setState(() {
          _query = value;
          _hasSearched = value.trim().length >= 2;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ShellLayout(
      title: 'Member Search',
      child: Column(
        children: [
          _buildSearchBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Search Church Members',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Search by name or phone number to find basic contact information.',
            style:
                TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Type a name or phone number...',
              prefixIcon:
                  const Icon(Icons.search, color: AppColors.textSecondary),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _query = '';
                          _hasSearched = false;
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                    color: AppColors.primary, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
            ),
            onChanged: _onSearchChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_hasSearched || _query.trim().length < 2) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search,
                size: 80, color: AppColors.surfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Start typing to search',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter at least 2 characters',
              style:
                  TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    final resultsAsync =
        ref.watch(memberSearchResultsProvider(_query));

    return resultsAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(24),
        child: ListSkeleton(
          count: 4,
          itemBuilder: () => const MemberCardSkeleton(),
        ),
      ),
      error: (e, _) => ErrorState(
        message: e.toString().contains('403')
            ? 'Access Denied'
            : 'Search failed',
        details: e.toString().contains('403')
            ? 'You do not have permission to search members.'
            : 'Please try again.',
        onRetry: () =>
            ref.invalidate(memberSearchResultsProvider(_query)),
      ),
      data: (results) => results.isEmpty
          ? EmptyState(
              icon: Icons.person_search_outlined,
              title: 'No results found',
              subtitle: 'No members match "$_query".',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: results.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) =>
                  _MemberSearchCard(result: results[i]),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Result card (limited fields — no link to full profile)
// ---------------------------------------------------------------------------

class _MemberSearchCard extends StatelessWidget {
  final MemberSearchResult result;

  const _MemberSearchCard({required this.result});

  Color get _statusColor {
    switch (result.status.toUpperCase()) {
      case 'ACTIVE':
        return AppColors.statusActive;
      case 'INACTIVE':
        return AppColors.statusInactive;
      case 'PENDING':
        return AppColors.statusPending;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
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
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primary.withOpacity(0.15),
            child: Text(
              result.fullName.isNotEmpty
                  ? result.fullName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.fullName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (result.phone != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        result.phone!,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: _statusColor.withOpacity(0.3)),
            ),
            child: Text(
              result.status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
