import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/error_state.dart';
import '../../providers/medical_provider.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class PatientDetailScreen extends ConsumerWidget {
  final String patientId;

  const PatientDetailScreen({super.key, required this.patientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientAsync = ref.watch(patientDetailProvider(patientId));
    final visitsAsync = ref.watch(patientVisitsProvider(patientId));

    return ShellLayout(
      title: 'Patient Detail',
      actions: [
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Visit'),
          onPressed: () => context.go('/medical/patients/$patientId/visit'),
        ),
        const SizedBox(width: 8),
      ],
      child: patientAsync.when(
        loading: () => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SkeletonBox(height: 220),
              const SizedBox(height: 16),
              const SkeletonBox(height: 300),
            ],
          ),
        ),
        error: (e, _) => ErrorState(
          message: e.toString().contains('403')
              ? 'Access Denied'
              : 'Failed to load patient',
          onRetry: () =>
              ref.invalidate(patientDetailProvider(patientId)),
        ),
        data: (patient) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PatientInfoCard(patient: patient),
              const SizedBox(height: 16),
              _VisitHistorySection(
                patientId: patientId,
                visitsAsync: visitsAsync,
                onAddVisit: () =>
                    context.go('/medical/patients/$patientId/visit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Patient info card
// ---------------------------------------------------------------------------

class _PatientInfoCard extends StatelessWidget {
  final Patient patient;

  const _PatientInfoCard({required this.patient});

  @override
  Widget build(BuildContext context) {
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
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_outline,
                    size: 30, color: AppColors.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.fullName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    // Church member is TEXT ONLY — no link
                    Text(
                      'Church Member: ${patient.isChurchMember ? "Yes" : "No"}',
                      style: TextStyle(
                        fontSize: 13,
                        color: patient.isChurchMember
                            ? AppColors.success
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          _buildInfoGrid(context, patient),
        ],
      ),
    );
  }

  Widget _buildInfoGrid(BuildContext context, Patient patient) {
    final rows = <_InfoPair>[
      if (patient.phone != null)
        _InfoPair('Phone', patient.phone!),
      if (patient.gender != null)
        _InfoPair('Gender', patient.gender!),
      if (patient.dateOfBirth != null)
        _InfoPair(
            'Date of Birth',
            '${patient.dateOfBirth!.day}/${patient.dateOfBirth!.month}/${patient.dateOfBirth!.year}'),
      if (patient.bloodGroup != null)
        _InfoPair('Blood Group', patient.bloodGroup!),
      if (patient.address != null)
        _InfoPair('Address', patient.address!),
      if (patient.allergies != null)
        _InfoPair('Allergies', patient.allergies!),
    ];

    return Wrap(
      spacing: 24,
      runSpacing: 12,
      children: rows.map((pair) => _InfoItem(pair: pair)).toList(),
    );
  }
}

class _InfoPair {
  final String label;
  final String value;

  const _InfoPair(this.label, this.value);
}

class _InfoItem extends StatelessWidget {
  final _InfoPair pair;

  const _InfoItem({required this.pair});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pair.label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            pair.value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Visit history section
// ---------------------------------------------------------------------------

class _VisitHistorySection extends StatelessWidget {
  final String patientId;
  final AsyncValue<List<PatientVisit>> visitsAsync;
  final VoidCallback onAddVisit;

  const _VisitHistorySection({
    required this.patientId,
    required this.visitsAsync,
    required this.onAddVisit,
  });

  @override
  Widget build(BuildContext context) {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Visit History',
                  style: Theme.of(context).textTheme.titleMedium),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Visit'),
                onPressed: onAddVisit,
              ),
            ],
          ),
          const SizedBox(height: 16),
          visitsAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator()),
            error: (e, _) => const Text(
              'Failed to load visits',
              style: TextStyle(color: AppColors.error),
            ),
            data: (visits) => visits.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No visits recorded yet',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  )
                : Column(
                    children: visits
                        .reversed
                        .map((v) => _VisitCard(visit: v))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Visit card
// ---------------------------------------------------------------------------

class _VisitCard extends StatelessWidget {
  final PatientVisit visit;

  const _VisitCard({required this.visit});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: const Border(
          left: BorderSide(color: AppColors.primary, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDate(visit.visitDate),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              if (visit.followUpDate != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Follow-up: ${_formatDate(visit.followUpDate!)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _VisitField(label: 'Complaints', value: visit.complaints),
          _VisitField(label: 'Diagnosis', value: visit.diagnosis),
          _VisitField(label: 'Treatment', value: visit.treatment),
          if (visit.medications != null)
            _VisitField(label: 'Medications', value: visit.medications!),
          if (visit.notes != null)
            _VisitField(label: 'Notes', value: visit.notes!),
          if (visit.attendedByName != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Attended by: ${visit.attendedByName}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _VisitField extends StatelessWidget {
  final String label;
  final String value;

  const _VisitField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Text(': ',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
