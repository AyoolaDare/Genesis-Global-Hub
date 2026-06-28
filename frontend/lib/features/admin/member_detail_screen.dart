import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/error_state.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/user_model.dart';
import '../../core/theme/app_colors.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../providers/members_provider.dart';

class MemberDetailScreen extends ConsumerWidget {
  final String memberId;

  const MemberDetailScreen({super.key, required this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = ref.watch(memberDetailProvider(memberId));
    final role = ref.watch(currentRoleProvider);

    return ShellLayout(
      title: 'Member Detail',
      child: memberAsync.when(
        loading: () => const _DetailSkeleton(),
        error: (e, _) => ErrorState(
          message: 'Failed to load member',
          details: e.toString(),
          onRetry: () => ref.invalidate(memberDetailProvider(memberId)),
        ),
        data: (member) => _MemberDetailContent(member: member, role: role),
      ),
    );
  }
}

String _formatMemberBirthday(DateTime date) {
  if (date.year == 1900) return DateFormat('dd MMM').format(date);
  return DateFormat('dd MMM yyyy').format(date);
}

class _MemberDetailContent extends StatelessWidget {
  final Member member;
  final UserRole role;

  const _MemberDetailContent({required this.member, required this.role});

  List<Tab> _buildTabs() {
    final tabs = <Tab>[const Tab(text: 'Basic Info')];
    final canSeeSpiritualTab = {
      UserRole.superAdmin, UserRole.pastor, UserRole.departmentHead,
      UserRole.teamLeader, UserRole.groupLeader
    }.contains(role);
    final canSeeDeptTab = {
      UserRole.superAdmin, UserRole.pastor, UserRole.departmentHead
    }.contains(role);
    final canSeeFollowUpTab = {
      UserRole.superAdmin, UserRole.followUp
    }.contains(role);
    final canSeeMedicalTab = {
      UserRole.superAdmin, UserRole.medical
    }.contains(role);
    final canSeeAttendanceTab = {
      UserRole.superAdmin, UserRole.pastor, UserRole.departmentHead,
      UserRole.teamLeader, UserRole.groupLeader
    }.contains(role);

    if (canSeeSpiritualTab) tabs.add(const Tab(text: 'Spiritual'));
    if (canSeeDeptTab) tabs.add(const Tab(text: 'Departments'));
    if (canSeeFollowUpTab) tabs.add(const Tab(text: 'Follow-up'));
    if (canSeeMedicalTab) tabs.add(const Tab(text: 'Medical'));
    if (canSeeAttendanceTab) tabs.add(const Tab(text: 'Attendance'));
    return tabs;
  }

  List<Widget> _buildTabViews() {
    final views = <Widget>[_BasicInfoTab(member: member)];
    final canSeeSpiritualTab = {
      UserRole.superAdmin, UserRole.pastor, UserRole.departmentHead,
      UserRole.teamLeader, UserRole.groupLeader
    }.contains(role);
    final canSeeDeptTab = {
      UserRole.superAdmin, UserRole.pastor, UserRole.departmentHead
    }.contains(role);
    final canSeeFollowUpTab = {
      UserRole.superAdmin, UserRole.followUp
    }.contains(role);
    final canSeeMedicalTab = {
      UserRole.superAdmin, UserRole.medical
    }.contains(role);
    final canSeeAttendanceTab = {
      UserRole.superAdmin, UserRole.pastor, UserRole.departmentHead,
      UserRole.teamLeader, UserRole.groupLeader
    }.contains(role);

    if (canSeeSpiritualTab) views.add(_SpiritualTab(member: member));
    if (canSeeDeptTab) views.add(_DepartmentsTab(member: member));
    if (canSeeFollowUpTab) views.add(_FollowUpTab(memberId: member.id));
    if (canSeeMedicalTab) views.add(_MedicalTab(member: member));
    if (canSeeAttendanceTab) views.add(_AttendanceTab(memberId: member.id));
    return views;
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _buildTabs();
    final tabViews = _buildTabViews();

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          _MemberHeader(member: member, role: role),
          Container(
            color: AppColors.white,
            child: TabBar(tabs: tabs),
          ),
          Expanded(
            child: TabBarView(children: tabViews),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Member header
// ---------------------------------------------------------------------------

class _MemberHeader extends StatelessWidget {
  final Member member;
  final UserRole role;

  const _MemberHeader({required this.member, required this.role});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');
    return Container(
      padding: const EdgeInsets.all(24),
      color: AppColors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: member.photoUrl != null
                ? CachedNetworkImage(
                    imageUrl: member.photoUrl!,
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _initials(context),
                    errorWidget: (_, __, ___) => _initials(context),
                  )
                : _initials(context),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      member.fullName,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(width: 12),
                    _StatusBadge(status: member.status),
                  ],
                ),
                const SizedBox(height: 8),
                _infoRow(Icons.phone_outlined, member.phone ?? 'N/A'),
                const SizedBox(height: 4),
                _infoRow(Icons.email_outlined, member.email ?? 'N/A'),
                const SizedBox(height: 4),
                _infoRow(
                  Icons.calendar_today_outlined,
                  member.joinedAt != null
                      ? 'Joined ${dateFormat.format(member.joinedAt!)}'
                      : 'Join date unknown',
                ),
                const SizedBox(height: 12),
                // Action buttons for admin
                if (role == UserRole.superAdmin &&
                    member.status == MemberStatus.pending)
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () =>
                            _showApproveDialog(context),
                        icon: const Icon(Icons.check_circle_outline,
                            size: 16),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _showRejectDialog(context),
                        icon: const Icon(Icons.cancel_outlined,
                            size: 16),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side:
                              const BorderSide(color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                if (role == UserRole.superAdmin || role == UserRole.pastor) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => _EditMemberDialog(member: member),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit Member'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _initials(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: const BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      child: Center(
        child: Text(
          '${member.firstName[0]}${member.lastName[0]}'.toUpperCase(),
          style: const TextStyle(
            color: AppColors.white,
            fontWeight: FontWeight.w700,
            fontSize: 32,
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
      ],
    );
  }

  void _showApproveDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Approve Member'),
        content: Text('Approve ${member.fullName} as an active member?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(BuildContext context) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject Member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Reject ${member.fullName}\'s membership?'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason for rejection',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }
}

class _EditMemberDialog extends ConsumerStatefulWidget {
  final Member member;

  const _EditMemberDialog({required this.member});

  @override
  ConsumerState<_EditMemberDialog> createState() => _EditMemberDialogState();
}

class _EditMemberDialogState extends ConsumerState<_EditMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _photoUrlController;
  late final TextEditingController _landmarkController;
  late final TextEditingController _stateController;
  late String _membershipStatus;
  String? _gender;
  String? _maritalStatus;
  int? _birthMonth;
  int? _birthDay;
  DateTime? _salvationDate;
  late bool _waterBaptismStatus;
  late bool _holySpiritBaptismStatus;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: widget.member.firstName);
    _lastNameController = TextEditingController(text: widget.member.lastName);
    _phoneController = TextEditingController(text: widget.member.phone ?? '');
    _emailController = TextEditingController(text: widget.member.email ?? '');
    _photoUrlController =
        TextEditingController(text: widget.member.photoUrl ?? '');
    final addressParts = (widget.member.address ?? '').split(',');
    _landmarkController =
        TextEditingController(text: addressParts.isNotEmpty ? addressParts.first.trim() : '');
    _stateController = TextEditingController(
        text: addressParts.length > 1 ? addressParts.sublist(1).join(',').trim() : '');
    _membershipStatus = widget.member.status.value;
    _gender = _displayEnum(widget.member.gender);
    _maritalStatus = _displayEnum(widget.member.maritalStatus);
    _birthMonth = widget.member.dateOfBirth?.month;
    _birthDay = widget.member.dateOfBirth?.day;
    _salvationDate = widget.member.salvationDate;
    _waterBaptismStatus = widget.member.waterBaptismStatus;
    _holySpiritBaptismStatus = widget.member.holySpiritBaptismStatus;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _photoUrlController.dispose();
    _landmarkController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  String? _displayEnum(String? value) {
    if (value == null || value.isEmpty) return null;
    final lower = value.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final address = [
        _landmarkController.text.trim(),
        _stateController.text.trim(),
      ].where((part) => part.isNotEmpty).join(', ');
      final dateOfBirth = _birthMonth != null && _birthDay != null
          ? '1900-${_birthMonth!.toString().padLeft(2, '0')}-${_birthDay!.toString().padLeft(2, '0')}'
          : null;

      final dio = ref.read(dioProvider);
      await dio.put(
        ApiEndpoints.memberById(widget.member.id),
        data: {
          'full_name':
              '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim(),
          if (_phoneController.text.trim().isNotEmpty)
            'phone': _phoneController.text.trim(),
          if (_emailController.text.trim().isNotEmpty)
            'email': _emailController.text.trim(),
          if (_gender != null) 'gender': _gender!.toUpperCase(),
          if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
          if (address.isNotEmpty) 'address': address,
          if (_maritalStatus != null)
            'marital_status': _maritalStatus!.toUpperCase(),
          'membership_status': _membershipStatus,
          if (_salvationDate != null)
            'salvation_date': _salvationDate!.toIso8601String().split('T').first,
          'water_baptism_status': _waterBaptismStatus,
          'holy_spirit_baptism_status': _holySpiritBaptismStatus,
          if (_photoUrlController.text.trim().isNotEmpty)
            'photo_url': _photoUrlController.text.trim(),
        },
      );
      ref.invalidate(memberDetailProvider(widget.member.id));
      ref.invalidate(membersProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiException.from(e)?.message ?? 'Failed to update member.';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Member'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _firstNameController,
                        decoration: const InputDecoration(labelText: 'First Name *'),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lastNameController,
                        decoration: const InputDecoration(labelText: 'Last Name *'),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _photoUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'Photo URL'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _gender,
                        decoration: const InputDecoration(labelText: 'Gender'),
                        items: ['Male', 'Female']
                            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                            .toList(),
                        onChanged: (v) => setState(() => _gender = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _maritalStatus,
                        decoration: const InputDecoration(labelText: 'Marital Status'),
                        items: ['Single', 'Married', 'Divorced', 'Widowed']
                            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                            .toList(),
                        onChanged: (v) => setState(() => _maritalStatus = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _membershipStatus,
                  decoration:
                      const InputDecoration(labelText: 'Membership Status'),
                  items: const [
                    DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                    DropdownMenuItem(value: 'INACTIVE', child: Text('Inactive')),
                    DropdownMenuItem(value: 'PENDING', child: Text('Pending')),
                    DropdownMenuItem(value: 'REJECTED', child: Text('Rejected')),
                  ],
                  onChanged: (v) =>
                      setState(() => _membershipStatus = v ?? 'ACTIVE'),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Spiritual Details',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _birthMonth,
                        decoration: const InputDecoration(labelText: 'Birth Month'),
                        items: List.generate(
                          12,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text(DateFormat.MMMM().format(DateTime(1900, i + 1))),
                          ),
                        ),
                        onChanged: (v) => setState(() => _birthMonth = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _birthDay,
                        decoration: const InputDecoration(labelText: 'Birth Day'),
                        items: List.generate(
                          31,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text('${i + 1}'),
                          ),
                        ),
                        onChanged: (v) => setState(() => _birthDay = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _landmarkController,
                        decoration: const InputDecoration(labelText: 'Landmark'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _stateController,
                        decoration: const InputDecoration(labelText: 'State'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Salvation Date'),
                  subtitle: Text(
                    _salvationDate == null
                        ? 'Not set'
                        : DateFormat('dd MMM yyyy').format(_salvationDate!),
                  ),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _salvationDate ?? DateTime.now(),
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => _salvationDate = picked);
                    }
                  },
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _waterBaptismStatus,
                  onChanged: (v) =>
                      setState(() => _waterBaptismStatus = v ?? false),
                  title: const Text('Water Baptism Completed'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _holySpiritBaptismStatus,
                  onChanged: (v) =>
                      setState(() => _holySpiritBaptismStatus = v ?? false),
                  title: const Text('Holy Spirit Baptism Completed'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.white,
                  ),
                )
              : const Text('Save Changes'),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
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

// ---------------------------------------------------------------------------
// Tab views
// ---------------------------------------------------------------------------

class _BasicInfoTab extends StatelessWidget {
  final Member member;

  const _BasicInfoTab({required this.member});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionCard(
            title: 'Personal Information',
            children: [
              _InfoRow('First Name', member.firstName),
              _InfoRow('Last Name', member.lastName),
              _InfoRow('Phone', member.phone ?? 'N/A'),
              _InfoRow('Email', member.email ?? 'N/A'),
              _InfoRow('Gender', member.gender ?? 'N/A'),
              _InfoRow(
                'Date of Birth',
                member.dateOfBirth != null
                    ? _formatMemberBirthday(member.dateOfBirth!)
                    : 'N/A',
              ),
              _InfoRow('Marital Status', member.maritalStatus ?? 'N/A'),
              _InfoRow('Occupation', member.occupation ?? 'N/A'),
              _InfoRow('Landmark / State', member.address ?? 'N/A'),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Membership Details',
            children: [
              _InfoRow('Status', member.status.value),
              _InfoRow('Role', member.role),
              _InfoRow(
                'Joined Date',
                member.joinedAt != null
                    ? dateFormat.format(member.joinedAt!)
                    : 'N/A',
              ),
              if (member.submittedByName != null)
                _InfoRow('Submitted By', member.submittedByName!),
              if (member.submittedAt != null)
                _InfoRow('Submitted At',
                    dateFormat.format(member.submittedAt!)),
              if (member.notes != null && member.notes!.isNotEmpty)
                _InfoRow('Notes', member.notes!),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpiritualTab extends StatelessWidget {
  final Member member;

  const _SpiritualTab({required this.member});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _SectionCard(
        title: 'Spiritual Profile',
        children: [
          _InfoRow(
            'Salvation Date',
            member.salvationDate != null
                ? DateFormat('dd MMM yyyy').format(member.salvationDate!)
                : 'N/A',
          ),
          _InfoRow(
            'Water Baptism',
            member.waterBaptismStatus ? 'Completed' : 'Not completed',
          ),
          _InfoRow(
            'Holy Spirit Baptism',
            member.holySpiritBaptismStatus ? 'Completed' : 'Not completed',
          ),
        ],
      ),
    );
  }
}

class _DepartmentsTab extends StatelessWidget {
  final Member member;

  const _DepartmentsTab({required this.member});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _SectionCard(
        title: 'Department Memberships',
        children: [
          if (member.departmentIds.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Not assigned to any department',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            ...member.departmentIds.map(
              (id) => ListTile(
                leading: const Icon(Icons.business_outlined,
                    color: AppColors.primary),
                title: Text('Department $id'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
    );
  }
}

class _FollowUpTab extends StatelessWidget {
  final String memberId;

  const _FollowUpTab({required this.memberId});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: _SectionCard(
        title: 'Follow-up History',
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Follow-up task history will appear here.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicalTab extends StatelessWidget {
  final Member member;

  const _MedicalTab({required this.member});

  @override
  Widget build(BuildContext context) {
    // Only show whether they have a medical record — NO medical details
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _SectionCard(
        title: 'Medical Information',
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.info),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Medical record status: Linked. Full medical details are '
                    'accessible only to authorized medical staff.',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceTab extends StatelessWidget {
  final String memberId;

  const _AttendanceTab({required this.memberId});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: _SectionCard(
        title: 'Attendance Record',
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Attendance records will appear here.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SkeletonBox(height: 120, borderRadius: BorderRadius.all(Radius.circular(12))),
          const SizedBox(height: 16),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 5,
            itemBuilder: (_, __) => const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: SkeletonBox(height: 48),
            ),
          ),
        ],
      ),
    );
  }
}
