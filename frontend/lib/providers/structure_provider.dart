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
      headId: json['head_id'],
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
  final String departmentId;
  final String? leaderId;
  final String? leaderName;
  final int memberCount;

  const Team({
    required this.id,
    required this.name,
    this.description,
    required this.departmentId,
    this.leaderId,
    this.leaderName,
    this.memberCount = 0,
  });

  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      departmentId: json['department_id'] ?? '',
      leaderId: json['leader_id'],
      leaderName: json['leader_name'],
      memberCount: json['member_count'] ?? 0,
    );
  }
}

class Group {
  final String id;
  final String name;
  final String? description;
  final String teamId;
  final String? leaderId;
  final String? leaderName;
  final int memberCount;

  const Group({
    required this.id,
    required this.name,
    this.description,
    required this.teamId,
    this.leaderId,
    this.leaderName,
    this.memberCount = 0,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      teamId: json['team_id'] ?? '',
      leaderId: json['leader_id'],
      leaderName: json['leader_name'],
      memberCount: json['member_count'] ?? 0,
    );
  }
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
