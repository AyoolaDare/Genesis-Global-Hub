import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../providers/follow_up_provider.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class NewConvertScreen extends ConsumerStatefulWidget {
  const NewConvertScreen({super.key});

  @override
  ConsumerState<NewConvertScreen> createState() =>
      _NewConvertScreenState();
}

class _NewConvertScreenState extends ConsumerState<NewConvertScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _prayerRequestsController = TextEditingController();
  final _howHeardController = TextEditingController();
  DateTime _dateOfVisit = DateTime.now();
  bool _isSubmitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _prayerRequestsController.dispose();
    _howHeardController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return ShellLayout(
        title: 'New Convert',
        child: _buildSuccessState(context),
      );
    }

    return ShellLayout(
      title: 'Register New Convert',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: _buildForm(context),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.primary.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_add_outlined,
                    color: AppColors.primary, size: 28),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Register New Convert',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text(
                      'Fill in the details to register a new convert and create a follow-up task.',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
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
                Text('Personal Information',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _firstNameController,
                        decoration: const InputDecoration(
                          labelText: 'First Name *',
                          border: OutlineInputBorder(),
                          prefixIcon:
                              Icon(Icons.person_outline, size: 20),
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
                          prefixIcon:
                              Icon(Icons.person_outline, size: 20),
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
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone_outlined, size: 20),
                    hintText: '+234...',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _addressController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Home Address',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Church Information',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _howHeardController,
                  decoration: const InputDecoration(
                    labelText: 'How did they hear about the church?',
                    border: OutlineInputBorder(),
                    prefixIcon:
                        Icon(Icons.record_voice_over_outlined, size: 20),
                    hintText:
                        'e.g. Friend, Social media, Street evangelism...',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _prayerRequestsController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Prayer Requests',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.volunteer_activism_outlined,
                        size: 20),
                    hintText:
                        'Any specific prayer needs or topics...',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                // Date of visit
                GestureDetector(
                  onTap: () => _pickDate(context),
                  child: AbsorbPointer(
                    child: TextFormField(
                      decoration: InputDecoration(
                        labelText: 'Date of Visit *',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(
                            Icons.calendar_today_outlined,
                            size: 20),
                        suffixIcon:
                            const Icon(Icons.arrow_drop_down),
                        hintText: _formatDate(_dateOfVisit),
                      ),
                      controller: TextEditingController(
                          text: _formatDate(_dateOfVisit)),
                    ),
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
                    label: Text(
                        _isSubmitting ? 'Submitting...' : 'Register Convert'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _isSubmitting ? null : _submit,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessState(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline,
                    size: 56, color: AppColors.success),
              ),
              const SizedBox(height: 24),
              Text(
                'Convert Registered!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                '${_firstNameController.text} ${_lastNameController.text} has been registered and a follow-up task has been created.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Another'),
                    onPressed: () {
                      setState(() {
                        _submitted = false;
                        _firstNameController.clear();
                        _lastNameController.clear();
                        _phoneController.clear();
                        _addressController.clear();
                        _prayerRequestsController.clear();
                        _howHeardController.clear();
                        _dateOfVisit = DateTime.now();
                      });
                    },
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.list_alt_outlined, size: 18),
                    label: const Text('Go to Tasks'),
                    onPressed: () => context.go('/follow-up/tasks'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfVisit,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dateOfVisit = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final convert = NewConvert(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim().isNotEmpty
            ? _phoneController.text.trim()
            : null,
        address: _addressController.text.trim().isNotEmpty
            ? _addressController.text.trim()
            : null,
        notes: _buildNotes(),
        dateOfVisit: _dateOfVisit,
      );
      await ref.read(followUpProvider.notifier).createNewConvert(convert);
      if (mounted) setState(() => _submitted = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to register convert: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _buildNotes() {
    final parts = <String>[];
    if (_howHeardController.text.trim().isNotEmpty) {
      parts.add('How heard: ${_howHeardController.text.trim()}');
    }
    if (_prayerRequestsController.text.trim().isNotEmpty) {
      parts.add('Prayer requests: ${_prayerRequestsController.text.trim()}');
    }
    return parts.isEmpty ? null : parts.join('\n');
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
