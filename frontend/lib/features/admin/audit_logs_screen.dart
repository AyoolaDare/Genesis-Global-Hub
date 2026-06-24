import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/pagination_footer.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class AuditLog {
  final String id;
  final DateTime timestamp;
  final String userEmail;
  final String action;
  final String resourceType;
  final String resourceId;
  final Map<String, dynamic>? details;

  const AuditLog({
    required this.id,
    required this.timestamp,
    required this.userEmail,
    required this.action,
    required this.resourceType,
    required this.resourceId,
    this.details,
  });

  factory AuditLog.fromJson(Map<String, dynamic> json) {
    return AuditLog(
      id: json['id'] ?? '',
      timestamp: DateTime.parse(
          json['timestamp'] ?? DateTime.now().toIso8601String()),
      userEmail: json['user_email'] ?? '',
      action: json['action'] ?? '',
      resourceType: json['resource_type'] ?? '',
      resourceId: json['resource_id'] ?? '',
      details: json['details'],
    );
  }
}

class AuditLogsList {
  final List<AuditLog> items;
  final int total;
  final int page;
  final int totalPages;

  const AuditLogsList({
    required this.items,
    required this.total,
    required this.page,
    required this.totalPages,
  });

  factory AuditLogsList.empty() => const AuditLogsList(
        items: [],
        total: 0,
        page: 1,
        totalPages: 0,
      );
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final auditLogsProvider =
    FutureProvider.family<AuditLogsList, Map<String, dynamic>>(
  (ref, params) async {
    final dio = ref.read(dioProvider);
    final response = await dio.get(
      ApiEndpoints.auditLogs,
      queryParameters: {
        'page': params['page'] ?? 1,
        'page_size': 20,
        if (params['action'] != null) 'action': params['action'],
        if (params['from'] != null) 'from': params['from'],
        if (params['to'] != null) 'to': params['to'],
      },
    );
    final data = response.data['data'] as List;
    final meta = response.data['meta'];
    return AuditLogsList(
      items: data.map((e) => AuditLog.fromJson(e)).toList(),
      total: meta['total'] ?? 0,
      page: meta['page'] ?? 1,
      totalPages: meta['total_pages'] ?? 1,
    );
  },
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class AuditLogsScreen extends ConsumerStatefulWidget {
  const AuditLogsScreen({super.key});

  @override
  ConsumerState<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends ConsumerState<AuditLogsScreen> {
  int _page = 1;
  String? _selectedAction;
  DateTimeRange? _dateRange;

  static const List<String> _actionTypes = [
    'CREATE',
    'UPDATE',
    'DELETE',
    'LOGIN',
    'LOGOUT',
    'APPROVE',
    'REJECT',
    'EXPORT',
  ];

  Map<String, dynamic> get _params => {
        'page': _page,
        if (_selectedAction != null) 'action': _selectedAction,
        if (_dateRange != null)
          'from': _dateRange!.start.toIso8601String(),
        if (_dateRange != null) 'to': _dateRange!.end.toIso8601String(),
      };

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(auditLogsProvider(_params));

    return ShellLayout(
      title: 'Audit Logs',
      child: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: logsAsync.when(
              loading: () => _buildSkeleton(),
              error: (e, _) => ErrorState(
                message: e.toString().contains('403')
                    ? 'Access Denied'
                    : 'Failed to load audit logs',
                details: e.toString().contains('403')
                    ? 'You do not have permission to view audit logs.'
                    : e.toString(),
                onRetry: () => ref.invalidate(auditLogsProvider(_params)),
              ),
              data: (logs) => logs.items.isEmpty
                  ? const EmptyState(
                      icon: Icons.history_outlined,
                      title: 'No audit logs found',
                      subtitle: 'No records match the current filters.',
                    )
                  : _buildTable(logs),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Action type filter
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              initialValue: _selectedAction,
              decoration: const InputDecoration(
                labelText: 'Action Type',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('All Actions')),
                ..._actionTypes.map(
                  (a) => DropdownMenuItem(value: a, child: Text(a)),
                ),
              ],
              onChanged: (v) => setState(() {
                _selectedAction = v;
                _page = 1;
              }),
            ),
          ),
          const SizedBox(width: 16),
          // Date range picker
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range_outlined, size: 18),
            label: Text(
              _dateRange == null
                  ? 'Select Date Range'
                  : '${_formatDate(_dateRange!.start)} – ${_formatDate(_dateRange!.end)}',
            ),
            onPressed: () => _pickDateRange(context),
          ),
          if (_dateRange != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.clear, size: 18),
              tooltip: 'Clear date filter',
              onPressed: () => setState(() {
                _dateRange = null;
                _page = 1;
              }),
            ),
          ],
          const Spacer(),
          // Reset all filters
          if (_selectedAction != null || _dateRange != null)
            TextButton.icon(
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: const Text('Reset Filters'),
              onPressed: () => setState(() {
                _selectedAction = null;
                _dateRange = null;
                _page = 1;
              }),
            ),
        ],
      ),
    );
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: AppColors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (range != null) {
      setState(() {
        _dateRange = range;
        _page = 1;
      });
    }
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _buildSkeleton() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: ListSkeleton(
        count: 8,
        itemBuilder: () => const SkeletonBox(height: 48),
      ),
    );
  }

  Widget _buildTable(AuditLogsList logs) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(AppColors.surface),
                columnSpacing: 24,
                columns: const [
                  DataColumn(label: Text('Timestamp')),
                  DataColumn(label: Text('User')),
                  DataColumn(label: Text('Action')),
                  DataColumn(label: Text('Resource Type')),
                  DataColumn(label: Text('Resource ID')),
                ],
                rows: logs.items.map((log) => _buildRow(log)).toList(),
              ),
            ),
          ),
        ),
        PaginationFooter(
          currentPage: _page,
          totalPages: logs.totalPages,
          totalItems: logs.total,
          pageSize: 20,
          onPageChanged: (p) => setState(() => _page = p),
        ),
      ],
    );
  }

  DataRow _buildRow(AuditLog log) {
    return DataRow(
      cells: [
        DataCell(
          Text(
            _formatTimestamp(log.timestamp),
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
        DataCell(
          Text(
            log.userEmail,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        DataCell(_ActionBadge(action: log.action)),
        DataCell(
          Text(
            log.resourceType,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        DataCell(
          SelectableText(
            log.resourceId,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(DateTime dt) {
    final date =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }
}

// ---------------------------------------------------------------------------
// Action badge
// ---------------------------------------------------------------------------

class _ActionBadge extends StatelessWidget {
  final String action;

  const _ActionBadge({required this.action});

  Color get _color {
    switch (action.toUpperCase()) {
      case 'CREATE':
        return AppColors.success;
      case 'UPDATE':
        return AppColors.info;
      case 'DELETE':
        return AppColors.error;
      case 'LOGIN':
      case 'LOGOUT':
        return AppColors.primary;
      case 'APPROVE':
        return AppColors.success;
      case 'REJECT':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Text(
        action,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _color,
        ),
      ),
    );
  }
}
