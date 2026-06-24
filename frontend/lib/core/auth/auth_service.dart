import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api/api_endpoints.dart';
import 'user_model.dart';
import 'package:dio/dio.dart';

const _accessTokenKey = 'access_token';
const _refreshTokenKey = 'refresh_token';

class AuthService {
  final FlutterSecureStorage _storage;
  final Dio _dio;

  AuthService(this._storage, this._dio);

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _dio.post(
      ApiEndpoints.login,
      data: {'email': email, 'password': password},
    );
    final data = response.data['data'];
    final accessToken = data['access_token'] as String;
    final refreshToken = data['refresh_token'] as String;
    await saveTokens(accessToken, refreshToken);
    final payload = decodeJwtPayload(accessToken);
    return payload;
  }

  Future<void> logout() async {
    try {
      final token = await getAccessToken();
      if (token != null) {
        await _dio.post(ApiEndpoints.logout);
      }
    } catch (_) {
      // Ignore errors on logout
    } finally {
      await clearTokens();
    }
  }

  Future<String?> refreshAccessToken() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null) return null;
    try {
      final response = await _dio.post(
        ApiEndpoints.refreshToken,
        data: {'refresh_token': refreshToken},
      );
      final data = response.data['data'];
      final newAccessToken = data['access_token'] as String;
      final newRefreshToken = data['refresh_token'] as String? ?? refreshToken;
      await saveTokens(newAccessToken, newRefreshToken);
      return newAccessToken;
    } catch (_) {
      await clearTokens();
      return null;
    }
  }

  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<String?> getAccessToken() async {
    return await _storage.read(key: _accessTokenKey);
  }

  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _refreshTokenKey);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  Future<CurrentUser?> getCurrentUser() async {
    final token = await getAccessToken();
    if (token == null) return null;
    try {
      final payload = decodeJwtPayload(token);
      final user = CurrentUser.fromJwtPayload(payload);
      if (user.isExpired) {
        final newToken = await refreshAccessToken();
        if (newToken == null) return null;
        final newPayload = decodeJwtPayload(newToken);
        return CurrentUser.fromJwtPayload(newPayload);
      }
      return user;
    } catch (_) {
      return null;
    }
  }

  Future<void> forgotPassword(String email) async {
    await _dio.post(
      ApiEndpoints.forgotPassword,
      data: {'email': email},
    );
  }
}
