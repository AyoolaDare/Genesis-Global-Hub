import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/theme/app_colors.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../providers/members_provider.dart';
import '../../providers/structure_provider.dart';

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _memberTypeNew = 'NEW';
const _memberTypeExisting = 'EXISTING';

class MemberCreateScreen extends ConsumerStatefulWidget {
  const MemberCreateScreen({super.key});

  @override
  ConsumerState<MemberCreateScreen> createState() => _MemberCreateScreenState();
}

class _MemberCreateScreenState extends ConsumerState<MemberCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _stateController = TextEditingController();
  final _occupationController = TextEditingController();
  final _notesController = TextEditingController();

  String? _gender;
  String? _maritalStatus;
  int? _birthDay;
  int? _birthMonth;
  String _memberType = _memberTypeNew;
  String? _selectedDepartmentId;
  String? _selectedTeamId;
  String? _selectedGroupId;

  int get _maxBirthDay {
    switch (_birthMonth) {
      case 2:
        return 29;
      case 4:
      case 6:
      case 9:
      case 11:
        return 30;
      default:
        return 31;
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _landmarkController.dispose();
    _stateController.dispose();
    _occupationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_memberType == _memberTypeExisting &&
        _selectedDepartmentId == null &&
        _selectedTeamId == null &&
        _selectedGroupId == null) {
      setState(() {
        _errorMessage =
            'Please choose at least one department, team, or group for an existing member.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final landmark = _landmarkController.text.trim();
      final state = _stateController.text.trim();
      final address = [landmark, state].where((s) => s.isNotEmpty).join(', ');

      String? dateOfBirth;
      if (_birthMonth != null && _birthDay != null) {
        dateOfBirth =
            '1900-${_birthMonth!.toString().padLeft(2, '0')}-${_birthDay!.toString().padLeft(2, '0')}';
      }

      final data = MemberCreate(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        address: address.isEmpty ? null : address,
        gender: _gender,
        dateOfBirth: dateOfBirth != null ? DateTime.parse(dateOfBirth) : null,
        occupation: _occupationController.text.trim().isEmpty
            ? null
            : _occupationController.text.trim(),
        maritalStatus: _maritalStatus,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      final memberId =
          await ref.read(membersProvider.notifier).createMemberAndGetId(data);

      if (_memberType == _memberTypeExisting && memberId != null) {
        final dio = ref.read(dioProvider);
        final assignments = <Map<String, String>>[
          if (_selectedDepartmentId != null)
            {
              'assignment_type': 'DEPARTMENT',
              'assignment_id': _selectedDepartmentId!,
            },
          if (_selectedTeamId != null)
            {
              'assignment_type': 'TEAM',
              'assignment_id': _selectedTeamId!,
            },
          if (_selectedGroupId != null)
            {
              'assignment_type': 'GROUP',
              'assignment_id': _selectedGroupId!,
            },
        ];

        for (final assignment in assignments) {
          await dio.post(ApiEndpoints.memberAssign(memberId), data: assignment);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Member created successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to create member: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final depts = ref.watch(departmentsProvider);
    final teams = ref.watch(teamsProvider);
    final groups = ref.watch(groupsProvider);

    return ShellLayout(
      title: 'Add New Member',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_errorMessage != null) ...[
                    _ErrorBanner(message: _errorMessage!),
                    const SizedBox(height: 16),
                  ],
                  _FormSection(
                    title: 'Personal Information',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _firstNameController,
                              decoration: const InputDecoration(
                                labelText: 'First Name *',
                              ),
                              validator: (v) => v == null || v.isEmpty
                                  ? 'First name is required'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _lastNameController,
                              decoration: const InputDecoration(
                                labelText: 'Last Name *',
                              ),
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Last name is required'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number *',
                          hintText: '08012345678',
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Phone number is required';
                          }
                          final phone =
                              v.replaceAll(' ', '').replaceAll('-', '');
                          if (!RegExp(r'^(0\d{10}|234\d{10})$')
                              .hasMatch(phone)) {
                            return 'Enter a valid Nigerian phone number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (v) {
                          if (v != null &&
                              v.isNotEmpty &&
                              !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                  .hasMatch(v)) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _gender,
                        decoration: const InputDecoration(labelText: 'Gender'),
                        items: ['Male', 'Female']
                            .map(
                              (g) => DropdownMenuItem(
                                value: g,
                                child: Text(g),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _gender = v),
                      ),
                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Birthday (Month & Day)',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<int>(
                                  value: _birthMonth,
                                  decoration: const InputDecoration(
                                    labelText: 'Month',
                                  ),
                                  items: List.generate(
                                    12,
                                    (i) => DropdownMenuItem(
                                      value: i + 1,
                                      child: Text(_months[i]),
                                    ),
                                  ),
                                  onChanged: (v) => setState(() {
                                    _birthMonth = v;
                                    if (_birthDay != null &&
                                        _birthDay! > _maxBirthDay) {
                                      _birthDay = null;
                                    }
                                  }),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<int>(
                                  value: _birthDay,
                                  decoration: const InputDecoration(
                                    labelText: 'Day',
                                  ),
                                  items: List.generate(
                                    _maxBirthDay,
                                    (i) => DropdownMenuItem(
                                      value: i + 1,
                                      child: Text('${i + 1}'),
                                    ),
                                  ),
                                  onChanged: (v) =>
                                      setState(() => _birthDay = v),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _FormSection(
                    title: 'Additional Information',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _landmarkController,
                              decoration: const InputDecoration(
                                labelText: 'Landmark',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _stateController,
                              decoration: const InputDecoration(
                                labelText: 'State',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _occupationController,
                              decoration: const InputDecoration(
                                labelText: 'Occupation',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _maritalStatus,
                              decoration: const InputDecoration(
                                labelText: 'Marital Status',
                              ),
                              items: [
                                'Single',
                                'Married',
                                'Divorced',
                                'Widowed',
                              ]
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _maritalStatus = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _notesController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          hintText: 'Any additional notes about this member...',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _FormSection(
                    title: 'Member Type',
                    children: [
                      DropdownButtonFormField<String>(
                        value: _memberType,
                        decoration: const InputDecoration(
                          labelText: 'Member Type *',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: _memberTypeNew,
                            child: Text('New member'),
                          ),
                          DropdownMenuItem(
                            value: _memberTypeExisting,
                            child: Text('Existing member'),
                          ),
                        ],
                        onChanged: (v) => setState(() {
                          _memberType = v ?? _memberTypeNew;
                          if (_memberType == _memberTypeNew) {
                            _selectedDepartmentId = null;
                            _selectedTeamId = null;
                            _selectedGroupId = null;
                          }
                        }),
                      ),
                    ],
                  ),
                  if (_memberType == _memberTypeExisting) ...[
                    const SizedBox(height: 16),
                    _FormSection(
                      title: 'Existing Member Assignments',
                      children: [
                        depts.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (_, __) => const Text(
                            'Could not load departments',
                            style: TextStyle(color: AppColors.error),
                          ),
                          data: (list) => DropdownButtonFormField<String>(
                            value: _selectedDepartmentId,
                            decoration: const InputDecoration(
                              labelText: 'Department',
                            ),
                            items: list
                                .map(
                                  (d) => DropdownMenuItem(
                                    value: d.id,
                                    child: Text(d.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedDepartmentId = v),
                          ),
                        ),
                        const SizedBox(height: 16),
                        teams.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (_, __) => const Text(
                            'Could not load teams',
                            style: TextStyle(color: AppColors.error),
                          ),
                          data: (list) => DropdownButtonFormField<String>(
                            value: _selectedTeamId,
                            decoration: const InputDecoration(
                              labelText: 'Team',
                            ),
                            items: list
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t.id,
                                    child: Text(t.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedTeamId = v),
                          ),
                        ),
                        const SizedBox(height: 16),
                        groups.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (_, __) => const Text(
                            'Could not load groups',
                            style: TextStyle(color: AppColors.error),
                          ),
                          data: (list) => DropdownButtonFormField<String>(
                            value: _selectedGroupId,
                            decoration: const InputDecoration(
                              labelText: 'Group',
                            ),
                            items: list
                                .map(
                                  (g) => DropdownMenuItem(
                                    value: g.id,
                                    child: Text(g.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedGroupId = v),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => context.pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleSubmit,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: AppColors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Create Member'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _FormSection({required this.title, required this.children});

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
          ...children,
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.error, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
