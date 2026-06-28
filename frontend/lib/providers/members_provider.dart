import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/api_client.dart';
import '../core/api/api_endpoints.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

enum MemberStatus { active, pending, inactive, rejected }

extension MemberStatusExtension on MemberStatus {
  String get value {
    switch (this) {
      case MemberStatus.active:
        return 'ACTIVE';
      case MemberStatus.pending:
        return 'PENDING';
      case MemberStatus.inactive:
        return 'INACTIVE';
      case MemberStatus.rejected:
        return 'REJECTED';
    }
  }

  static MemberStatus fromString(String s) {
    switch (s.toUpperCase()) {
      case 'ACTIVE':
        return MemberStatus.active;
      case 'PENDING':
        return MemberStatus.pending;
      case 'INACTIVE':
        return MemberStatus.inactive;
      case 'REJECTED':
        return MemberStatus.rejected;
      default:
        return MemberStatus.pending;
    }
  }
}

class Member {
  final String id;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final String? photoUrl;
  final MemberStatus status;
  final String role;
  final DateTime? joinedAt;
  final DateTime createdAt;
  final String? submittedBy;
  final String? submittedByName;
  final DateTime? submittedAt;
  final String? notes;
  final bool isDuplicateFlagged;
  final String? duplicateOfId;
  final Map<String, dynamic>? spiritualData;
  final List<String> departmentIds;
  final String? address;
  final String? gender;
  final DateTime? dateOfBirth;
  final String? occupation;
  final String? maritalStatus;
  final DateTime? salvationDate;
  final bool waterBaptismStatus;
  final bool holySpiritBaptismStatus;

  const Member({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.email,
    this.phone,
    this.photoUrl,
    required this.status,
    required this.role,
    this.joinedAt,
    required this.createdAt,
    this.submittedBy,
    this.submittedByName,
    this.submittedAt,
    this.notes,
    this.isDuplicateFlagged = false,
    this.duplicateOfId,
    this.spiritualData,
    this.departmentIds = const [],
    this.address,
    this.gender,
    this.dateOfBirth,
    this.occupation,
    this.maritalStatus,
    this.salvationDate,
    this.waterBaptismStatus = false,
    this.holySpiritBaptismStatus = false,
  });

  String get fullName => '$firstName $lastName';

  factory Member.fromJson(Map<String, dynamic> json) {
    final fullName = (json['full_name'] ?? '').toString().trim();
    final spaceIdx = fullName.indexOf(' ');
    final firstName = spaceIdx >= 0 ? fullName.substring(0, spaceIdx) : fullName;
    final lastName = spaceIdx >= 0 ? fullName.substring(spaceIdx + 1) : '';
    return Member(
      id: json['id'] ?? '',
      firstName: firstName,
      lastName: lastName,
      email: json['email'],
      phone: json['phone'],
      photoUrl: json['photo_url'],
      status: MemberStatusExtension.fromString(
          json['membership_status'] ?? json['status'] ?? 'PENDING'),
      role: json['role'] ?? 'MEMBER',
      joinedAt: json['joined_at'] != null
          ? DateTime.tryParse(json['joined_at'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      submittedBy: json['submitted_by']?.toString(),
      submittedByName: json['submitted_by_name'],
      submittedAt: json['submitted_at'] != null
          ? DateTime.tryParse(json['submitted_at'])
          : null,
      notes: json['submitter_notes'] ?? json['notes'],
      isDuplicateFlagged: json['is_duplicate_flagged'] ?? false,
      duplicateOfId: (json['duplicate_of'] ?? json['duplicate_of_id'])?.toString(),
      spiritualData: json['spiritual_data'],
      departmentIds: json['department_ids'] != null
          ? List<String>.from(json['department_ids'])
          : [],
      address: json['address'],
      gender: json['gender'],
      dateOfBirth: json['date_of_birth'] != null
          ? DateTime.tryParse(json['date_of_birth'])
          : null,
      occupation: json['occupation'],
      maritalStatus: json['marital_status'],
      salvationDate: json['salvation_date'] != null
          ? DateTime.tryParse(json['salvation_date'])
          : null,
      waterBaptismStatus: json['water_baptism_status'] ?? false,
      holySpiritBaptismStatus: json['holy_spirit_baptism_status'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'phone': phone,
        'photo_url': photoUrl,
        'status': status.value,
        'role': role,
        'joined_at': joinedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'submitted_by': submittedBy,
        'notes': notes,
        'is_duplicate_flagged': isDuplicateFlagged,
        'duplicate_of_id': duplicateOfId,
        'spiritual_data': spiritualData,
        'department_ids': departmentIds,
        'address': address,
        'gender': gender,
        'date_of_birth': dateOfBirth?.toIso8601String(),
        'occupation': occupation,
        'marital_status': maritalStatus,
        'salvation_date': salvationDate?.toIso8601String(),
        'water_baptism_status': waterBaptismStatus,
        'holy_spirit_baptism_status': holySpiritBaptismStatus,
      };
}

class MemberCreate {
  final String firstName;
  final String lastName;
  final String? email;
  final String phone;
  final String? address;
  final String? gender;
  final DateTime? dateOfBirth;
  final String? occupation;
  final String? maritalStatus;
  final String? notes;

  const MemberCreate({
    required this.firstName,
    required this.lastName,
    this.email,
    required this.phone,
    this.address,
    this.gender,
    this.dateOfBirth,
    this.occupation,
    this.maritalStatus,
    this.notes,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'full_name': '$firstName $lastName'.trim(),
      'phone': phone,
      if (email != null && email!.isNotEmpty) 'email': email,
      if (address != null && address!.isNotEmpty) 'address': address,
      if (gender != null) 'gender': gender!.toUpperCase(),
      if (dateOfBirth != null)
        'date_of_birth': dateOfBirth!.toIso8601String().substring(0, 10),
      if (maritalStatus != null) 'marital_status': maritalStatus!.toUpperCase(),
      if (notes != null && notes!.isNotEmpty) 'submitter_notes': notes,
    };
    return map;
  }
}

class MembersList {
  final List<Member> items;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;

  const MembersList({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  factory MembersList.empty() => const MembersList(
        items: [],
        total: 0,
        page: 1,
        pageSize: 20,
        totalPages: 0,
      );
}

class MemberLookupResult {
  final String id;
  final String fullName;
  final String? phone;
  final String? email;
  final String? gender;
  final DateTime? dateOfBirth;
  final String? address;

  const MemberLookupResult({
    required this.id,
    required this.fullName,
    this.phone,
    this.email,
    this.gender,
    this.dateOfBirth,
    this.address,
  });

  factory MemberLookupResult.fromJson(Map<String, dynamic> json) {
    return MemberLookupResult(
      id: json['id']?.toString() ?? '',
      fullName: json['full_name'] ?? '',
      phone: json['phone'],
      email: json['email'],
      gender: json['gender'],
      dateOfBirth: json['date_of_birth'] != null
          ? DateTime.tryParse(json['date_of_birth'])
          : null,
      address: json['address'],
    );
  }
}

final memberLookupProvider =
    FutureProvider.family<List<MemberLookupResult>, String>((ref, query) async {
  if (query.trim().length < 2) return [];
  final dio = ref.read(dioProvider);
  final response = await dio.get(
    ApiEndpoints.memberLookup,
    queryParameters: {'search': query.trim(), 'per_page': 20},
  );
  final data = response.data['data'] as List;
  return data.map((e) => MemberLookupResult.fromJson(e)).toList();
});

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class MembersNotifier extends AsyncNotifier<MembersList> {
  @override
  Future<MembersList> build() async {
    return fetchMembers();
  }

  Future<MembersList> fetchMembers({
    int page = 1,
    String? search,
    String? status,
  }) async {
    final dio = ref.read(dioProvider);
    final response = await dio.get(
      ApiEndpoints.members,
      queryParameters: {
        'page': page,
        'page_size': 20,
        if (search != null && search.isNotEmpty) 'search': search,
        if (status != null) 'status': status,
      },
    );
    final data = response.data['data'];
    final meta = response.data['meta'];
    final items = (data as List).map((e) => Member.fromJson(e)).toList();
    return MembersList(
      items: items,
      total: meta['total'] ?? 0,
      page: meta['page'] ?? 1,
      pageSize: meta['page_size'] ?? 20,
      totalPages: meta['total_pages'] ?? 1,
    );
  }

  Future<void> refresh({int page = 1, String? search, String? status}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => fetchMembers(page: page, search: search, status: status),
    );
  }

  Future<Member?> getMember(String id) async {
    final dio = ref.read(dioProvider);
    final response = await dio.get(ApiEndpoints.memberById(id));
    return Member.fromJson(response.data['data']);
  }

  Future<bool> createMember(MemberCreate data) async {
    final dio = ref.read(dioProvider);
    await dio.post(ApiEndpoints.members, data: data.toJson());
    await refresh();
    return true;
  }

  /// Creates a member and returns the new member's ID, or null on failure.
  Future<String?> createMemberAndGetId(MemberCreate data) async {
    final dio = ref.read(dioProvider);
    final response = await dio.post(ApiEndpoints.members, data: data.toJson());
    await refresh();
    return response.data['data']?['id']?.toString();
  }

  Future<bool> approveMember(String memberId) async {
    final dio = ref.read(dioProvider);
    await dio.post(ApiEndpoints.memberApprove(memberId));
    await refresh();
    return true;
  }

  Future<bool> rejectMember(String memberId, String reason) async {
    final dio = ref.read(dioProvider);
    await dio.post(
      ApiEndpoints.memberReject(memberId),
      data: {'reason': reason},
    );
    await refresh();
    return true;
  }

  Future<bool> mergeMember(
      String sourceId, String targetId, Map<String, dynamic> fields) async {
    final dio = ref.read(dioProvider);
    await dio.post(
      ApiEndpoints.memberMerge(sourceId),
      data: {'target_id': targetId, 'fields': fields},
    );
    await refresh();
    return true;
  }
}

final membersProvider = AsyncNotifierProvider<MembersNotifier, MembersList>(
  () => MembersNotifier(),
);

// Single member provider
final memberDetailProvider =
    FutureProvider.family<Member, String>((ref, id) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.memberById(id));
  return Member.fromJson(response.data['data']);
});

// Pending members provider
final pendingMembersProvider = FutureProvider<List<Member>>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(
    ApiEndpoints.members,
    queryParameters: {'status': 'PENDING', 'page_size': 100},
  );
  final data = response.data['data'] as List;
  return data.map((e) => Member.fromJson(e)).toList();
});
