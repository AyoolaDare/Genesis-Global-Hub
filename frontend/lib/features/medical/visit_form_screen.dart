import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../providers/medical_provider.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class VisitFormScreen extends ConsumerStatefulWidget {
  final String patientId;

  const VisitFormScreen({super.key, required this.patientId});

  @override
  ConsumerState<VisitFormScreen> createState() => _VisitFormScreenState();
}

class _VisitFormScreenState extends ConsumerState<VisitFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _complaintsController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _treatmentController = TextEditingController();
  final _medicationsController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _visitDate = DateTime.now();
  DateTime? _followUpDate;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _complaintsController.dispose();
    _diagnosisController.dispose();
    _treatmentController.dispose();
    _medicationsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final patientAsync =
        ref.watch(patientDetailProvider(widget.patientId));

    return ShellLayout(
      title: 'Record Visit',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Patient name header
                patientAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (patient) => Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.15)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline,
                            color: AppColors.primary, size: 22),
                        const SizedBox(width: 12),
                        Text(
                          'Recording visit for: ${patient.fullName}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Form(
                  key: _formKey,
                  child: Container(
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
                        Text('Visit Details',
                            style:
                                Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 20),
                        // Visit date
                        _buildDatePicker(
                          context,
                          label: 'Visit Date *',
                          date: _visitDate,
                          onPick: () => _pickDate(context, isFollowUp: false),
                        ),
                        const SizedBox(height: 16),
                        // Complaints
                        TextFormField(
                          controller: _complaintsController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Presenting Complaints *',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                            hintText:
                                'Describe the patient\'s chief complaints...',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Complaints are required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        // Diagnosis
                        TextFormField(
                          controller: _diagnosisController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Diagnosis *',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                            hintText: 'Clinical diagnosis...',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Diagnosis is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        // Treatment
                        TextFormField(
                          controller: _treatmentController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Treatment / Management *',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                            hintText:
                                'Describe the treatment plan...',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Treatment is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        // Medications
                        TextFormField(
                          controller: _medicationsController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Medications Prescribed',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                            hintText:
                                'List medications with dosage...',
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Follow-up date
                        Row(
                          children: [
                            Expanded(
                              child: _buildDatePicker(
                                context,
                                label: 'Follow-up Date',
                                date: _followUpDate,
                                hintText: 'Optional',
                                onPick: () =>
                                    _pickDate(context, isFollowUp: true),
                              ),
                            ),
                            if (_followUpDate != null) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.clear,
                                    color: AppColors.error),
                                tooltip: 'Remove follow-up date',
                                onPressed: () =>
                                    setState(() => _followUpDate = null),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Notes
                        TextFormField(
                          controller: _notesController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Additional Notes',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => context
                                    .go('/medical/patients/${widget.patientId}'),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                icon: _isSubmitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.white,
                                        ),
                                      )
                                    : const Icon(Icons.save_outlined,
                                        size: 20),
                                label: Text(_isSubmitting
                                    ? 'Saving...'
                                    : 'Save Visit Record'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                ),
                                onPressed:
                                    _isSubmitting ? null : _submit,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDatePicker(
    BuildContext context, {
    required String label,
    required DateTime? date,
    String? hintText,
    required VoidCallback onPick,
  }) {
    return GestureDetector(
      onTap: onPick,
      child: AbsorbPointer(
        child: TextFormField(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            prefixIcon:
                const Icon(Icons.calendar_today_outlined, size: 20),
            suffixIcon: const Icon(Icons.arrow_drop_down),
            hintText: date != null ? _formatDate(date) : hintText,
          ),
          controller: TextEditingController(
            text: date != null ? _formatDate(date) : '',
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context,
      {required bool isFollowUp}) async {
    final initial = isFollowUp
        ? (_followUpDate ?? DateTime.now().add(const Duration(days: 7)))
        : _visitDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: isFollowUp ? DateTime.now() : DateTime(2020),
      lastDate: isFollowUp
          ? DateTime.now().add(const Duration(days: 365))
          : DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isFollowUp) {
          _followUpDate = picked;
        } else {
          _visitDate = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(
        ApiEndpoints.patientVisits(widget.patientId),
        data: {
          'patient_id': widget.patientId,
          'visit_date': _visitDate.toIso8601String(),
          'complaints': _complaintsController.text.trim(),
          'diagnosis': _diagnosisController.text.trim(),
          'treatment': _treatmentController.text.trim(),
          if (_medicationsController.text.trim().isNotEmpty)
            'medications': _medicationsController.text.trim(),
          if (_followUpDate != null)
            'follow_up_date': _followUpDate!.toIso8601String(),
          if (_notesController.text.trim().isNotEmpty)
            'notes': _notesController.text.trim(),
        },
      );
      // Invalidate patient detail and visits to refresh
      ref.invalidate(patientDetailProvider(widget.patientId));
      ref.invalidate(patientVisitsProvider(widget.patientId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Visit recorded successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        context.go('/medical/patients/${widget.patientId}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save visit: $e'),
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
}
