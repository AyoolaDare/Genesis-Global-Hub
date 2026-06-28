import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_endpoints.dart';

// ---------------------------------------------------------------------------
// Custom exceptions
// ---------------------------------------------------------------------------

class ApiException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  const ApiException({
    required this.message,
    this.code,
    this.statusCode,
  });

  @override
  String toString() => 'ApiException($statusCode): $message';

  /// Extracts an [ApiException] from a caught error, unwrapping a
  /// [DioException] wrapper if present.
  static ApiException? from(dynamic e) {
    if (e is ApiException) return e;
    if (e is DioException && e.error is ApiException) return e.error as ApiException;
    return null;
  }
}

class UnauthorizedException extends ApiException {
  const UnauthorizedException({super.message = 'Unauthorized', super.code})
      : super(statusCode: 401);
}

class ForbiddenException extends ApiException {
  const ForbiddenException({super.message = 'Access denied', super.code})
      : super(statusCode: 403);
}

class NotFoundException extends ApiException {
  const NotFoundException({super.message = 'Resource not found', super.code})
      : super(statusCode: 404);
}

class ValidationException extends ApiException {
  final Map<String, List<String>> fieldErrors;

  const ValidationException({
    super.message = 'Validation failed',
    super.code,
    this.fieldErrors = const {},
  }) : super(statusCode: 422);
}

class ServerException extends ApiException {
  const ServerException({super.message = 'Server error', super.code})
      : super(statusCode: 500);
}

// ---------------------------------------------------------------------------
// Auth interceptor
// ---------------------------------------------------------------------------

class _AuthInterceptor extends Interceptor {
  final FlutterSecureStorage _storage;
  final Dio _dio;
  bool _isRefreshing = false;
  final List<RequestOptions> _pendingRequests = [];

  _AuthInterceptor(this._storage, this._dio);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storage.read(key: 'access_token');
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    options.headers['Content-Type'] = 'application/json';
    options.headers['Accept'] = 'application/json';
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401) {
      if (_isRefreshing) {
        _pendingRequests.add(err.requestOptions);
        return;
      }
      _isRefreshing = true;
      try {
        final refreshToken = await _storage.read(key: 'refresh_token');
        if (refreshToken == null) {
          await _clearTokensAndRedirect();
          handler.next(err);
          return;
        }
        final refreshDio = Dio(BaseOptions(baseUrl: ApiEndpoints.baseUrl));
        final response = await refreshDio.post(
          ApiEndpoints.refreshToken,
          data: {'refresh_token': refreshToken},
        );
        final newToken = response.data['data']['access_token'] as String;
        final newRefresh =
            response.data['data']['refresh_token'] as String? ?? refreshToken;
        await _storage.write(key: 'access_token', value: newToken);
        await _storage.write(key: 'refresh_token', value: newRefresh);

        // Retry original request
        final opts = err.requestOptions;
        opts.headers['Authorization'] = 'Bearer $newToken';
        final retryResponse = await _dio.fetch(opts);

        // Retry pending requests
        for (final pending in _pendingRequests) {
          pending.headers['Authorization'] = 'Bearer $newToken';
          await _dio.fetch(pending);
        }
        _pendingRequests.clear();
        handler.resolve(retryResponse);
      } catch (_) {
        await _clearTokensAndRedirect();
        handler.next(err);
      } finally {
        _isRefreshing = false;
      }
    } else {
      handler.next(err);
    }
  }

  Future<void> _clearTokensAndRedirect() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }
}

// ---------------------------------------------------------------------------
// Response interceptor
// ---------------------------------------------------------------------------

class _ResponseInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    ApiException apiError;

    if (response != null) {
      final data = response.data;
      String message = 'An error occurred';
      String? code;

      if (data is Map) {
        final error = data['error'];
        if (error is Map) {
          message = error['message']?.toString() ?? message;
          code = error['code']?.toString();
        } else {
          message = data['message']?.toString() ?? message;
        }
      }

      switch (response.statusCode) {
        case 401:
          apiError = UnauthorizedException(message: message, code: code);
        case 403:
          apiError = ForbiddenException(message: message, code: code);
        case 404:
          apiError = NotFoundException(message: message, code: code);
        case 422:
          Map<String, List<String>> fieldErrors = {};
          if (data is Map && data['errors'] is Map) {
            final errs = data['errors'] as Map;
            errs.forEach((k, v) {
              fieldErrors[k.toString()] = v is List
                  ? v.map((e) => e.toString()).toList()
                  : [v.toString()];
            });
          }
          apiError = ValidationException(
              message: message, code: code, fieldErrors: fieldErrors);
        case 500:
        case 502:
        case 503:
          apiError = ServerException(message: message, code: code);
        default:
          apiError = ApiException(
            message: message,
            code: code,
            statusCode: response.statusCode,
          );
      }
    } else {
      apiError = const ApiException(
        message: 'Network error. Please check your internet connection.',
        statusCode: null,
      );
    }

    // Use handler.reject() — the correct Dio pattern.
    // Throwing from onError can be swallowed by Dio's interceptor machinery.
    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: apiError,
        stackTrace: err.stackTrace,
        message: apiError.message,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dio provider
// ---------------------------------------------------------------------------

final dioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(
    Provider((ref) => const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    )),
  );

  final dio = Dio(
    BaseOptions(
      baseUrl: ApiEndpoints.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  // Add auth interceptor
  dio.interceptors.add(_AuthInterceptor(storage, dio));

  // Add response interceptor
  dio.interceptors.add(_ResponseInterceptor());

  // Debug logging
  if (kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        error: true,
        logPrint: (obj) => debugPrint(obj.toString()),
      ),
    );
  }

  return dio;
});
