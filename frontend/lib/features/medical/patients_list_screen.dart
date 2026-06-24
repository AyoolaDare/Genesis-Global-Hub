import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/pagination_footer.dart';
import '../../providers/medical_provider.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class PatientsListScreen extends ConsumerStatefulWidget {
  const PatientsListScreen({super.key});

  @override
  ConsumerState<PatientsListScreen> createState() =>
      _PatientsListScreenState();
}

class _PatientsListScreenState extends ConsumerState<PatientsListScreen> {
  int _page = 1;
  String _search = '';
  final _searchController = TextEditingController();

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
        ref.read(medicalProvider.notifier).refresh(
              page: 1,
              search: value.isNotEmpty ? value : null,
            );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(medicalProvider);

    return ShellLayout(
      title: 'My Patients',
      actions: [
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New Patient'),
          onPressed: () => context.go('/medical/patients/new'),
        ),
        const SizedBox(width: 8),
      ],
      child: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: patientsAsync.when(
              loading: () => Padding(
                padding: const EdgeInsets.all(24),
                child: ListSkeleton(
                  count: 5,
                  itemBuilder: () => const PatientCardSkeleton(),
                ),
              ),
              error: (e, _) => ErrorState(
                message: e.toString().contains('403')
                    ? 'Access Denied'
                    : 'Failed to load patients',
                onRetry: () => ref.invalidate(medicalProvider),
              ),
              data: (patients) => patients.items.isEmpty
                  ? EmptyState(
                      icon: Icons.sick_outlined,
                      title: 'No patients found',
                      subtitle: _search.isNotEmpty
                          ? 'No patients match "$_search"'
                          : 'You have no patients yet.',
                      actionLabel: 'Add Patient',
                      onAction: () => context.go('/medical/patients/new'),
                    )
                  : _buildList(patients),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search patients by name or phone...',
          prefixIcon:
              const Icon(Icons.search, color: AppColors.textSecondary),
          suffixIcon: _search.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _search = '';
                      _page = 1;
                    });
                    ref.read(medicalProvider.notifier).refresh();
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildList(PatientsList patients) {
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: patients.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) =>
                _PatientCard(patient: patients.items[i]),
          ),
        ),
        PaginationFooter(
          currentPage: _page,
          totalPages: patients.totalPages,
          totalItems: patients.total,
          pageSize: 20,
          onPageChanged: (p) {
            setState(() => _page = p);
            ref.read(medicalProvider.notifier).refresh(
                  page: p,
                  search: _search.isNotEmpty ? _search : null,
                );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Patient card
// ---------------------------------------------------------------------------

class _PatientCard extends StatelessWidget {
  final Patient patient;

  const _PatientCard({required this.patient});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/medical/patients/${patient.id}'),
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
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.person_outline,
                      size: 24, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patient.fullName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (patient.phone != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          patient.phone!,
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                // Church member indicator — TEXT ONLY, no link
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: patient.isChurchMember
                        ? AppColors.success.withOpacity(0.1)
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: patient.isChurchMember
                          ? AppColors.success.withOpacity(0.3)
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    patient.isChurchMember ? 'Member' : 'Non-member',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: patient.isChurchMember
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  patient.lastVisit != null
                      ? 'Last visit: ${_formatDate(patient.lastVisit!)}'
                      : 'No visits yet',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
