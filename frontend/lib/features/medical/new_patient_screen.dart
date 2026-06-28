import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../providers/medical_provider.dart';
import '../../providers/members_provider.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class NewPatientScreen extends ConsumerStatefulWidget {
  const NewPatientScreen({super.key});

  @override
  ConsumerState<NewPatientScreen> createState() =>
      _NewPatientScreenState();
}

class _NewPatientScreenState extends ConsumerState<NewPatientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _conditionsController = TextEditingController();
  final _memberSearchController = TextEditingController();

  String? _gender;
  DateTime? _dateOfBirth;
  bool _isChurchMember = false;
  MemberLookupResult? _selectedMember;
  bool _consentGiven = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _allergiesController.dispose();
    _conditionsController.dispose();
    _memberSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShellLayout(
      title: 'Register New Patient',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Personal info section
                  _buildSection(
                    context,
                    title: 'Personal Information',
                    icon: Icons.person_outline,
                    children: [
                      _buildNameRow(),
                      const SizedBox(height: 16),
                      _buildPhoneAndGender(),
                      const SizedBox(height: 16),
                      _buildDobPicker(context),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _addressController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Address',
                          border: OutlineInputBorder(),
                          prefixIcon:
                              Icon(Icons.location_on_outlined, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Medical info section
                  _buildSection(
                    context,
                    title: 'Medical Information',
                    icon: Icons.medical_services_outlined,
                    children: [
                      TextFormField(
                        controller: _allergiesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Known Allergies',
                          border: OutlineInputBorder(),
                          hintText: 'e.g. Penicillin, Peanuts... or "None known"',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _conditionsController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Chronic Conditions',
                          border: OutlineInputBorder(),
                          hintText: 'e.g. Hypertension, Diabetes... or "None"',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Church & consent section
                  _buildSection(
                    context,
                    title: 'Church & Consent',
                    icon: Icons.church_outlined,
                    children: [
                      CheckboxListTile(
                        value: _isChurchMember,
                        onChanged: (v) => setState(() {
                          _isChurchMember = v ?? false;
                          if (!_isChurchMember) _selectedMember = null;
                        }),
                        title: const Text('Patient is a church member'),
                        subtitle: const Text(
                            'Check if this patient attends Genesis Global Church'),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (_isChurchMember) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _memberSearchController,
                          decoration: const InputDecoration(
                            labelText: 'Search Church Member',
                            hintText: 'Type name or phone',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.search_outlined),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        _MemberLookupResults(
                          query: _memberSearchController.text,
                          selected: _selectedMember,
                          onSelected: _applyMember,
                        ),
                      ],
                      const Divider(),
                      CheckboxListTile(
                        value: _consentGiven,
                        onChanged: (v) =>
                            setState(() => _consentGiven = v ?? false),
                        title: const Text(
                          'Patient consent obtained *',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                            'The patient has given consent for their medical information to be recorded and processed.'),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        activeColor: AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Submit button
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
                          ? 'Registering...'
                          : 'Register Patient'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _isSubmitting ? null : _submit,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
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
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildNameRow() {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _firstNameController,
            decoration: const InputDecoration(
              labelText: 'First Name *',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'First name is required';
              }
              return null;
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: TextFormField(
            controller: _lastNameController,
            decoration: const InputDecoration(
              labelText: 'Last Name *',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Last name is required';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneAndGender() {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              border: OutlineInputBorder(),
              hintText: '+234...',
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _gender,
            decoration: const InputDecoration(
              labelText: 'Gender',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 15),
            ),
            items: const [
              DropdownMenuItem(value: 'MALE', child: Text('Male')),
              DropdownMenuItem(value: 'FEMALE', child: Text('Female')),
            ],
            onChanged: (v) => setState(() => _gender = v),
          ),
        ),
      ],
    );
  }

  Widget _buildDobPicker(BuildContext context) {
    return GestureDetector(
      onTap: () => _pickDob(context),
      child: AbsorbPointer(
        child: TextFormField(
          decoration: InputDecoration(
            labelText: 'Date of Birth',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
            suffixIcon: const Icon(Icons.arrow_drop_down),
            hintText: _dateOfBirth != null
                ? _formatDate(_dateOfBirth!)
                : 'Select date',
          ),
          controller: TextEditingController(
            text: _dateOfBirth != null ? _formatDate(_dateOfBirth!) : '',
          ),
        ),
      ),
    );
  }

  Future<void> _pickDob(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ??
          DateTime.now().subtract(const Duration(days: 365 * 30)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_consentGiven) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Patient consent is required before registration.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    if (_isChurchMember && _selectedMember == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select the church member to link.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final data = PatientCreate(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim().isNotEmpty
            ? _phoneController.text.trim()
            : null,
        address: _addressController.text.trim().isNotEmpty
            ? _addressController.text.trim()
            : null,
        gender: _gender,
        dateOfBirth: _dateOfBirth,
        allergies: _allergiesController.text.trim().isNotEmpty
            ? _allergiesController.text.trim()
            : null,
        chronicConditions: _conditionsController.text.trim().isNotEmpty
            ? _conditionsController.text.trim()
            : null,
        isChurchMember: _isChurchMember,
        memberId: _selectedMember?.id,
        consentGiven: _consentGiven,
      );
      await ref.read(medicalProvider.notifier).createPatient(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Patient registered successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        context.go('/medical/patients');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to register patient: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  void _applyMember(MemberLookupResult member) {
    final nameParts = member.fullName.split(' ');
    setState(() {
      _selectedMember = member;
      _firstNameController.text = nameParts.isNotEmpty ? nameParts.first : '';
      _lastNameController.text =
          nameParts.length > 1 ? nameParts.skip(1).join(' ') : '';
      _phoneController.text = member.phone ?? '';
      _addressController.text = member.address ?? '';
      _gender = member.gender;
      _dateOfBirth = member.dateOfBirth;
    });
  }
}

class _MemberLookupResults extends ConsumerWidget {
  final String query;
  final MemberLookupResult? selected;
  final ValueChanged<MemberLookupResult> onSelected;

  const _MemberLookupResults({
    required this.query,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().length < 2) {
      return const Text(
        'Enter at least 2 characters to search members.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      );
    }
    final results = ref.watch(memberLookupProvider(query));
    return results.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text(
        'Could not search members: $e',
        style: const TextStyle(color: AppColors.error, fontSize: 12),
      ),
      data: (members) => Column(
        children: members
            .take(5)
            .map(
              (m) => RadioListTile<String>(
                value: m.id,
                groupValue: selected?.id,
                onChanged: (_) => onSelected(m),
                title: Text(m.fullName),
                subtitle: Text(m.phone ?? 'No phone'),
                dense: true,
              ),
            )
            .toList(),
      ),
    );
  }
}
