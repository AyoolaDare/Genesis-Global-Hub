import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/pagination_footer.dart';
import '../../providers/sponsor_provider.dart';

// ---------------------------------------------------------------------------
// Create sponsor form provider state
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class SponsorsListScreen extends ConsumerStatefulWidget {
  const SponsorsListScreen({super.key});

  @override
  ConsumerState<SponsorsListScreen> createState() =>
      _SponsorsListScreenState();
}

class _SponsorsListScreenState extends ConsumerState<SponsorsListScreen> {
  int _page = 1;
  String _search = '';
  String? _tierFilter;
  final _searchController = TextEditingController();

  static const List<String> _tiers = [
    'MONTHLY',
    'QUARTERLY',
    'ANNUAL',
    'ONE_TIME',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_searchController.text == value) {
        setState(() {
          _search = value;
          _page = 1;
        });
        ref.read(sponsorProvider.notifier).refresh(
              search: value.isNotEmpty ? value : null,
            );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sponsorsAsync = ref.watch(sponsorProvider);

    return ShellLayout(
      title: 'Sponsors',
      actions: [
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Sponsor'),
          onPressed: () => _showCreateSponsorSheet(context),
        ),
        const SizedBox(width: 8),
      ],
      child: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: sponsorsAsync.when(
              loading: () => Padding(
                padding: const EdgeInsets.all(24),
                child: ListSkeleton(
                  count: 5,
                  itemBuilder: () => const MemberCardSkeleton(),
                ),
              ),
              error: (e, _) => ErrorState(
                message: e.toString().contains('403')
                    ? 'Access Denied'
                    : 'Failed to load sponsors',
                onRetry: () => ref.invalidate(sponsorProvider),
              ),
              data: (sponsors) {
                // Apply tier filter client-side
                var items = sponsors.items;
                if (_tierFilter != null) {
                  items = items
                      .where((s) => s.category == _tierFilter)
                      .toList();
                }

                return items.isEmpty
                    ? EmptyState(
                        icon: Icons.volunteer_activism_outlined,
                        title: 'No sponsors found',
                        subtitle: _search.isNotEmpty
                            ? 'No sponsors match "$_search"'
                            : 'Add your first sponsor to get started.',
                        actionLabel: 'Add Sponsor',
                        onAction: () => _showCreateSponsorSheet(context),
                      )
                    : _buildList(items, sponsors);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search sponsors...',
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textSecondary),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _search = '';
                            _page = 1;
                          });
                          ref.read(sponsorProvider.notifier).refresh();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              value: _tierFilter,
              decoration: const InputDecoration(
                labelText: 'Tier',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('All Tiers')),
                ..._tiers.map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(t.replaceAll('_', ' ')),
                  ),
                ),
              ],
              onChanged: (v) => setState(() {
                _tierFilter = v;
                _page = 1;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<Sponsor> items, SponsorsList full) {
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) =>
                _SponsorCard(sponsor: items[i]),
          ),
        ),
        PaginationFooter(
          currentPage: _page,
          totalPages: full.totalPages,
          totalItems: full.total,
          pageSize: 20,
          onPageChanged: (p) {
            setState(() => _page = p);
            ref.read(sponsorProvider.notifier).refresh(page: p);
          },
        ),
      ],
    );
  }

  void _showCreateSponsorSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _CreateSponsorSheet(
        onCreated: () {
          ref.read(sponsorProvider.notifier).refresh();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sponsor card
// ---------------------------------------------------------------------------

class _SponsorCard extends StatelessWidget {
  final Sponsor sponsor;

  const _SponsorCard({required this.sponsor});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/finance/sponsors/${sponsor.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
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
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.volunteer_activism_outlined,
                  size: 24, color: AppColors.secondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sponsor.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (sponsor.category != null)
                        _TierBadge(tier: sponsor.category!),
                    ],
                  ),
                  if (sponsor.phone != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      sponsor.phone!,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'Total: ₦${sponsor.totalContributions.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 20, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _TierBadge extends StatelessWidget {
  final String tier;

  const _TierBadge({required this.tier});

  Color get _color {
    switch (tier.toUpperCase()) {
      case 'ANNUAL':
        return AppColors.secondary;
      case 'QUARTERLY':
        return AppColors.primary;
      case 'MONTHLY':
        return AppColors.info;
      default:
        return AppColors.textSecondary;
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
        tier.replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: _color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create sponsor bottom sheet
// ---------------------------------------------------------------------------

class _CreateSponsorSheet extends ConsumerStatefulWidget {
  final VoidCallback onCreated;

  const _CreateSponsorSheet({required this.onCreated});

  @override
  ConsumerState<_CreateSponsorSheet> createState() =>
      _CreateSponsorSheetState();
}

class _CreateSponsorSheetState
    extends ConsumerState<_CreateSponsorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _amountController = TextEditingController();
  String? _tier;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Add New Sponsor',
                    style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Sponsor Name *',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Pledge Amount (₦)',
                      border: OutlineInputBorder(),
                      prefixText: '₦ ',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _tier,
                    decoration: const InputDecoration(
                      labelText: 'Tier',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 15),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'MONTHLY', child: Text('Monthly')),
                      DropdownMenuItem(
                          value: 'QUARTERLY',
                          child: Text('Quarterly')),
                      DropdownMenuItem(
                          value: 'ANNUAL', child: Text('Annual')),
                      DropdownMenuItem(
                          value: 'ONE_TIME', child: Text('One-time')),
                    ],
                    onChanged: (v) => setState(() => _tier = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.white),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label:
                    Text(_isSubmitting ? 'Saving...' : 'Create Sponsor'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _isSubmitting ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(ApiEndpoints.sponsors, data: {
        'name': _nameController.text.trim(),
        if (_phoneController.text.trim().isNotEmpty)
          'phone': _phoneController.text.trim(),
        if (_emailController.text.trim().isNotEmpty)
          'email': _emailController.text.trim(),
        if (_amountController.text.trim().isNotEmpty)
          'pledge_amount': double.tryParse(_amountController.text.trim()),
        if (_tier != null) 'category': _tier,
      });
      widget.onCreated();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create sponsor: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
