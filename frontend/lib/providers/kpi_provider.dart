import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/api_client.dart';
import '../core/api/api_endpoints.dart';

class KpiConfig {
  final String id;
  final String name;
  final String description;
  final String unit;
  final double target;
  final String frequency;
  final String departmentId;
  final String? departmentName;
  final bool isActive;

  const KpiConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.unit,
    required this.target,
    required this.frequency,
    required this.departmentId,
    this.departmentName,
    this.isActive = true,
  });

  factory KpiConfig.fromJson(Map<String, dynamic> json) {
    return KpiConfig(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      unit: json['target_unit'] ?? json['unit'] ?? '',
      target: (json['target_value'] ?? json['target'] ?? 0.0).toDouble(),
      frequency: json['period'] ?? json['frequency'] ?? 'MONTHLY',
      departmentId:
          (json['entity_id'] ?? json['department_id'] ?? '').toString(),
      departmentName: json['department_name'],
      isActive: json['is_active'] ?? true,
    );
  }
}

class KpiReport {
  final String configId;
  final String kpiName;
  final double target;
  final double actual;
  final String period;
  final String departmentName;
  final double achievementRate;

  const KpiReport({
    required this.configId,
    required this.kpiName,
    required this.target,
    required this.actual,
    required this.period,
    required this.departmentName,
    required this.achievementRate,
  });

  factory KpiReport.fromJson(Map<String, dynamic> json) {
    return KpiReport(
      configId: json['config_id'] ?? '',
      kpiName: json['kpi_name'] ?? '',
      target: (json['target'] ?? 0.0).toDouble(),
      actual: (json['actual'] ?? 0.0).toDouble(),
      period: json['period'] ?? '',
      departmentName: json['department_name'] ?? '',
      achievementRate: (json['achievement_rate'] ?? 0.0).toDouble(),
    );
  }
}

final kpiConfigsProvider = FutureProvider<List<KpiConfig>>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.kpiConfigs);
  final data = response.data['data'] as List;
  return data.map((e) => KpiConfig.fromJson(e)).toList();
});

final kpiReportsProvider = FutureProvider<List<KpiReport>>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(ApiEndpoints.kpiReports);
  final data = response.data['data'] as List;
  return data.map((e) => KpiReport.fromJson(e)).toList();
});
