import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api/api_client.dart';
import 'auth_service.dart';
import 'user_model.dart';

// ---------------------------------------------------------------------------
// Infrastructure providers
// ---------------------------------------------------------------------------

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
});

final authServiceProvider = Provider<AuthService>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final dio = ref.watch(dioProvider);
  return AuthService(storage, dio);
});

// ---------------------------------------------------------------------------
// Auth state
// ---------------------------------------------------------------------------

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final CurrentUser? user;
  final String? error;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = true,
    this.user,
    this.error,
  });

  UserRole get role => user?.role ?? UserRole.unknown;

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    CurrentUser? user,
    String? error,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      error: error,
    );
  }
}

// ---------------------------------------------------------------------------
// Auth notifier
// ---------------------------------------------------------------------------

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;

  AuthNotifier(this._authService) : super(const AuthState()) {
    checkAuth();
  }

  Future<void> checkAuth() async {
    state = state.copyWith(isLoading: true);
    try {
      final user = await _authService.getCurrentUser();
      if (user != null) {
        state = AuthState(
          isAuthenticated: true,
          isLoading: false,
          user: user,
        );
      } else {
        state = const AuthState(isAuthenticated: false, isLoading: false);
      }
    } catch (e) {
      state = const AuthState(isAuthenticated: false, isLoading: false);
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final payload = await _authService.login(email, password);
      final user = CurrentUser.fromJwtPayload(payload);
      state = AuthState(
        isAuthenticated: true,
        isLoading: false,
        user: user,
      );
      return true;
    } on Exception catch (e) {
      state = AuthState(
        isAuthenticated: false,
        isLoading: false,
        error: _parseError(e),
      );
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    await _authService.logout();
    state = const AuthState(isAuthenticated: false, isLoading: false);
  }

  String _parseError(dynamic e) {
    final api = ApiException.from(e);
    if (api != null) {
      if (api.statusCode == 401) return 'Invalid email or password. Please try again.';
      if (api.message.isNotEmpty) return api.message;
    }
    final msg = e.toString();
    if (msg.contains('SocketException') || msg.contains('Connection')) {
      return 'Unable to connect. Please check your internet connection.';
    }
    return 'Login failed. Please try again later.';
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthNotifier(authService);
});

final currentUserProvider = Provider<CurrentUser?>((ref) {
  return ref.watch(authProvider).user;
});

final currentRoleProvider = Provider<UserRole>((ref) {
  return ref.watch(authProvider).role;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});
