import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/api_client.dart';
import '../core/api/api_endpoints.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class Department {
  final String id;
  final String name;
  final String? description;
  final String? headId;
  final String? headName;
  final int memberCount;
  final int teamCount;

  const Department({
    required this.id,
    required this.name,
    this.description,
    this.headId,
    this.headName,
    this.memberCount = 0,
    this.teamCount = 0,
  });

  factory Department.fromJson(Map<String, dynamic> json) {
    return Department(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      headId: json['head_id']?.toString(),
      headName: json['head_name'],
      memberCount: json['member_count'] ?? 0,
      teamCount: json['team_count'] ?? 0,
    );
  }
}

class Team {
  final String id;
  final String name;
  final String? description;
  final String? departmentId;
  final String? departmentName;
  final String? leaderId;
  final String? leaderName;
  final int memberCount;

  const Team({
    required this.id,
    required this.name,
    this.description,
    this.departmentId,
    this.departmentName,
    this.leaderId,
    this.leaderName,
    this.memberCount = 0,
  });

  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      departmentId: json['department_id']?.toString(),
      departmentName: json['department_name'],
      leaderId: json['leader_id']?.toString(),
      leaderName: json['leader_name'],
      memberCount: json['member_count'] ?? 0,
    );
  }
}

class Group {
  final String id;
  final String name;
  final String? description;
  final String? teamId;
  final String? teamName;
  final String? departmentId;
  final String? departmentName;
  final String? leaderId;
  final String? leaderName;
  final int memberCount;

  const Group({
    required this.id,
    required this.name,
    this.description,
    this.teamId,
    this.teamName,
    this.departmentId,
    this.departmentName,
    this.leaderId,
    this.leaderName,
    this.memberCount = 0,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      teamId: json['team_id']?.toString(),
      teamName: json['team_name'],
      departmentId: json['department_id']?.toString(),
      departmentName: json['department_name'],
      leaderId: json['leader_id']?.toString(),
      leaderName: json['leader_name'],
      memberCount: json['member_count'] ?? 0,
    );
  }
}

class MemberUnitAssignment {
  final String id;
  final String assignmentType; // DEPARTMENT | TEAM | GROUP
  final String assignmentId;
  final String entityName;
  final String? roleInAssignment;
  final DateTime? joinedAt;

  const MemberUnitAssignment({
    required this.id,
    required this.assignmentType,
    required this.assignmentId,
    required this.entityName,
    this.roleInAssignment,
    this.joinedAt,
  });

  factory MemberUnitAssignment.fromJson(Map<String, dynamic> json) {
    return MemberUnitAssignment(
      id: json['id'] ?? '',
      assignmentType: json['assignment_type'] ?? '',
      assignmentId: json['assignment_id'] ?? '',
      entityName: json['entity_name'] ?? 'Unknown',
      roleInAssignment: json['role_in_assignment'],
      joinedAt: json['joined_at'] != null
          ? DateTime.tryParse(json['joined_at'].toString())
          : null,
    );
  }
}

class MemberPortalAccess {
  final String id;
  final String email;
  final String role;
  final String memberId;
  final bool isActive;
  final DateTime? lastLoginAt;

  const MemberPortalAccess({
    required this.id,
    required this.email,
    required this.role,
    required this.memberId,
    required this.isActive,
    this.lastLoginAt,
  });

  factory MemberPortalAccess.fromJson(Map<String, dynamic> json) {
    return MemberPortalAccess(
      id: json['id']?.toString() ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? '',
      memberId: json['member_id']?.toString() ?? '',
      isActive: json['is_active'] ?? false,
      lastLoginAt: json['last_login_at'] != null
          ? DateTime.tryParse(json['last_login_at'].toString())
          : null,
    );
  }
}

class PortalAccessResult {
  final MemberPortalAccess user;
  final String? temporaryPassword;

  const PortalAccessResult({
    required this.user,
    this.temporaryPassword,
  });
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final departmentsProvider = FutureProvider<List<Department>>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.departments);
  final data = response.data['data'] as List;
  return data.map((e) => Department.fromJson(e)).toList();
});

final departmentDetailProvider =
    FutureProvider.family<Department, String>((ref, id) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.departmentById(id));
  return Department.fromJson(response.data['data']);
});

final teamsProvider = FutureProvider<List<Team>>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.teams);
  final data = response.data['data'] as List;
  return data.map((e) => Team.fromJson(e)).toList();
});

final groupsProvider = FutureProvider<List<Group>>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.groups);
  final data = response.data['data'] as List;
  return data.map((e) => Group.fromJson(e)).toList();
});

final memberAssignmentsProvider =
    FutureProvider.family<List<MemberUnitAssignment>, String>(
        (ref, memberId) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.memberAssignments(memberId));
  final data = response.data['data'] as List;
  return data
      .map((e) => MemberUnitAssignment.fromJson(Map<String, dynamic>.from(e)))
      .toList();
});

final memberPortalAccessProvider =
    FutureProvider.family<MemberPortalAccess?, String>((ref, memberId) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.memberPortalAccess(memberId));
  final data = response.data['data'];
  if (data == null) return null;
  return MemberPortalAccess.fromJson(Map<String, dynamic>.from(data));
});

final structureActionsProvider = Provider<StructureActions>((ref) {
  return StructureActions(ref);
});

class StructureActions {
  final Ref _ref;

  StructureActions(this._ref);

  Future<PortalAccessResult> savePortalAccess({
    required String memberId,
    required String email,
    required String role,
    String? temporaryPassword,
  }) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.post(
      ApiEndpoints.memberPortalAccess(memberId),
      data: {
        'email': email,
        'role': role,
        if (temporaryPassword != null && temporaryPassword.trim().isNotEmpty)
          'temporary_password': temporaryPassword.trim(),
      },
    );
    final data = Map<String, dynamic>.from(response.data['data']);
    return PortalAccessResult(
      user: MemberPortalAccess.fromJson(
        Map<String, dynamic>.from(data['user']),
      ),
      temporaryPassword: data['temporary_password'],
    );
  }

  Future<void> revokePortalAccess(String memberId) async {
    final dio = _ref.read(dioProvider);
    await dio.delete(ApiEndpoints.memberPortalAccess(memberId));
  }
}
