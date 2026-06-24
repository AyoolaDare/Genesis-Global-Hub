import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/theme/app_colors.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../providers/members_provider.dart';
import '../../providers/structure_provider.dart';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

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
  int? _birthMonth; // 1–12

  // Assignment
  String _assignmentType = 'NONE'; // NONE / DEPARTMENT / TEAM / GROUP
  String? _selectedAssignmentId;

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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // Combine landmark + state into address
      final landmark = _landmarkController.text.trim();
      final state = _stateController.text.trim();
      final address = [landmark, state]
          .where((s) => s.isNotEmpty)
          .join(', ');

      // Build date_of_birth as "1900-MM-DD" (year 1900 = year not collected)
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

      // Assign to dept/team/group if selected
      if (_assignmentType != 'NONE' &&
          _selectedAssignmentId != null &&
          memberId != null) {
        final dio = ref.read(dioProvider);
        await dio.post(
          ApiEndpoints.memberAssign(memberId),
          data: {
            'assignment_type': _assignmentType,
            'assignment_id': _selectedAssignmentId,
          },
        );
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

                  // ── Personal Information ──────────────────────────────────
                  _FormSection(
                    title: 'Personal Information',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _firstNameController,
                              decoration: const InputDecoration(
                                  labelText: 'First Name *'),
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
                                  labelText: 'Last Name *'),
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
                          if (v == null || v.isEmpty)
                            return 'Phone number is required';
                          final phone =
                              v.replaceAll(' ', '').replaceAll('-', '');
                          if (!RegExp(r'^(0\d{10}|234\d{10})$').hasMatch(phone)) {
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
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _gender,
                              decoration:
                                  const InputDecoration(labelText: 'Gender'),
                              items: ['Male', 'Female']
                                  .map((g) =>
                                      DropdownMenuItem(value: g, child: Text(g)))
                                  .toList(),
                              onChanged: (v) => setState(() => _gender = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Birthday: Month + Day only (no year)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Birthday (Month & Day)',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<int>(
                                  value: _birthMonth,
                                  decoration:
                                      const InputDecoration(labelText: 'Month'),
                                  items: List.generate(
                                    12,
                                    (i) => DropdownMenuItem(
                                      value: i + 1,
                                      child: Text(_months[i]),
                                    ),
                                  ),
                                  onChanged: (v) =>
                                      setState(() => _birthMonth = v),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  decoration:
                                      const InputDecoration(labelText: 'Day'),
                                  onChanged: (v) {
                                    final d = int.tryParse(v);
                                    setState(() => _birthDay = d);
                                  },
                                  validator: (v) {
                                    if (v == null || v.isEmpty) return null;
                                    final d = int.tryParse(v);
                                    if (d == null || d < 1 || d > 31) {
                                      return 'Enter 1–31';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Additional Information ────────────────────────────────
                  _FormSection(
                    title: 'Additional Information',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _landmarkController,
                              decoration:
                                  const InputDecoration(labelText: 'Landmark'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _stateController,
                              decoration:
                                  const InputDecoration(labelText: 'State'),
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
                              decoration:
                                  const InputDecoration(labelText: 'Occupation'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _maritalStatus,
                              decoration: const InputDecoration(
                                  labelText: 'Marital Status'),
                              items: ['Single', 'Married', 'Divorced', 'Widowed']
                                  .map((s) =>
                                      DropdownMenuItem(value: s, child: Text(s)))
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

                  // ── Church Assignment ─────────────────────────────────────
                  _FormSection(
                    title: 'Church Assignment (Optional)',
                    children: [
                      DropdownButtonFormField<String>(
                        value: _assignmentType,
                        decoration: const InputDecoration(
                            labelText: 'Assign to'),
                        items: const [
                          DropdownMenuItem(
                              value: 'NONE', child: Text('None')),
                          DropdownMenuItem(
                              value: 'DEPARTMENT', child: Text('Department')),
                          DropdownMenuItem(
                              value: 'TEAM', child: Text('Team')),
                          DropdownMenuItem(
                              value: 'GROUP', child: Text('Group')),
                        ],
                        onChanged: (v) => setState(() {
                          _assignmentType = v ?? 'NONE';
                          _selectedAssignmentId = null;
                        }),
                      ),
                      if (_assignmentType == 'DEPARTMENT') ...[
                        const SizedBox(height: 16),
                        depts.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (_, __) => const Text(
                            'Could not load departments',
                            style: TextStyle(color: AppColors.error),
                          ),
                          data: (list) => DropdownButtonFormField<String>(
                            value: _selectedAssignmentId,
                            decoration: const InputDecoration(
                                labelText: 'Select Department *'),
                            items: list
                                .map((d) => DropdownMenuItem(
                                    value: d.id, child: Text(d.name)))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedAssignmentId = v),
                            validator: (_) =>
                                _assignmentType != 'NONE' &&
                                        _selectedAssignmentId == null
                                    ? 'Please select a ${_assignmentType.toLowerCase()}'
                                    : null,
                          ),
                        ),
                      ],
                      if (_assignmentType == 'TEAM') ...[
                        const SizedBox(height: 16),
                        teams.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (_, __) => const Text(
                            'Could not load teams',
                            style: TextStyle(color: AppColors.error),
                          ),
                          data: (list) => DropdownButtonFormField<String>(
                            value: _selectedAssignmentId,
                            decoration: const InputDecoration(
                                labelText: 'Select Team *'),
                            items: list
                                .map((t) => DropdownMenuItem(
                                    value: t.id, child: Text(t.name)))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedAssignmentId = v),
                            validator: (_) =>
                                _assignmentType != 'NONE' &&
                                        _selectedAssignmentId == null
                                    ? 'Please select a team'
                                    : null,
                          ),
                        ),
                      ],
                      if (_assignmentType == 'GROUP') ...[
                        const SizedBox(height: 16),
                        groups.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (_, __) => const Text(
                            'Could not load groups',
                            style: TextStyle(color: AppColors.error),
                          ),
                          data: (list) => DropdownButtonFormField<String>(
                            value: _selectedAssignmentId,
                            decoration: const InputDecoration(
                                labelText: 'Select Group *'),
                            items: list
                                .map((g) => DropdownMenuItem(
                                    value: g.id, child: Text(g.name)))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedAssignmentId = v),
                            validator: (_) =>
                                _assignmentType != 'NONE' &&
                                        _selectedAssignmentId == null
                                    ? 'Please select a group'
                                    : null,
                          ),
                        ),
                      ],
                    ],
                  ),
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

// ---------------------------------------------------------------------------
// Shared form section widget
// ---------------------------------------------------------------------------

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
