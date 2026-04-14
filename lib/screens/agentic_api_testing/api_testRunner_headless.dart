import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiTestRunner {
  ApiTestRunner(
    this.baseUrl, {
    required this.logger,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final void Function(String) logger;
  final http.Client _client;

  final Map<String, String> env = {};
  final String uniqueId =
      (DateTime.now().millisecondsSinceEpoch % 1000000).toString();

  void dispose() => _client.close();

  String _sub(String text) {
    var result = text.replaceAll('{{unique_id}}', uniqueId);
    env.forEach((k, v) => result = result.replaceAll('{{$k}}', v));
    result = result.replaceAll('{{test_email}}', 'user_$uniqueId@example.com');
    result = result.replaceAll('{{test_password}}', 'TestPass123!');
    return result;
  }

  dynamic _walk(dynamic v) {
    if (v is String) return _sub(v);
    if (v is Map) return v.map((k, val) => MapEntry(k, _walk(val)));
    if (v is List) return v.map(_walk).toList();
    return v;
  }

  Future<http.Response> _send(String method, String url,
      Map<String, String> headers, String? body) async {
    final uri = Uri.parse(url);
    switch (method.toUpperCase()) {
      case 'POST':
        return await _client.post(uri, headers: headers, body: body);
      case 'PATCH':
        return await _client.patch(uri, headers: headers, body: body);
      case 'PUT':
        return await _client.put(uri, headers: headers, body: body);
      case 'DELETE':
        return await _client.delete(uri, headers: headers, body: body);
      case 'HEAD':
        return await _client.head(uri, headers: headers);
      case 'GET':
      default:
        return await _client.get(uri, headers: headers);
    }
  }

  Future<void> runSuite(Map<String, dynamic> suite) async {
    final tests = (suite['tests'] as List?) ?? const [];
    logger('[DEBUG] Test started. Found ${tests.length} tests in payload.');

    for (final t in tests) {
      final name = (t['name'] ?? 'unnamed').toString();
      logger('[DEBUG] test: $name');

      final method = (t['method'] ?? 'GET').toString();
      final path = _sub((t['path'] ?? '/').toString());
      final requiresAuth = (t['requires_auth'] ?? false) == true;

      final headers = <String, String>{'Content-Type': 'application/json'};
      if (t['headers'] is Map) {
        (t['headers'] as Map).forEach((k, v) {
          if (v != null) headers[k.toString()] = v.toString();
        });
      }

      if (requiresAuth) {
        final token = env['access_token'];
        if (token == null || token.isEmpty) {
          logger('[SKIP] $name: No access token available.');
          continue;
        }
        headers['Authorization'] = 'Bearer $token';
      }

      final body = t['body'] != null ? jsonEncode(_walk(t['body'])) : null;
      final url = '$baseUrl$path';

      logger('HTTP $method to $url');

      try {
        final res = await _send(method, url, headers, body);
        logger('[DEBUG] Received HTTP  ${res.statusCode}');
        _validate(t as Map, res);
      } catch (e) {
        logger('[FAIL] $name: Request failed - $e');
      }
    }
    logger('[DEBUG] Test engine finished sequence.');
  }

  void _validate(Map test, http.Response res) {
    final name = (test['name'] ?? 'unnamed').toString();
    final expected = (test['expected_status'] as num?)?.toInt() ?? 200;
    final got = res.statusCode;

    if (got == expected) {
      logger('[PASS] $name ($got)');

      logger('       Response: ${res.body}');

      final extract = test['extract_to_env'];
      if (extract is Map && res.body.isNotEmpty) {
        try {
          final data = jsonDecode(res.body);
          extract.forEach((apiKey, envKey) {
            final v = (data is Map) ? data[apiKey] : null;
            if (v != null) env[envKey.toString()] = v.toString();
          });
        } catch (_) {}
      }
      return;
    }

    logger(name);
    logger('       Expected: $expected, Got: $got');
    logger('       Response: ${res.body}');
  }
}
