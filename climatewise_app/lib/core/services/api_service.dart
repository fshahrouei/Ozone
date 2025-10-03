import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../constants/app_constants.dart';

/// ApiService
///
/// A lightweight HTTP client wrapper for making API calls (GET, POST, PUT, DELETE).
/// - Supports optional SSL certificate ignoring (for local/self-signed servers).
/// - Centralizes response parsing and error handling.
/// - Ensures JSON requests/responses with appropriate headers.
class ApiService {
  final String baseUrl;
  final bool ignoreSSLError;

  ApiService({this.baseUrl = BASE_API_URL, this.ignoreSSLError = false});

  /// Returns an HTTP client.
  /// - If [ignoreSSLError] is true, creates a client that accepts all certificates.
  http.Client get _client {
    if (!ignoreSSLError) return http.Client();
    final ioc = HttpClient()
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
    return IOClient(ioc);
  }

  /// Executes an HTTP GET request to the given [endpoint].
  Future<dynamic> get(String endpoint) async {
    final response = await _client.get(
      Uri.parse('$baseUrl$endpoint'),
      headers: {
        'Accept': 'application/json',
      },
    );
    return _processResponse(response);
  }

  /// Executes an HTTP POST request with a JSON-encoded [body].
  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    final response = await _client.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(body),
    );
    return _processResponse(response);
  }

  /// Executes an HTTP PUT request with a JSON-encoded [body].
  Future<dynamic> put(String endpoint, Map<String, dynamic> body) async {
    final response = await _client.put(
      Uri.parse('$baseUrl$endpoint'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(body),
    );
    return _processResponse(response);
  }

  /// Executes an HTTP DELETE request.
  Future<dynamic> delete(String endpoint) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl$endpoint'),
      headers: {
        'Accept': 'application/json',
      },
    );
    return _processResponse(response);
  }

  /// Processes the HTTP [response].
  /// - Attempts to parse JSON if the body is not empty.
  /// - Throws an [Exception] for non-2xx responses with detailed information.
  dynamic _processResponse(http.Response response) {
    final text = response.body;
    Map<String, dynamic>? json;

    try {
      if (text.isNotEmpty) {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          json = decoded;
        }
      }
    } catch (_) {
      // Non-JSON responses (e.g., HTML or plain text) are ignored here.
    }

    final ok = response.statusCode >= 200 && response.statusCode < 300;

    if (ok) {
      // Success: expect JSON response
      if (json != null) return json;
      throw Exception('API Success but non-JSON body (length=${text.length}).');
    } else {
      // Error: return JSON error if available, otherwise return raw text
      if (json != null) {
        throw Exception('API Error: ${response.statusCode} - $json');
      } else {
        throw Exception('API Error: ${response.statusCode} - $text');
      }
    }
  }
}
