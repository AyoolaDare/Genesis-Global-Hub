import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/api_client.dart';
import '../core/api/api_endpoints.dart';

class Worker {
  final String id;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final String? photoUrl;
  final String role;
  final String? department;
  final String employmentType;
  final DateTime? startDate;
  final String status;

  const Worker({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.email,
    this.phone,
    this.photoUrl,
    required this.role,
    this.department,
    required this.employmentType,
    this.startDate,
    required this.status,
  });

  String get fullName => '$firstName $lastName';

  factory Worker.fromJson(Map<String, dynamic> json) {
    return Worker(
      id: json['id'] ?? '',
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      email: json['email'],
      phone: json['phone'],
      photoUrl: json['photo_url'],
      role: json['role'] ?? '',
      department: json['department'],
      employmentType: json['employment_type'] ?? 'FULL_TIME',
      startDate: json['start_date'] != null
          ? DateTime.tryParse(json['start_date'])
          : null,
      status: json['status'] ?? 'ACTIVE',
    );
  }
}

class PerformanceReview {
  final String id;
  final String workerId;
  final String workerName;
  final String period;
  final double score;
  final String? comments;
  final String reviewedById;
  final String? reviewedByName;
  final DateTime reviewDate;

  const PerformanceReview({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.period,
    required this.score,
    this.comments,
    required this.reviewedById,
    this.reviewedByName,
    required this.reviewDate,
  });

  factory PerformanceReview.fromJson(Map<String, dynamic> json) {
    return PerformanceReview(
      id: json['id'] ?? '',
      workerId: json['worker_id'] ?? '',
      workerName: json['worker_name'] ?? '',
      period: json['period'] ?? '',
      score: (json['score'] ?? 0.0).toDouble(),
      comments: json['comments'],
      reviewedById: json['reviewed_by_id'] ?? '',
      reviewedByName: json['reviewed_by_name'],
      reviewDate: DateTime.parse(
          json['review_date'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class WorkersList {
  final List<Worker> items;
  final int total;
  final int page;
  final int totalPages;

  const WorkersList({
    required this.items,
    required this.total,
    required this.page,
    required this.totalPages,
  });

  factory WorkersList.empty() => const WorkersList(
        items: [],
        total: 0,
        page: 1,
        totalPages: 0,
      );
}

class HrNotifier extends AsyncNotifier<WorkersList> {
  @override
  Future<WorkersList> build() => fetchWorkers();

  Future<WorkersList> fetchWorkers({int page = 1, String? search}) async {
    final dio = ref.read(dioProvider);
    final response = await dio.get(
      ApiEndpoints.workers,
      queryParameters: {
        'page': page,
        'page_size': 20,
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    final data = response.data['data'] as List;
    final meta = response.data['meta'];
    return WorkersList(
      items: data.map((e) => Worker.fromJson(e)).toList(),
      total: meta['total'] ?? 0,
      page: meta['page'] ?? 1,
      totalPages: meta['total_pages'] ?? 1,
    );
  }

  Future<void> refresh({int page = 1, String? search}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => fetchWorkers(page: page, search: search));
  }
}

final hrProvider =
    AsyncNotifierProvider<HrNotifier, WorkersList>(() => HrNotifier());

final workerDetailProvider =
    FutureProvider.family<Worker, String>((ref, id) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.workerById(id));
  return Worker.fromJson(response.data['data']);
});

final performanceProvider =
    FutureProvider<List<PerformanceReview>>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.performance);
  final data = response.data['data'] as List;
  return data.map((e) => PerformanceReview.fromJson(e)).toList();
});
