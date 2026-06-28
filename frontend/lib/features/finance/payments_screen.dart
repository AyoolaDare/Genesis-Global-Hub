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
import '../../providers/sponsor_provider.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final paymentsListProvider =
    FutureProvider.family<PaymentsList, Map<String, dynamic>>(
        (ref, params) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(
    ApiEndpoints.payments,
    queryParameters: {
      'page': params['page'] ?? 1,
      if (params['status'] != null) 'status': params['status'],
      if (params['from'] != null) 'from': params['from'],
      if (params['to'] != null) 'to': params['to'],
      if (params['method'] != null) 'method': params['method'],
    },
  );
  return PaymentsList.fromJson(response.data);
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  int _page = 1;
  String? _status;
  String? _method;
  DateTime? _from;
  DateTime? _to;

  Map<String, dynamic> get _params => {
        'page': _page,
        if (_status != null) 'status': _status,
        if (_method != null) 'method': _method,
        if (_from != null) 'from': _from!.toIso8601String().split('T').first,
        if (_to != null) 'to': _to!.toIso8601String().split('T').first,
      };

  @override
  Widget build(BuildContext context) {
    final paymentsAsync = ref.watch(paymentsListProvider(_params));

    return ShellLayout(
      title: 'Payments',
      child: Column(
        children: [
          _buildFilters(context),
          Expanded(
            child: paymentsAsync.when(
              loading: () => Padding(
                padding: const EdgeInsets.all(24),
                child: ListSkeleton(
                  count: 6,
                  itemBuilder: () => const SkeletonBox(height: 60),
                ),
              ),
              error: (e, _) => ErrorState(
                message: e.toString().contains('403')
                    ? 'Access Denied'
                    : 'Failed to load payments',
                onRetry: () =>
                    ref.invalidate(paymentsListProvider(_params)),
              ),
              data: (data) => data.items.isEmpty
                  ? EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No payments found',
                      subtitle: 'No payments match the current filters.',
                      actionLabel: 'Clear Filters',
                      onAction: _clearFilters,
                    )
                  : _buildContent(data),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            width: 160,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
              color: AppColors.white,
            ),
            child: DropdownButton<String>(
              value: _method,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              hint: const Text('All Methods',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              items: const [
                DropdownMenuItem<String>(
                    value: null, child: Text('All Methods')),
                DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                DropdownMenuItem(
                    value: 'TRANSFER', child: Text('Transfer')),
                DropdownMenuItem(value: 'CHEQUE', child: Text('Cheque')),
                DropdownMenuItem(value: 'POS', child: Text('POS')),
              ],
              onChanged: (v) => setState(() {
                _method = v;
                _page = 1;
              }),
            ),
          ),
          _DateRangePicker(
            from: _from,
            to: _to,
            onFromPicked: (d) => setState(() {
              _from = d;
              _page = 1;
            }),
            onToPicked: (d) => setState(() {
              _to = d;
              _page = 1;
            }),
          ),
          if (_method != null || _from != null || _to != null)
            TextButton.icon(
              icon: const Icon(Icons.clear, size: 16),
              label: const Text('Clear'),
              onPressed: _clearFilters,
            ),
        ],
      ),
    );
  }

  Widget _buildContent(PaymentsList data) {
    // Summary stats
    final total = data.items.fold<double>(0, (sum, p) => sum + p.amount);

    return Column(
      children: [
        _SummaryBar(total: total, count: data.total),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _PaymentsTable(payments: data.items),
          ),
        ),
        PaginationFooter(
          currentPage: _page,
          totalPages: data.totalPages,
          totalItems: data.total,
          pageSize: 20,
          onPageChanged: (p) => setState(() => _page = p),
        ),
      ],
    );
  }

  void _clearFilters() {
    setState(() {
      _status = null;
      _method = null;
      _from = null;
      _to = null;
      _page = 1;
    });
  }
}

// ---------------------------------------------------------------------------
// Summary bar
// ---------------------------------------------------------------------------

class _SummaryBar extends StatelessWidget {
  final double total;
  final int count;

  const _SummaryBar({required this.total, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      color: AppColors.primary.withOpacity(0.04),
      child: Row(
        children: [
          _SummaryStat(
            label: 'Total Payments',
            value: '$count',
            icon: Icons.receipt_long_outlined,
            color: AppColors.primary,
          ),
          const SizedBox(width: 32),
          _SummaryStat(
            label: 'Total Amount',
            value: _formatCurrency(total),
            icon: Icons.account_balance_wallet_outlined,
            color: AppColors.success,
          ),
        ],
      ),
    );
  }

  String _formatCurrency(double amount) {
    if (amount >= 1000000) {
      return '₦${(amount / 1000000).toStringAsFixed(2)}M';
    } else if (amount >= 1000) {
      return '₦${(amount / 1000).toStringAsFixed(1)}K';
    }
    return '₦${amount.toStringAsFixed(0)}';
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Payments table
// ---------------------------------------------------------------------------

class _PaymentsTable extends StatelessWidget {
  final List<Payment> payments;

  const _PaymentsTable({required this.payments});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor:
              MaterialStateProperty.all(AppColors.surface),
          columns: const [
            DataColumn(label: Text('Sponsor')),
            DataColumn(label: Text('Amount')),
            DataColumn(label: Text('Method')),
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Reference')),
          ],
          rows: payments
              .map(
                (p) => DataRow(
                  cells: [
                    DataCell(
                      Text(
                        p.sponsorName ?? '—',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        '₦${p.amount.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                    DataCell(_MethodBadge(method: p.method)),
                    DataCell(Text(
                      '${p.paymentDate.day}/${p.paymentDate.month}/${p.paymentDate.year}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    )),
                    DataCell(Text(p.reference ?? '—',
                        style: const TextStyle(fontSize: 13))),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _MethodBadge extends StatelessWidget {
  final String method;

  const _MethodBadge({required this.method});

  Color get _color {
    switch (method.toUpperCase()) {
      case 'CASH':
        return AppColors.success;
      case 'TRANSFER':
        return AppColors.info;
      case 'CHEQUE':
        return AppColors.warning;
      case 'POS':
        return AppColors.secondary;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        method,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date range picker widget
// ---------------------------------------------------------------------------

class _DateRangePicker extends StatelessWidget {
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<DateTime> onFromPicked;
  final ValueChanged<DateTime> onToPicked;

  const _DateRangePicker({
    required this.from,
    required this.to,
    required this.onFromPicked,
    required this.onToPicked,
  });

  String _fmt(DateTime? d) => d != null
      ? '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}'
      : '';

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PickerField(
          label: 'From',
          value: _fmt(from),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: from ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (picked != null) onFromPicked(picked);
          },
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child:
              Text('—', style: TextStyle(color: AppColors.textSecondary)),
        ),
        _PickerField(
          label: 'To',
          value: _fmt(to),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: to ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (picked != null) onToPicked(picked);
          },
        ),
      ],
    );
  }
}

class _PickerField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _PickerField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
          color: AppColors.white,
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                value.isNotEmpty ? value : label,
                style: TextStyle(
                  fontSize: 13,
                  color: value.isNotEmpty
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
