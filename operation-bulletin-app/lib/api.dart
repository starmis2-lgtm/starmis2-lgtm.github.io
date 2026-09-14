import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thin JSON client for the Apps Script web app (doPost dispatcher).
class Api {
  static const String execUrl =
      'https://script.google.com/macros/s/AKfycbwz492tw24mYnFwSvAG4pQ9oUU_OsW_g8EYPrTGZM119pwKzRdyQODpoGS5pfp3Z5a4zw/exec';

  final http.Client _client = http.Client();
  String token = '';

  Future<dynamic> call(String fn, List<dynamic> args,
      {bool withToken = true, Duration timeout = const Duration(seconds: 45), int retries = 1}) async {
    try {
      return await _call(fn, args, withToken: withToken, timeout: timeout);
    } on ApiException catch (e) {
      final transient = e.message.startsWith('Network error') || e.message.startsWith('Server took too long') || e.message.startsWith('Server error 5');
      if (retries > 0 && transient) return call(fn, args, withToken: withToken, timeout: timeout, retries: retries - 1);
      rethrow;
    }
  }

  Future<dynamic> _call(String fn, List<dynamic> args, {required bool withToken, required Duration timeout}) async {
    final a = List<dynamic>.from(args);
    if (withToken) a.add(token);
    final req = http.Request('POST', Uri.parse(execUrl))
      ..headers['Content-Type'] = 'application/json; charset=utf-8'
      ..followRedirects = false
      ..body = jsonEncode({'fn': fn, 'args': a});

    String text;
    try {
      final sres = await _client.send(req).timeout(timeout);
      final code = sres.statusCode;
      if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
        final loc = sres.headers['location'];
        if (loc == null || loc.isEmpty) throw ApiException('Redirect without location');
        final r = await _client.get(Uri.parse(loc)).timeout(timeout);
        if (r.statusCode >= 400) throw ApiException('Server error ${r.statusCode}');
        text = utf8.decode(r.bodyBytes);
      } else {
        text = await sres.stream.bytesToString();
        if (code >= 400) throw ApiException('Server error $code');
      }
    } on TimeoutException {
      throw ApiException('Server took too long to respond. Check your internet.');
    } on http.ClientException catch (e) {
      throw ApiException('Network error: ${e.message}');
    }

    Map<String, dynamic> j;
    try {
      j = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Unexpected response from server. Please try again.');
    }
    if (j['error'] != null) throw ApiException(j['error'].toString());
    return j['result'];
  }

  /// Calls a function that returns a JSON string and decodes it.
  Future<Map<String, dynamic>> callJson(String fn, List<dynamic> args, {bool withToken = true}) async {
    final r = await call(fn, args, withToken: withToken);
    if (r is Map<String, dynamic>) return r;
    try {
      return jsonDecode(r.toString()) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Bad JSON from server');
    }
  }

  /// Calls a function that returns "Success: ..." / "Error: ..." text.
  Future<String> callMsg(String fn, List<dynamic> args) async {
    final r = (await call(fn, args)).toString();
    if (r.startsWith('Error:')) throw ApiException(r.substring(6).trim());
    if (r.startsWith('Success:')) return r.substring(8).trim();
    return r;
  }
}
