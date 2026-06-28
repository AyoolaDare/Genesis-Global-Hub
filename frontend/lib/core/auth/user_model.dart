import 'dart:convert';

enum UserRole {
  superAdmin,
  pastor,
  financeAdmin,
  hrAdmin,
  departmentHead,
  teamLeader,
  groupLeader,
  followUp,
  medical,
  member,
  unknown,
}

extension UserRoleExtension on UserRole {
  String get name {
    switch (this) {
      case UserRole.superAdmin:
        return 'SUPER_ADMIN';
      case UserRole.pastor:
        return 'PASTOR';
      case UserRole.financeAdmin:
        return 'FINANCE_ADMIN';
      case UserRole.hrAdmin:
        return 'HR_ADMIN';
      case UserRole.departmentHead:
        return 'DEPARTMENT_HEAD';
      case UserRole.teamLeader:
        return 'TEAM_LEADER';
      case UserRole.groupLeader:
        return 'GROUP_LEADER';
      case UserRole.followUp:
        return 'FOLLOW_UP';
      case UserRole.medical:
        return 'MEDICAL';
      case UserRole.member:
        return 'MEMBER';
      case UserRole.unknown:
        return 'UNKNOWN';
    }
  }

  String get displayName {
    switch (this) {
      case UserRole.superAdmin:
        return 'Super Admin';
      case UserRole.pastor:
        return 'Pastor';
      case UserRole.financeAdmin:
        return 'Sponsor Admin';
      case UserRole.hrAdmin:
        return 'HR Admin';
      case UserRole.departmentHead:
        return 'Department Head';
      case UserRole.teamLeader:
        return 'Team Leader';
      case UserRole.groupLeader:
        return 'Group Leader';
      case UserRole.followUp:
        return 'Follow-up Officer';
      case UserRole.medical:
        return 'Medical Officer';
      case UserRole.member:
        return 'Member';
      case UserRole.unknown:
        return 'Unknown';
    }
  }

  String get dashboardRoute {
    switch (this) {
      case UserRole.superAdmin:
      case UserRole.pastor:
        return '/admin';
      case UserRole.financeAdmin:
        return '/finance';
      case UserRole.hrAdmin:
        return '/hr';
      case UserRole.departmentHead:
        return '/dept';
      case UserRole.teamLeader:
        return '/team';
      case UserRole.groupLeader:
        return '/group';
      case UserRole.followUp:
        return '/follow-up';
      case UserRole.medical:
        return '/medical';
      case UserRole.member:
        return '/profile';
      case UserRole.unknown:
        return '/login';
    }
  }

  static UserRole fromString(String role) {
    switch (role.toUpperCase()) {
      case 'SUPER_ADMIN':
        return UserRole.superAdmin;
      case 'PASTOR':
        return UserRole.pastor;
      case 'FINANCE_ADMIN':
        return UserRole.financeAdmin;
      case 'HR_ADMIN':
        return UserRole.hrAdmin;
      case 'DEPARTMENT_HEAD':
        return UserRole.departmentHead;
      case 'TEAM_LEADER':
        return UserRole.teamLeader;
      case 'GROUP_LEADER':
        return UserRole.groupLeader;
      case 'FOLLOW_UP':
        return UserRole.followUp;
      case 'MEDICAL':
        return UserRole.medical;
      case 'MEMBER':
        return UserRole.member;
      default:
        return UserRole.unknown;
    }
  }
}

class UserScope {
  final List<String> departments;
  final List<String> teams;
  final List<String> groups;

  const UserScope({
    this.departments = const [],
    this.teams = const [],
    this.groups = const [],
  });

  factory UserScope.fromJson(Map<String, dynamic> json) {
    return UserScope(
      departments: List<String>.from(json['departments'] ?? []),
      teams: List<String>.from(json['teams'] ?? []),
      groups: List<String>.from(json['groups'] ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
        'departments': departments,
        'teams': teams,
        'groups': groups,
      };

  factory UserScope.empty() => const UserScope();
}

class CurrentUser {
  final String id;
  final String email;
  final String? name;
  final String? photoUrl;
  final UserRole role;
  final UserScope scope;
  final int issuedAt;
  final int expiresAt;

  const CurrentUser({
    required this.id,
    required this.email,
    this.name,
    this.photoUrl,
    required this.role,
    required this.scope,
    required this.issuedAt,
    required this.expiresAt,
  });

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch / 1000 > expiresAt;

  factory CurrentUser.fromJwtPayload(Map<String, dynamic> payload) {
    return CurrentUser(
      id: payload['sub'] ?? '',
      email: payload['email'] ?? '',
      name: payload['name'],
      photoUrl: payload['photo_url'],
      role: UserRoleExtension.fromString(payload['role'] ?? ''),
      scope: payload['scope'] != null
          ? UserScope.fromJson(payload['scope'])
          : UserScope.empty(),
      issuedAt: payload['iat'] ?? 0,
      expiresAt: payload['exp'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'photo_url': photoUrl,
        'role': role.name,
        'scope': scope.toJson(),
        'iat': issuedAt,
        'exp': expiresAt,
      };

  factory CurrentUser.fromJson(Map<String, dynamic> json) {
    return CurrentUser(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      name: json['name'],
      photoUrl: json['photo_url'],
      role: UserRoleExtension.fromString(json['role'] ?? ''),
      scope: json['scope'] != null
          ? UserScope.fromJson(json['scope'])
          : UserScope.empty(),
      issuedAt: json['iat'] ?? 0,
      expiresAt: json['exp'] ?? 0,
    );
  }

  CurrentUser copyWith({
    String? id,
    String? email,
    String? name,
    String? photoUrl,
    UserRole? role,
    UserScope? scope,
    int? issuedAt,
    int? expiresAt,
  }) {
    return CurrentUser(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      photoUrl: photoUrl ?? this.photoUrl,
      role: role ?? this.role,
      scope: scope ?? this.scope,
      issuedAt: issuedAt ?? this.issuedAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}

/// Decode a JWT token without verifying signature (client-side only)
Map<String, dynamic> decodeJwtPayload(String token) {
  final parts = token.split('.');
  if (parts.length != 3) {
    throw const FormatException('Invalid JWT format');
  }
  String payload = parts[1];
  // Add padding if needed
  switch (payload.length % 4) {
    case 1:
      payload += '===';
      break;
    case 2:
      payload += '==';
      break;
    case 3:
      payload += '=';
      break;
  }
  final decoded = utf8.decode(base64Url.decode(payload));
  return json.decode(decoded) as Map<String, dynamic>;
}
