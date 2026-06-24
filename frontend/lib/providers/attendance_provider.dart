import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/api_client.dart';
import '../core/api/api_endpoints.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

enum AttendanceStatus { present, absent, excused }

extension AttendanceStatusExtension on AttendanceStatus {
  String get value {
    switch (this) {
      case AttendanceStatus.present:
        return 'PRESENT';
      case AttendanceStatus.absent:
        return 'ABSENT';
      case AttendanceStatus.excused:
        return 'EXCUSED';
    }
  }

  static AttendanceStatus fromString(String s) {
    switch (s.toUpperCase()) {
      case 'PRESENT':
        return AttendanceStatus.present;
      case 'EXCUSED':
        return AttendanceStatus.excused;
      default:
        return AttendanceStatus.absent;
    }
  }
}

class Meeting {
  final String id;
  final String title;
  final DateTime meetingDate;
  final String type;
  final String? groupId;
  final String? teamId;
  final int? totalExpected;
  final int? totalPresent;

  const Meeting({
    required this.id,
    required this.title,
    required this.meetingDate,
    required this.type,
    this.groupId,
    this.teamId,
    this.totalExpected,
    this.totalPresent,
  });

  double get attendanceRate => totalExpected != null && totalExpected! > 0
      ? (totalPresent ?? 0) / totalExpected! * 100
      : 0;

  factory Meeting.fromJson(Map<String, dynamic> json) {
    return Meeting(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      meetingDate: DateTime.parse(
          json['meeting_date'] ?? DateTime.now().toIso8601String()),
      type: json['type'] ?? 'REGULAR',
      groupId: json['group_id'],
      teamId: json['team_id'],
      totalExpected: json['total_expected'],
      totalPresent: json['total_present'],
    );
  }
}

class AttendanceRecord {
  final String memberId;
  final String memberName;
  final String? photoUrl;
  final AttendanceStatus status;

  const AttendanceRecord({
    required this.memberId,
    required this.memberName,
    this.photoUrl,
    required this.status,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      memberId: json['member_id'] ?? '',
      memberName: json['member_name'] ?? '',
      photoUrl: json['photo_url'],
      status: AttendanceStatusExtension.fromString(
          json['status'] ?? 'ABSENT'),
    );
  }

  AttendanceRecord copyWith({AttendanceStatus? status}) {
    return AttendanceRecord(
      memberId: memberId,
      memberName: memberName,
      photoUrl: photoUrl,
      status: status ?? this.status,
    );
  }
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class AttendanceState {
  final List<Meeting> meetings;
  final Meeting? selectedMeeting;
  final List<AttendanceRecord> records;
  final bool isLoading;
  final bool isSaving;
  final String? error;

  const AttendanceState({
    this.meetings = const [],
    this.selectedMeeting,
    this.records = const [],
    this.isLoading = false,
    this.isSaving = false,
    this.error,
  });

  int get presentCount =>
      records.where((r) => r.status == AttendanceStatus.present).length;

  AttendanceState copyWith({
    List<Meeting>? meetings,
    Meeting? selectedMeeting,
    List<AttendanceRecord>? records,
    bool? isLoading,
    bool? isSaving,
    String? error,
  }) {
    return AttendanceState(
      meetings: meetings ?? this.meetings,
      selectedMeeting: selectedMeeting ?? this.selectedMeeting,
      records: records ?? this.records,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      error: error,
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class AttendanceNotifier extends StateNotifier<AttendanceState> {
  final Ref _ref;

  AttendanceNotifier(this._ref) : super(const AttendanceState());

  Future<void> loadMeetings({String? groupId, String? teamId}) async {
    state = state.copyWith(isLoading: true);
    try {
      final dio = _ref.read(dioProvider);
      final response = await dio.get(
        ApiEndpoints.meetings,
        queryParameters: {
          if (groupId != null) 'group_id': groupId,
          if (teamId != null) 'team_id': teamId,
          'page_size': 50,
        },
      );
      final data = response.data['data'] as List;
      final meetings = data.map((e) => Meeting.fromJson(e)).toList();
      state = state.copyWith(meetings: meetings, isLoading: false);
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: 'Failed to load meetings');
    }
  }

  Future<void> selectMeeting(Meeting meeting) async {
    state = state.copyWith(selectedMeeting: meeting, isLoading: true);
    try {
      final dio = _ref.read(dioProvider);
      final response = await dio.get(
          ApiEndpoints.meetingAttendance(meeting.id));
      final data = response.data['data'] as List;
      final records =
          data.map((e) => AttendanceRecord.fromJson(e)).toList();
      state = state.copyWith(records: records, isLoading: false);
    } catch (e) {
      state =
          state.copyWith(isLoading: false, error: 'Failed to load attendance');
    }
  }

  Future<void> createMeeting(String title, DateTime date,
      {String? groupId, String? teamId}) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.post(ApiEndpoints.meetings, data: {
      'title': title,
      'meeting_date': date.toIso8601String(),
      'type': 'REGULAR',
      if (groupId != null) 'group_id': groupId,
      if (teamId != null) 'team_id': teamId,
    });
    final meeting = Meeting.fromJson(response.data['data']);
    await loadMeetings(groupId: groupId, teamId: teamId);
    await selectMeeting(meeting);
  }

  void updateAttendance(String memberId, AttendanceStatus status) {
    final updated = state.records.map((r) {
      if (r.memberId == memberId) return r.copyWith(status: status);
      return r;
    }).toList();
    state = state.copyWith(records: updated);
  }

  void markAllPresent() {
    final updated = state.records
        .map((r) => r.copyWith(status: AttendanceStatus.present))
        .toList();
    state = state.copyWith(records: updated);
  }

  Future<bool> submitAttendance() async {
    if (state.selectedMeeting == null) return false;
    state = state.copyWith(isSaving: true);
    try {
      final dio = _ref.read(dioProvider);
      final attendanceData = state.records.map((r) => {
            'member_id': r.memberId,
            'status': r.status.value,
          }).toList();
      await dio.post(
        ApiEndpoints.meetingAttendance(state.selectedMeeting!.id),
        data: {'attendance': attendanceData},
      );
      state = state.copyWith(isSaving: false);
      return true;
    } catch (e) {
      state = state.copyWith(
          isSaving: false, error: 'Failed to submit attendance');
      return false;
    }
  }
}

final attendanceProvider =
    StateNotifierProvider<AttendanceNotifier, AttendanceState>(
  (ref) => AttendanceNotifier(ref),
);
