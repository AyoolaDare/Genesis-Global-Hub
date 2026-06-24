import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/api_client.dart';
import '../core/api/api_endpoints.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

enum FollowUpStage {
  initial,
  firstContact,
  secondContact,
  thirdContact,
  integrated,
  lost,
}

extension FollowUpStageExtension on FollowUpStage {
  String get value {
    switch (this) {
      case FollowUpStage.initial:
        return 'INITIAL';
      case FollowUpStage.firstContact:
        return 'FIRST_CONTACT';
      case FollowUpStage.secondContact:
        return 'SECOND_CONTACT';
      case FollowUpStage.thirdContact:
        return 'THIRD_CONTACT';
      case FollowUpStage.integrated:
        return 'INTEGRATED';
      case FollowUpStage.lost:
        return 'LOST';
    }
  }

  String get label {
    switch (this) {
      case FollowUpStage.initial:
        return 'Initial';
      case FollowUpStage.firstContact:
        return '1st Contact';
      case FollowUpStage.secondContact:
        return '2nd Contact';
      case FollowUpStage.thirdContact:
        return '3rd Contact';
      case FollowUpStage.integrated:
        return 'Integrated';
      case FollowUpStage.lost:
        return 'Lost';
    }
  }

  int get stepIndex {
    switch (this) {
      case FollowUpStage.initial:
        return 0;
      case FollowUpStage.firstContact:
        return 1;
      case FollowUpStage.secondContact:
        return 2;
      case FollowUpStage.thirdContact:
        return 3;
      case FollowUpStage.integrated:
        return 4;
      case FollowUpStage.lost:
        return 5;
    }
  }

  static FollowUpStage fromString(String s) {
    switch (s.toUpperCase()) {
      case 'INITIAL':
        return FollowUpStage.initial;
      case 'FIRST_CONTACT':
        return FollowUpStage.firstContact;
      case 'SECOND_CONTACT':
        return FollowUpStage.secondContact;
      case 'THIRD_CONTACT':
        return FollowUpStage.thirdContact;
      case 'INTEGRATED':
        return FollowUpStage.integrated;
      case 'LOST':
        return FollowUpStage.lost;
      default:
        return FollowUpStage.initial;
    }
  }
}

class FollowUpTask {
  final String id;
  final String convertName;
  final String? convertPhone;
  final String? notes;
  final FollowUpStage stage;
  final DateTime dueDate;
  final bool isCompleted;
  final bool isOverdue;
  final String assignedToId;
  final String? assignedToName;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? convertId;

  const FollowUpTask({
    required this.id,
    required this.convertName,
    this.convertPhone,
    this.notes,
    required this.stage,
    required this.dueDate,
    required this.isCompleted,
    required this.isOverdue,
    required this.assignedToId,
    this.assignedToName,
    required this.createdAt,
    this.completedAt,
    this.convertId,
  });

  factory FollowUpTask.fromJson(Map<String, dynamic> json) {
    final dueDate = DateTime.parse(json['due_date'] ?? DateTime.now().toIso8601String());
    return FollowUpTask(
      id: json['id'] ?? '',
      convertName: json['convert_name'] ?? '',
      convertPhone: json['convert_phone'],
      notes: json['notes'],
      stage: FollowUpStageExtension.fromString(json['stage'] ?? 'INITIAL'),
      dueDate: dueDate,
      isCompleted: json['is_completed'] ?? false,
      isOverdue: !json['is_completed'] && dueDate.isBefore(DateTime.now()),
      assignedToId: json['assigned_to_id'] ?? '',
      assignedToName: json['assigned_to_name'],
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'])
          : null,
      convertId: json['convert_id'],
    );
  }
}

class FollowUpTasksList {
  final List<FollowUpTask> items;
  final int total;
  final int page;
  final int totalPages;

  const FollowUpTasksList({
    required this.items,
    required this.total,
    required this.page,
    required this.totalPages,
  });

  factory FollowUpTasksList.empty() => const FollowUpTasksList(
        items: [],
        total: 0,
        page: 1,
        totalPages: 0,
      );
}

class NewConvert {
  final String firstName;
  final String lastName;
  final String? phone;
  final String? address;
  final String? notes;
  final DateTime dateOfVisit;

  const NewConvert({
    required this.firstName,
    required this.lastName,
    this.phone,
    this.address,
    this.notes,
    required this.dateOfVisit,
  });

  Map<String, dynamic> toJson() => {
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'address': address,
        'notes': notes,
        'date_of_visit': dateOfVisit.toIso8601String(),
      };
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class FollowUpNotifier extends AsyncNotifier<FollowUpTasksList> {
  @override
  Future<FollowUpTasksList> build() => fetchTasks();

  Future<FollowUpTasksList> fetchTasks({
    int page = 1,
    String? stage,
    bool? today,
  }) async {
    final dio = ref.read(dioProvider);
    final response = await dio.get(
      ApiEndpoints.followUpTasks,
      queryParameters: {
        'page': page,
        'page_size': 20,
        if (stage != null) 'stage': stage,
        if (today == true) 'due_today': true,
      },
    );
    final data = response.data['data'] as List;
    final meta = response.data['meta'];
    return FollowUpTasksList(
      items: data.map((e) => FollowUpTask.fromJson(e)).toList(),
      total: meta['total'] ?? 0,
      page: meta['page'] ?? 1,
      totalPages: meta['total_pages'] ?? 1,
    );
  }

  Future<void> refresh({int page = 1, String? stage}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => fetchTasks(page: page, stage: stage));
  }

  Future<bool> completeTask(String taskId) async {
    final dio = ref.read(dioProvider);
    await dio.post(ApiEndpoints.followUpTaskComplete(taskId));
    await refresh();
    return true;
  }

  Future<bool> createNewConvert(NewConvert data) async {
    final dio = ref.read(dioProvider);
    await dio.post(ApiEndpoints.newConverts, data: data.toJson());
    return true;
  }
}

final followUpProvider =
    AsyncNotifierProvider<FollowUpNotifier, FollowUpTasksList>(
  () => FollowUpNotifier(),
);

final followUpTaskDetailProvider =
    FutureProvider.family<FollowUpTask, String>((ref, id) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.followUpTaskById(id));
  return FollowUpTask.fromJson(response.data['data']);
});
