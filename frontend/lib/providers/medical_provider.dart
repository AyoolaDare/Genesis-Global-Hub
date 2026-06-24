import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/api_client.dart';
import '../core/api/api_endpoints.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class Patient {
  final String id;
  final String firstName;
  final String lastName;
  final String? phone;
  final String? address;
  final String? gender;
  final DateTime? dateOfBirth;
  final String? bloodGroup;
  final String? allergies;
  final bool isChurchMember;
  final String? memberId;
  final DateTime createdAt;
  final DateTime? lastVisit;

  const Patient({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.phone,
    this.address,
    this.gender,
    this.dateOfBirth,
    this.bloodGroup,
    this.allergies,
    required this.isChurchMember,
    this.memberId,
    required this.createdAt,
    this.lastVisit,
  });

  String get fullName => '$firstName $lastName';

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      id: json['id'] ?? '',
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      phone: json['phone'],
      address: json['address'],
      gender: json['gender'],
      dateOfBirth: json['date_of_birth'] != null
          ? DateTime.tryParse(json['date_of_birth'])
          : null,
      bloodGroup: json['blood_group'],
      allergies: json['allergies'],
      isChurchMember: json['is_church_member'] ?? false,
      memberId: json['member_id'],
      createdAt: DateTime.parse(
          json['created_at'] ?? DateTime.now().toIso8601String()),
      lastVisit: json['last_visit'] != null
          ? DateTime.tryParse(json['last_visit'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'address': address,
        'gender': gender,
        'date_of_birth': dateOfBirth?.toIso8601String(),
        'blood_group': bloodGroup,
        'allergies': allergies,
        'is_church_member': isChurchMember,
        'member_id': memberId,
      };
}

class PatientVisit {
  final String id;
  final String patientId;
  final DateTime visitDate;
  final String complaints;
  final String diagnosis;
  final String treatment;
  final String? medications;
  final DateTime? followUpDate;
  final String? notes;
  final String attendedById;
  final String? attendedByName;

  const PatientVisit({
    required this.id,
    required this.patientId,
    required this.visitDate,
    required this.complaints,
    required this.diagnosis,
    required this.treatment,
    this.medications,
    this.followUpDate,
    this.notes,
    required this.attendedById,
    this.attendedByName,
  });

  factory PatientVisit.fromJson(Map<String, dynamic> json) {
    return PatientVisit(
      id: json['id'] ?? '',
      patientId: json['patient_id'] ?? '',
      visitDate: DateTime.parse(
          json['visit_date'] ?? DateTime.now().toIso8601String()),
      complaints: json['complaints'] ?? '',
      diagnosis: json['diagnosis'] ?? '',
      treatment: json['treatment'] ?? '',
      medications: json['medications'],
      followUpDate: json['follow_up_date'] != null
          ? DateTime.tryParse(json['follow_up_date'])
          : null,
      notes: json['notes'],
      attendedById: json['attended_by_id'] ?? '',
      attendedByName: json['attended_by_name'],
    );
  }
}

class PatientCreate {
  final String firstName;
  final String lastName;
  final String? phone;
  final String? address;
  final String? gender;
  final DateTime? dateOfBirth;
  final String? bloodGroup;
  final String? allergies;
  final bool isChurchMember;
  final String? memberId;

  const PatientCreate({
    required this.firstName,
    required this.lastName,
    this.phone,
    this.address,
    this.gender,
    this.dateOfBirth,
    this.bloodGroup,
    this.allergies,
    this.isChurchMember = false,
    this.memberId,
  });

  Map<String, dynamic> toJson() => {
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'address': address,
        'gender': gender,
        'date_of_birth': dateOfBirth?.toIso8601String(),
        'blood_group': bloodGroup,
        'allergies': allergies,
        'is_church_member': isChurchMember,
        'member_id': memberId,
      };
}

class VisitCreate {
  final String patientId;
  final DateTime visitDate;
  final String complaints;
  final String diagnosis;
  final String treatment;
  final String? medications;
  final DateTime? followUpDate;
  final String? notes;

  const VisitCreate({
    required this.patientId,
    required this.visitDate,
    required this.complaints,
    required this.diagnosis,
    required this.treatment,
    this.medications,
    this.followUpDate,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'patient_id': patientId,
        'visit_date': visitDate.toIso8601String(),
        'complaints': complaints,
        'diagnosis': diagnosis,
        'treatment': treatment,
        'medications': medications,
        'follow_up_date': followUpDate?.toIso8601String(),
        'notes': notes,
      };
}

class PatientsList {
  final List<Patient> items;
  final int total;
  final int page;
  final int totalPages;

  const PatientsList({
    required this.items,
    required this.total,
    required this.page,
    required this.totalPages,
  });

  factory PatientsList.empty() => const PatientsList(
        items: [],
        total: 0,
        page: 1,
        totalPages: 0,
      );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class MedicalNotifier extends AsyncNotifier<PatientsList> {
  @override
  Future<PatientsList> build() => fetchPatients();

  Future<PatientsList> fetchPatients({int page = 1, String? search}) async {
    final dio = ref.read(dioProvider);
    final response = await dio.get(
      ApiEndpoints.patients,
      queryParameters: {
        'page': page,
        'page_size': 20,
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    final data = response.data['data'] as List;
    final meta = response.data['meta'];
    return PatientsList(
      items: data.map((e) => Patient.fromJson(e)).toList(),
      total: meta['total'] ?? 0,
      page: meta['page'] ?? 1,
      totalPages: meta['total_pages'] ?? 1,
    );
  }

  Future<void> refresh({int page = 1, String? search}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => fetchPatients(page: page, search: search));
  }

  Future<bool> createPatient(PatientCreate data) async {
    final dio = ref.read(dioProvider);
    await dio.post(ApiEndpoints.patients, data: data.toJson());
    await refresh();
    return true;
  }
}

final medicalProvider =
    AsyncNotifierProvider<MedicalNotifier, PatientsList>(
  () => MedicalNotifier(),
);

final patientDetailProvider =
    FutureProvider.family<Patient, String>((ref, id) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.patientById(id));
  return Patient.fromJson(response.data['data']);
});

final patientVisitsProvider =
    FutureProvider.family<List<PatientVisit>, String>((ref, patientId) async {
  final dio = ref.read(dioProvider);
  final response =
      await dio.get(ApiEndpoints.patientVisits(patientId));
  final data = response.data['data'] as List;
  return data.map((e) => PatientVisit.fromJson(e)).toList();
});
