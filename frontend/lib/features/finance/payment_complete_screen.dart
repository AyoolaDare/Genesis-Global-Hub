import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/theme/app_colors.dart';

class PaymentCompleteScreen extends ConsumerStatefulWidget {
  const PaymentCompleteScreen({super.key});

  @override
  ConsumerState<PaymentCompleteScreen> createState() =>
      _PaymentCompleteScreenState();
}

class _PaymentCompleteScreenState extends ConsumerState<PaymentCompleteScreen> {
  bool _started = false;
  bool _loading = true;
  String? _txRef;
  String? _status;
  String? _message;
  double? _amount;
  String? _currency;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _txRef = _extractTxRef();
    _verifyPayment();
  }

  @override
  Widget build(BuildContext context) {
    final status = (_status ?? '').toLowerCase();
    final isSuccess = status == 'successful' || status == 'completed';
    final isPending = status == 'pending' || status == 'unknown';
    final color = isSuccess
        ? AppColors.success
        : isPending
            ? AppColors.warning
            : AppColors.error;
    final icon = isSuccess
        ? Icons.check_circle_outline
        : isPending
            ? Icons.hourglass_top_outlined
            : Icons.error_outline;
    final title = _loading
        ? 'Verifying payment'
        : isSuccess
            ? 'Payment received'
            : isPending
                ? 'Payment pending'
                : 'Payment not completed';

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.cardShadow,
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : Icon(icon, color: color, size: 34),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  _message ?? 'Please wait while we confirm your payment.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                if (_txRef != null || _amount != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_txRef != null)
                          _DetailLine(label: 'Reference', value: _txRef!),
                        if (_amount != null)
                          _DetailLine(
                            label: 'Amount',
                            value:
                                '${_currency ?? 'NGN'} ${_amount!.toStringAsFixed(0)}',
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (!_loading && !isSuccess)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Check Again'),
                        onPressed: _verifyPayment,
                      ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.login, size: 18),
                      label: const Text('Go to Login'),
                      onPressed: () => context.go('/login'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _extractTxRef() {
    String? fromParams(Map<String, String> params) {
      final value = params['tx_ref'] ?? params['txRef'];
      return value != null && value.trim().isNotEmpty ? value.trim() : null;
    }

    final routeValue = fromParams(GoRouterState.of(context).uri.queryParameters);
    if (routeValue != null) return routeValue;

    final baseValue = fromParams(Uri.base.queryParameters);
    if (baseValue != null) return baseValue;

    final fragment = Uri.base.fragment;
    if (fragment.contains('?')) {
      final parsed = Uri.parse(fragment.startsWith('/') ? fragment : '/$fragment');
      return fromParams(parsed.queryParameters);
    }

    return null;
  }

  Future<void> _verifyPayment() async {
    final txRef = _txRef;
    if (txRef == null || txRef.isEmpty) {
      setState(() {
        _loading = false;
        _status = 'missing_reference';
        _message = 'Payment reference was not found in the return URL.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = 'Please wait while we confirm your payment.';
    });

    try {
      final dio = ref.read(dioProvider);
      final response =
          await dio.post(ApiEndpoints.verifyFlutterwaveReturn(txRef));
      final body = Map<String, dynamic>.from(response.data as Map);
      final data = Map<String, dynamic>.from((body['data'] ?? {}) as Map);

      setState(() {
        _loading = false;
        _status = data['status']?.toString();
        _message = body['message']?.toString() ??
            data['message']?.toString() ??
            'Payment status retrieved.';
        _amount = data['amount'] != null
            ? double.tryParse(data['amount'].toString())
            : null;
        _currency = data['currency']?.toString();
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _status = 'error';
        _message = ApiException.from(e)?.message ??
            'Could not verify the payment. Please try again.';
      });
    }
  }
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _DetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
