import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:better_networking/better_networking.dart';

typedef ManualReviewHandler = Future<HttpRequestModel?> Function(
    HttpRequestModel request, String description);

class ApiTestRunner {
  final ManualReviewHandler? onManualReview;
  ApiTestRunner(this.baseUrl,
      {required this.logger, http.Client? client, this.onManualReview})
      : _client = client ?? http.Client();

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

  HTTPVerb _verb(String m) {
    switch (m.toUpperCase()) {
      case 'POST':
        return HTTPVerb.post;
      case 'PATCH':
        return HTTPVerb.patch;
      case 'PUT':
        return HTTPVerb.put;
      case 'DELETE':
        return HTTPVerb.delete;
      case 'HEAD':
        return HTTPVerb.head;
      case 'OPTIONS':
        return HTTPVerb.options;
      default:
        return HTTPVerb.get;
    }
  }

  Future<HttpResponseModel> _send(HttpRequestModel req) async {
    final uri = Uri.parse(req.url);
    final headers = req.headersMap;
    final body = req.body;

    final sw = Stopwatch()..start();
    late http.Response raw;

    switch (req.method) {
      case HTTPVerb.post:
        raw = await _client.post(uri, headers: headers, body: body);
        break;
      case HTTPVerb.patch:
        raw = await _client.patch(uri, headers: headers, body: body);
        break;
      case HTTPVerb.put:
        raw = await _client.put(uri, headers: headers, body: body);
        break;
      case HTTPVerb.delete:
        raw = await _client.delete(uri, headers: headers, body: body);
        break;
      case HTTPVerb.head:
        raw = await _client.head(uri, headers: headers);
        break;
      case HTTPVerb.options:
        raw = await _client
            .send(http.Request('OPTIONS', uri)..headers.addAll(headers))
            .then(http.Response.fromStream);
        break;
      case HTTPVerb.get:
      default:
        raw = await _client.get(uri, headers: headers);
    }

    sw.stop();

    return const HttpResponseModel().fromResponse(
      response: raw,
      time: Duration(microseconds: sw.elapsedMicroseconds),
      isStreamingResponse: false,
    );
  }

  Future<void> runSuite(Map<String, dynamic> suite) async {
    final tests = (suite['tests'] as List?) ?? const [];

    for (final t in tests) {
      final name = (t['name'] ?? 'unnamed').toString();
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

      var req = HttpRequestModel(
        method: _verb(method),
        url: '$baseUrl$path',
        body: body,
        headers: headers.entries
            .map((e) => NameValueModel(name: e.key, value: e.value))
            .toList(),
      );

      if (onManualReview != null) {
        final description =
            (t['description'] ?? 'No Description Provided').toString();
        final reviewed = await onManualReview!(req, description);
        if (reviewed == null) continue; // User skipped
        req = reviewed;
      }

      try {
        final res = await _send(req);
        _validate(t as Map, res);
      } catch (e) {
        logger('[FAIL] $name: Request failed - $e');
      }
    }
  }

  void _validate(Map test, HttpResponseModel res) {
    final name = (test['name'] ?? 'unnamed').toString();
    final expected = (test['expected_status'] as num?)?.toInt() ?? 200;
    final got = res.statusCode ?? 0;
    final description = (test['description'] ?? 'No Description').toString();

    if (got == expected) {
      logger('[PASS] $name ($got) \n $description');

      final extract = test['extract_to_env'];
      if (extract is Map && (res.body?.isNotEmpty ?? false)) {
        final data = jsonDecode(res.body!);
        extract.forEach((apiKey, envKey) {
          final v = (data is Map) ? data[apiKey] : null;
          if (v != null) env[envKey.toString()] = v.toString();
        });
      }
      return;
    }

    logger('[FAIL] $name');
    logger('       Expected: $expected, Got: $got');
    logger('       Response: ${res.body}');
  }
}
