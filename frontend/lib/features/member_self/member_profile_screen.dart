import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/error_state.dart';

// ---------------------------------------------------------------------------
// Model & provider
// ---------------------------------------------------------------------------

class MyProfile {
  final String id;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final String? address;
  final String? gender;
  final DateTime? dateOfBirth;
  final DateTime? salvationDate;
  final String status;
  final String? photoUrl;

  const MyProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.email,
    this.phone,
    this.address,
    this.gender,
    this.dateOfBirth,
    this.salvationDate,
    required this.status,
    this.photoUrl,
  });

  String get fullName => '$firstName $lastName';

  factory MyProfile.fromJson(Map<String, dynamic> json) {
    return MyProfile(
      id: json['id'] ?? '',
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      email: json['email'],
      phone: json['phone'],
      address: json['address'],
      gender: json['gender'],
      dateOfBirth: json['date_of_birth'] != null
          ? DateTime.tryParse(json['date_of_birth'])
          : null,
      salvationDate: json['salvation_date'] != null
          ? DateTime.tryParse(json['salvation_date'])
          : null,
      status: json['status'] ?? 'ACTIVE',
      photoUrl: json['photo_url'],
    );
  }
}

final myProfileProvider = FutureProvider<MyProfile>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.myProfile);
  return MyProfile.fromJson(response.data['data']);
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class MemberProfileScreen extends ConsumerStatefulWidget {
  const MemberProfileScreen({super.key});

  @override
  ConsumerState<MemberProfileScreen> createState() =>
      _MemberProfileScreenState();
}

class _MemberProfileScreenState
    extends ConsumerState<MemberProfileScreen> {
  bool _isEditing = false;
  bool _isSaving = false;

  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);

    return ShellLayout(
      title: 'My Profile',
      actions: [
        if (!_isEditing)
          TextButton.icon(
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
            onPressed: () {
              profileAsync.whenData((profile) {
                _phoneController.text = profile.phone ?? '';
                _emailController.text = profile.email ?? '';
                _addressController.text = profile.address ?? '';
                setState(() => _isEditing = true);
              });
            },
          ),
        if (_isEditing) ...[
          TextButton(
            onPressed: _isSaving
                ? null
                : () => setState(() => _isEditing = false),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.white),
                  )
                : const Icon(Icons.save_outlined, size: 16),
            label: Text(_isSaving ? 'Saving...' : 'Save'),
            onPressed: _isSaving ? null : _save,
          ),
          const SizedBox(width: 8),
        ],
      ],
      child: profileAsync.when(
        loading: () => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: const [
              SkeletonBox(height: 200),
              SizedBox(height: 16),
              SkeletonBox(height: 300),
            ],
          ),
        ),
        error: (e, _) => ErrorState(
          message: e.toString().contains('403')
              ? 'Access Denied'
              : 'Failed to load profile',
          onRetry: () => ref.invalidate(myProfileProvider),
        ),
        data: (profile) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProfileHeader(profile: profile),
                  const SizedBox(height: 16),
                  _isEditing
                      ? _EditableFields(
                          profile: profile,
                          phoneController: _phoneController,
                          emailController: _emailController,
                          addressController: _addressController,
                        )
                      : _ReadOnlyFields(profile: profile),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.patch(ApiEndpoints.myProfile, data: {
        if (_phoneController.text.trim().isNotEmpty)
          'phone': _phoneController.text.trim(),
        if (_emailController.text.trim().isNotEmpty)
          'email': _emailController.text.trim(),
        if (_addressController.text.trim().isNotEmpty)
          'address': _addressController.text.trim(),
      });
      ref.invalidate(myProfileProvider);
      if (mounted) {
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Profile header
// ---------------------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  final MyProfile profile;

  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    final initials = profile.fullName
        .split(' ')
        .take(2)
        .map((s) => s.isNotEmpty ? s[0].toUpperCase() : '')
        .join();

    return Container(
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
      child: Row(
        children: [
          profile.photoUrl != null
              ? CircleAvatar(
                  radius: 36,
                  backgroundImage: NetworkImage(profile.photoUrl!),
                )
              : Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.fullName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                // Status — read-only display
                _StatusChip(status: profile.status),
                if (profile.salvationDate != null) ...[
                  const SizedBox(height: 6),
                  // Salvation date — read-only, not editable by member
                  Row(
                    children: [
                      const Icon(Icons.favorite_outline,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        'Saved: ${profile.salvationDate!.day}/${profile.salvationDate!.month}/${profile.salvationDate!.year}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  Color get _color {
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        return AppColors.success;
      case 'INACTIVE':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Read-only fields section
// ---------------------------------------------------------------------------

class _ReadOnlyFields extends StatelessWidget {
  final MyProfile profile;

  const _ReadOnlyFields({required this.profile});

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
              Text('Contact Information',
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              const Text(
                'Phone, email and address are editable',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 20,
            children: [
              // Editable fields shown as read-only
              if (profile.phone != null)
                _Field(
                    label: 'Phone',
                    value: profile.phone!,
                    editable: true),
              if (profile.email != null)
                _Field(
                    label: 'Email',
                    value: profile.email!,
                    editable: true),
              if (profile.address != null)
                _Field(
                    label: 'Address',
                    value: profile.address!,
                    editable: true),
              // Non-editable fields
              if (profile.gender != null)
                _Field(label: 'Gender', value: profile.gender!),
              if (profile.dateOfBirth != null)
                _Field(
                  label: 'Date of Birth',
                  value:
                      '${profile.dateOfBirth!.day}/${profile.dateOfBirth!.month}/${profile.dateOfBirth!.year}',
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.info.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: const [
                Icon(Icons.info_outline,
                    size: 16, color: AppColors.info),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Name, salvation date and membership status can only be updated by an administrator.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
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

class _Field extends StatelessWidget {
  final String label;
  final String value;
  final bool editable;

  const _Field(
      {required this.label,
      required this.value,
      this.editable = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              if (editable) ...[
                const SizedBox(width: 4),
                const Icon(Icons.edit_outlined,
                    size: 10, color: AppColors.info),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
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
// Editable fields section
// ---------------------------------------------------------------------------

class _EditableFields extends StatelessWidget {
  final MyProfile profile;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final TextEditingController addressController;

  const _EditableFields({
    required this.profile,
    required this.phoneController,
    required this.emailController,
    required this.addressController,
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
          Text('Edit Contact Details',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          const Text(
            'You can update your phone, email and address.',
            style:
                TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              border: OutlineInputBorder(),
              prefixIcon:
                  Icon(Icons.phone_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email Address',
              border: OutlineInputBorder(),
              prefixIcon:
                  Icon(Icons.email_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: addressController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Home Address',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
              prefixIcon:
                  Icon(Icons.location_on_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 20),
          // Non-editable read-only section
          const Divider(),
          const SizedBox(height: 12),
          const Text(
            'The following fields cannot be edited by members:',
            style:
                TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _ReadOnlyChip(
                  label: 'Name',
                  value: profile.fullName),
              _ReadOnlyChip(
                  label: 'Status',
                  value: profile.status),
              if (profile.salvationDate != null)
                _ReadOnlyChip(
                  label: 'Salvation Date',
                  value:
                      '${profile.salvationDate!.day}/${profile.salvationDate!.month}/${profile.salvationDate!.year}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyChip extends StatelessWidget {
  final String label;
  final String value;

  const _ReadOnlyChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline,
              size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
