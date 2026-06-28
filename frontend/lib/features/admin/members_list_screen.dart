import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/pagination_footer.dart';
import '../../core/widgets/search_bar.dart';
import '../../core/theme/app_colors.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/utils/file_import.dart';
import '../../providers/members_provider.dart';

class MembersListScreen extends ConsumerStatefulWidget {
  const MembersListScreen({super.key});

  @override
  ConsumerState<MembersListScreen> createState() =>
      _MembersListScreenState();
}

class _MembersListScreenState extends ConsumerState<MembersListScreen> {
  Timer? _debounce;
  String _searchQuery = '';
  String? _statusFilter;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String value) {
    setState(() {
      _searchQuery = value;
    });
    ref.read(membersProvider.notifier).refresh(
          page: 1,
          search: value.isEmpty ? null : value,
          status: _statusFilter,
        );
  }

  void _onFilterChange(String? status) {
    setState(() {
      _statusFilter = status;
    });
    ref.read(membersProvider.notifier).refresh(
          page: 1,
          search: _searchQuery.isEmpty ? null : _searchQuery,
          status: status,
        );
  }

  void _showUploadSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _UploadMembersSheet(
        onComplete: () => ref.read(membersProvider.notifier).refresh(),
      ),
    );
  }

  void _onPageChange(int page) {
    ref.read(membersProvider.notifier).refresh(
          page: page,
          search: _searchQuery.isEmpty ? null : _searchQuery,
          status: _statusFilter,
        );
  }

  @override
  Widget build(BuildContext context) {
    return ShellLayout(
      title: 'Members',
      actions: [
        OutlinedButton.icon(
          onPressed: () => _showUploadSheet(context),
          icon: const Icon(Icons.upload_file_outlined, size: 18),
          label: const Text('Upload CSV/XLSX'),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () => context.push('/admin/members/create'),
          icon: const Icon(Icons.person_add_outlined, size: 18),
          label: const Text('Add Member'),
        ),
        const SizedBox(width: 16),
      ],
      child: Column(
        children: [
          _buildFilters(),
          Expanded(child: _buildList()),
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
            child: DebouncedSearchBar(
              hintText: 'Search members by name, phone, email...',
              onSearch: _onSearch,
            ),
          ),
          const SizedBox(width: 16),
          _StatusFilterChips(
            selected: _statusFilter,
            onChanged: _onFilterChange,
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final membersAsync = ref.watch(membersProvider);
    return membersAsync.when(
      loading: () => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 8,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: MemberCardSkeleton(),
        ),
      ),
      error: (error, _) => ErrorState(
        message: 'Failed to load members',
        details: error.toString(),
        onRetry: () => ref.read(membersProvider.notifier).refresh(),
      ),
      data: (membersList) {
        if (membersList.items.isEmpty) {
          return EmptyState(
            icon: Icons.people_outline,
            title: _searchQuery.isNotEmpty
                ? 'No members found for "$_searchQuery"'
                : 'No members yet',
            subtitle: _searchQuery.isEmpty
                ? 'Add a new member to get started'
                : null,
            actionLabel: _searchQuery.isEmpty ? 'Add Member' : null,
            onAction: _searchQuery.isEmpty
                ? () => context.push('/admin/members/create')
                : null,
          );
        }
        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: membersList.items.length,
                itemBuilder: (_, i) =>
                    _MemberCard(member: membersList.items[i]),
              ),
            ),
            PaginationFooter(
              currentPage: membersList.page,
              totalPages: membersList.totalPages,
              totalItems: membersList.total,
              pageSize: 20,
              onPageChanged: _onPageChange,
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Status filter chips
// ---------------------------------------------------------------------------

class _StatusFilterChips extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _StatusFilterChips({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FilterChip(
          label: 'All',
          isSelected: selected == null,
          onTap: () => onChanged(null),
        ),
        const SizedBox(width: 8),
        _FilterChip(
          label: 'Active',
          isSelected: selected == 'ACTIVE',
          color: AppColors.statusActive,
          onTap: () => onChanged(selected == 'ACTIVE' ? null : 'ACTIVE'),
        ),
        const SizedBox(width: 8),
        _FilterChip(
          label: 'Pending',
          isSelected: selected == 'PENDING',
          color: AppColors.statusPending,
          onTap: () =>
              onChanged(selected == 'PENDING' ? null : 'PENDING'),
        ),
        const SizedBox(width: 8),
        _FilterChip(
          label: 'Inactive',
          isSelected: selected == 'INACTIVE',
          color: AppColors.statusInactive,
          onTap: () =>
              onChanged(selected == 'INACTIVE' ? null : 'INACTIVE'),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : AppColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? AppColors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Member card
// ---------------------------------------------------------------------------

class _MemberCard extends StatelessWidget {
  final Member member;

  const _MemberCard({required this.member});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => context.push('/admin/members/${member.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _MemberAvatar(member: member),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            member.fullName,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        _StatusBadge(status: member.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (member.phone != null)
                      Row(
                        children: [
                          const Icon(Icons.phone_outlined,
                              size: 14,
                              color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            member.phone!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _RoleBadge(role: member.role),
                        if (member.isDuplicateFlagged) ...[
                          const SizedBox(width: 8),
                          _DuplicateBadge(),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  final Member member;

  const _MemberAvatar({required this.member});

  @override
  Widget build(BuildContext context) {
    if (member.photoUrl != null) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: member.photoUrl!,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          placeholder: (_, __) => _initials(context),
          errorWidget: (_, __, ___) => _initials(context),
        ),
      );
    }
    return _initials(context);
  }

  Widget _initials(BuildContext context) {
    final initials =
        '${member.firstName[0]}${member.lastName[0]}'.toUpperCase();
    return Container(
      width: 48,
      height: 48,
      decoration: const BoxDecoration(
        color: AppColors.primaryLight,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: AppColors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final MemberStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case MemberStatus.active:
        color = AppColors.statusActive;
        label = 'Active';
        break;
      case MemberStatus.pending:
        color = AppColors.statusPending;
        label = 'Pending';
        break;
      case MemberStatus.inactive:
        color = AppColors.statusInactive;
        label = 'Inactive';
        break;
      case MemberStatus.rejected:
        color = AppColors.statusRejected;
        label = 'Rejected';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;

  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        role.replaceAll('_', ' '),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.primary,
        ),
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
          Icon(Icons.warning_amber_rounded,
              size: 12, color: AppColors.error),
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

// ---------------------------------------------------------------------------
// Upload members sheet
// ---------------------------------------------------------------------------

class _UploadMembersSheet extends ConsumerStatefulWidget {
  final VoidCallback onComplete;

  const _UploadMembersSheet({required this.onComplete});

  @override
  ConsumerState<_UploadMembersSheet> createState() =>
      _UploadMembersSheetState();
}

class _UploadMembersSheetState extends ConsumerState<_UploadMembersSheet> {
  UploadState _state = UploadState.idle;
  ParsedImport? _parsed;
  List<Map<String, dynamic>> _validRows = [];
  int _invalidCount = 0;

  // import progress
  int _importedCount = 0;
  int _failedCount = 0;
  int _currentRow = 0;
  final List<String> _errors = [];

  void _pickFile() {
    pickAndParseFile(
      onSuccess: (result) {
        final valid = <Map<String, dynamic>>[];
        int invalid = 0;

        for (final row in result.rows) {
          final member = _rowToMemberJson(row);
          if (member != null) {
            valid.add(member);
          } else {
            invalid++;
          }
        }

        setState(() {
          _parsed = result;
          _validRows = valid;
          _invalidCount = invalid;
          _state = UploadState.reviewing;
        });
      },
      onError: (msg) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: AppColors.error),
          );
        }
      },
    );
  }

  Map<String, dynamic>? _rowToMemberJson(Map<String, String> row) {
    // Name
    final fullName = notEmpty(
      row['full_name'] ?? row['name'] ?? row['member_name'],
    );
    String first, last;
    if (fullName != null) {
      final idx = fullName.indexOf(' ');
      first = idx >= 0 ? fullName.substring(0, idx) : fullName;
      last = idx >= 0 ? fullName.substring(idx + 1) : '';
    } else {
      first = notEmpty(row['first_name']) ?? '';
      last = notEmpty(row['last_name']) ?? '';
    }
    if (first.isEmpty) return null;

    // Phone (required)
    final phone =
        notEmpty(row['phone'] ?? row['mobile'] ?? row['phone_number']);
    if (phone == null) return null;

    final email = notEmpty(row['email'] ?? row['email_address']);
    final gender =
        normaliseGender(row['gender'] ?? row['sex']);

    final addrRaw = notEmpty(row['address'] ?? row['home_address'] ?? row['landmark']);
    final stateRaw = notEmpty(row['state']);
    final addrParts = <String>[
      if (addrRaw != null) addrRaw,
      if (stateRaw != null) stateRaw,
    ];
    final address = addrParts.isEmpty ? null : addrParts.join(', ');

    final marital =
        normaliseMaritalStatus(row['marital_status'] ?? row['marital']);

    return {
      'full_name': '$first $last'.trim(),
      'phone': phone,
      if (email != null) 'email': email,
      if (gender != null) 'gender': gender,
      if (address != null) 'address': address,
      if (marital != null) 'marital_status': marital,
    };
  }

  Future<void> _startImport() async {
    setState(() {
      _state = UploadState.importing;
      _importedCount = 0;
      _failedCount = 0;
      _currentRow = 0;
      _errors.clear();
    });

    final dio = ref.read(dioProvider);
    for (int i = 0; i < _validRows.length; i++) {
      if (!mounted) return;
      setState(() => _currentRow = i + 1);
      try {
        await dio.post(ApiEndpoints.members, data: _validRows[i]);
        _importedCount++;
      } catch (e) {
        _failedCount++;
        final name = _validRows[i]['full_name'] ?? 'Row ${i + 1}';
        _errors.add('$name: ${_friendlyError(e.toString())}');
      }
    }

    widget.onComplete();
    if (mounted) setState(() => _state = UploadState.done);
  }

  String _friendlyError(String e) {
    if (e.contains('422') || e.contains('invalid')) return 'Invalid data';
    if (e.contains('409') || e.contains('already exists')) {
      return 'Already exists';
    }
    return 'Failed';
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Import Members',
                    style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _state == UploadState.importing
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildBody(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case UploadState.idle:
        return _buildIdle();
      case UploadState.reviewing:
        return _buildReviewing();
      case UploadState.importing:
        return _buildImporting();
      case UploadState.done:
        return _buildDone();
    }
  }

  Widget _buildIdle() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, style: BorderStyle.solid),
          ),
          child: Column(
            children: [
              const Icon(Icons.upload_file_outlined,
                  size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              const Text(
                'Upload a CSV or XLSX file',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Required columns: full_name, phone\n'
                'Optional: email, gender, address, state, marital_status',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: const Text('Choose File'),
            style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewing() {
    final p = _parsed!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.success.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.insert_drive_file_outlined,
                  color: AppColors.success, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(p.fileName,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SummaryRow(
          icon: Icons.check_circle_outline,
          color: AppColors.success,
          label: '${_validRows.length} rows ready to import',
        ),
        if (_invalidCount > 0) ...[
          const SizedBox(height: 8),
          _SummaryRow(
            icon: Icons.warning_amber_outlined,
            color: AppColors.warning,
            label:
                '$_invalidCount rows will be skipped (missing full_name or phone)',
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() {
                  _state = UploadState.idle;
                  _parsed = null;
                }),
                child: const Text('Choose Different File'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _validRows.isEmpty ? null : _startImport,
                child: Text('Import ${_validRows.length} Members'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildImporting() {
    final total = _validRows.length;
    final progress = total == 0 ? 0.0 : _currentRow / total;
    return Column(
      children: [
        const SizedBox(height: 16),
        const CircularProgressIndicator(),
        const SizedBox(height: 20),
        Text(
          'Importing $_currentRow of $total...',
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: AppColors.border,
          color: AppColors.primary,
        ),
        const SizedBox(height: 8),
        Text(
          '${(progress * 100).toInt()}%',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildDone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_importedCount > 0)
          _SummaryRow(
            icon: Icons.check_circle_outline,
            color: AppColors.success,
            label: '$_importedCount members imported successfully',
          ),
        if (_failedCount > 0) ...[
          const SizedBox(height: 8),
          _SummaryRow(
            icon: Icons.error_outline,
            color: AppColors.error,
            label: '$_failedCount rows failed',
          ),
        ],
        if (_errors.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            height: 120,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppColors.error.withOpacity(0.2)),
            ),
            child: ListView.builder(
              itemCount: _errors.length,
              itemBuilder: (_, i) => Text(
                '• ${_errors[i]}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.error),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _SummaryRow({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
