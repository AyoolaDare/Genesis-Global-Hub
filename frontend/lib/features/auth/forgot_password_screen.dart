import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/theme/app_colors.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final authService = ref.read(authServiceProvider);
      await authService.forgotPassword(_emailController.text.trim());
      if (mounted) setState(() => _emailSent = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to send reset email. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _emailSent ? _buildSuccess() : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_reset_outlined,
              size: 36,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Forgot Password?',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your email and we\'ll send you a link to reset your password.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error.withOpacity(0.3)),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: AppColors.error, fontSize: 14),
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email Address',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (val) {
              if (val == null || val.isEmpty) return 'Email is required';
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(val)) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleSubmit,
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: AppColors.white, strokeWidth: 2.5),
                    )
                  : const Text('Send Reset Link'),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => context.go('/login'),
            child: const Text('Back to Login'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mark_email_read_outlined,
            size: 72, color: AppColors.success),
        const SizedBox(height: 24),
        Text(
          'Check your email',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'We sent a password reset link to ${_emailController.text}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () => context.go('/login'),
          child: const Text('Back to Login'),
        ),
      ],
    );
  }
}
