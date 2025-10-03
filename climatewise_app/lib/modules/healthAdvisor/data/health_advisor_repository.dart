// Repository for HealthAdvisor APIs: store (POST), index (GET), destroy (DELETE).
// Comments & strings are in English.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/services/api_service.dart';
import '../../../core/utils/guest_user_manager.dart';
import '../models/health_form.dart';
import '../models/health_result_summary.dart';

class ApiException implements Exception {
  final String message;
  final int status;
  const ApiException(this.message, {this.status = 500});

  @override
  String toString() => 'ApiException($status): $message';
}

class ValidationException extends ApiException {
  final Map<String, List<String>> fieldErrors;

  const ValidationException({
    required this.fieldErrors,
    String message = 'Validation error',
    int status = 422,
  }) : super(message, status: status);

  @override
  String toString() => 'ValidationException($status): $fieldErrors';
}

class PagedResult<T> {
  final List<T> items;
  final int page;
  final int perPage;
  final int total;
  final int lastPage;
  final String? sort;

  const PagedResult({
    required this.items,
    required this.page,
    required this.perPage,
    required this.total,
    required this.lastPage,
    this.sort,
  });
}

class HealthAdvisorRepository {
  final ApiService api = ApiService(ignoreSSLError: true);

  String getEndpoint(String action, [dynamic id]) {
    switch (action) {
      case 'store':
        return "frontend/health-advisor/store";
      case 'index':
        return "frontend/health-advisor/index";
      case 'destroy':
        if (id == null) throw ArgumentError('destroy needs an id');
        return "frontend/health-advisor/destroy/$id";
      default:
        throw UnimplementedError('Unknown endpoint: $action');
    }
  }

  // ---------------------------- STORE ----------------------------

  Future<HealthForm> submitForm(HealthForm form) async {
    final String clientId = await GuestUserManager.getOrCreateUserId();

    // Collect extra device info
    final String? fcmToken = await FirebaseMessaging.instance.getToken();
    final String platform = Platform.isAndroid ? "android" : (Platform.isIOS ? "ios" : "other");
    final String appVersion = (await PackageInfo.fromPlatform()).version;

    final Map<String, dynamic> payload = form.copyWith(clientId: clientId).toJson()
      ..addAll({
        'fcm_token': fcmToken,
        'platform': platform,
        'app_version': appVersion,
      });

    final String endpoint = getEndpoint('store');
    _debugFullUrl(method: 'POST', endpointOrUrl: endpoint);

    if (kDebugMode) {
      debugPrint('🛰️ [Repo] POST $endpoint');
      debugPrint('🛰️ Payload: ${const JsonEncoder.withIndent('  ').convert(payload)}');
    }

    dynamic raw;
    try {
      raw = await api.post(endpoint, payload);
    } catch (e) {
      throw ApiException('Network error: $e', status: 500);
    }

    final _NormalizedResp nr = _normalizeResponse(raw);
    final body = nr.body;
    final succeed = body['succeed'] == true;
    final status = nr.status ?? (body['status'] as int? ?? 200);
    final reason = (body['reason'] ?? '') as String? ?? '';
    final message = (body['message'] ?? '') as String? ?? '';

    if (succeed && status == 201) {
      final data = (body['data'] ?? {}) as Map<String, dynamic>;
      data['client_id'] = data['client_id'] ?? clientId;
      return HealthForm.fromJson(data);
    }

    if (status == 422 || reason == 'invalid' || body.containsKey('errors')) {
      final rawErrors = (body['errors'] ?? {}) as Map<String, dynamic>;
      final Map<String, List<String>> fieldErrors = {};
      rawErrors.forEach((key, val) {
        if (val is List) {
          fieldErrors[key] = val.map((e) => '$e').toList();
        } else if (val is String) {
          fieldErrors[key] = [val];
        }
      });
      throw ValidationException(
        fieldErrors: fieldErrors,
        message: message.isNotEmpty ? message : 'Validation error',
        status: status == 0 ? 422 : status,
      );
    }

    throw ApiException(message.isNotEmpty ? message : 'Server error', status: status == 0 ? 500 : status);
  }

  // ---------------------------- INDEX ----------------------------

  Future<PagedResult<HealthResultSummary>> fetchSavedPoints({
    String? uuid,
    String? search,
    bool hasLocation = false,
    String sort = '-received_at',
    int page = 1,
    int perPage = 10,
  }) async {
    final String endpoint = getEndpoint('index');

    final Map<String, dynamic> query = {
      if (uuid != null && uuid.trim().isNotEmpty) 'uuid': uuid.trim(),
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (hasLocation) 'has_location': 1,
      if (sort.isNotEmpty) 'sort': sort,
      'page': page,
      'per_page': perPage.clamp(1, 50),
    };

    final qp = query.map((k, v) => MapEntry(k, '$v'));
    final qs = Uri(queryParameters: qp).query;
    final urlPathWithQuery = qs.isEmpty ? endpoint : '$endpoint?$qs';

    _debugFullUrl(method: 'GET', endpointOrUrl: urlPathWithQuery);
    if (kDebugMode) debugPrint('🛰️ [Repo] GET $urlPathWithQuery');

    dynamic raw;
    try {
      raw = await api.get(urlPathWithQuery);
    } catch (e) {
      throw ApiException('Network error: $e', status: 500);
    }

    final _NormalizedResp nr = _normalizeResponse(raw);
    final body = nr.body;
    final succeed = body['succeed'] == true;
    final status = nr.status ?? (body['status'] as int? ?? 200);
    final message = (body['message'] ?? '') as String? ?? '';

    if (!succeed || status != 200) {
      if (status == 422 || body.containsKey('errors')) {
        final rawErrors = (body['errors'] ?? {}) as Map<String, dynamic>;
        final Map<String, List<String>> fieldErrors = {};
        rawErrors.forEach((key, val) {
          if (val is List) {
            fieldErrors[key] = val.map((e) => '$e').toList();
          } else if (val is String) {
            fieldErrors[key] = [val];
          }
        });
        throw ValidationException(
          fieldErrors: fieldErrors,
          message: message.isNotEmpty ? message : 'Validation error',
          status: status == 0 ? 422 : status,
        );
      }
      throw ApiException(message.isNotEmpty ? message : 'Failed to fetch records', status: status == 0 ? 500 : status);
    }

    final items = HealthResultSummary.listFromIndexResponse(body);
    final meta = (body['meta'] is Map) ? Map<String, dynamic>.from(body['meta'] as Map) : const {};
    final pageNum = int.tryParse('${meta['page'] ?? page}') ?? page;
    final per = int.tryParse('${meta['per_page'] ?? perPage}') ?? perPage;
    final total = int.tryParse('${meta['total'] ?? items.length}') ?? items.length;
    final last = int.tryParse('${meta['last_page'] ?? 1}') ?? 1;
    final sortApplied = (meta['sort'] is String) ? meta['sort'] as String : null;

    return PagedResult<HealthResultSummary>(
      items: items,
      page: pageNum,
      perPage: per,
      total: total,
      lastPage: last,
      sort: sortApplied,
    );
  }

  // ---------------------------- DESTROY ----------------------------

  Future<void> deleteById(int id) async {
    if (id <= 0) throw const ApiException('Invalid id', status: 422);

    final String endpoint = getEndpoint('destroy', id);
    _debugFullUrl(method: 'DELETE', endpointOrUrl: endpoint);
    if (kDebugMode) debugPrint('🗑️ [Repo] DELETE $endpoint');

    dynamic raw;
    try {
      raw = await api.delete(endpoint);
    } catch (e) {
      throw ApiException('Network error: $e', status: 500);
    }

    final _NormalizedResp nr = _normalizeResponse(raw);
    final body = nr.body;
    final succeed = body['succeed'] == true;
    final status = nr.status ?? (body['status'] as int? ?? 200);
    final message = (body['message'] ?? '') as String? ?? '';

    if (!succeed || status != 200) {
      if (status == 404) throw ApiException('Record not found', status: 404);
      if (status == 422 || body.containsKey('errors')) {
        throw ApiException(message.isNotEmpty ? message : 'Invalid request', status: 422);
      }
      throw ApiException(message.isNotEmpty ? message : 'Failed to delete record', status: status == 0 ? 500 : status);
    }
  }

  // ---------------------------- Helpers ----------------------------

  void _debugFullUrl({required String method, required String endpointOrUrl}) {
    if (!kDebugMode) return;
    String base = '';
    try {
      final dyn = (api as dynamic);
      final b1 = dyn.baseUrl;
      if (b1 is String && b1.isNotEmpty) {
        base = b1;
      } else {
        final getter = dyn.getBaseUrl;
        if (getter is Function) {
          final b2 = getter();
          if (b2 is String && b2.isNotEmpty) base = b2;
        }
      }
    } catch (_) {}

    String full;
    if (base.isNotEmpty) {
      if (base.endsWith('/') && endpointOrUrl.startsWith('/')) {
        full = base + endpointOrUrl.substring(1);
      } else if (!base.endsWith('/') && !endpointOrUrl.startsWith('/')) {
        full = '$base/$endpointOrUrl';
      } else {
        full = '$base$endpointOrUrl';
      }
    } else {
      full = endpointOrUrl;
    }

    debugPrint('🔎 [$method] FULL URL => $full');
  }

  _NormalizedResp _normalizeResponse(dynamic raw) {
    int? httpStatus;
    Map<String, dynamic>? body;

    if (raw is Map<String, dynamic>) {
      if (raw.containsKey('statusCode') && raw.containsKey('json')) {
        httpStatus = raw['statusCode'] is int ? raw['statusCode'] as int : null;
        final dynJson = raw['json'];
        if (dynJson is Map<String, dynamic>) {
          body = dynJson;
        } else {
          throw const ApiException('Unexpected response format (json)', status: 500);
        }
      } else {
        body = raw;
        if (body['status'] is int) httpStatus = body['status'] as int;
      }
    } else {
      throw const ApiException('Unexpected response (not JSON map)', status: 500);
    }

    return _NormalizedResp(status: httpStatus, body: body);
  }
}

class _NormalizedResp {
  final int? status;
  final Map<String, dynamic> body;
  const _NormalizedResp({required this.status, required this.body});
}
