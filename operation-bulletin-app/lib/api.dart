import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// The Cloudflare Worker URL when the app uses it; operation photos are loaded through it (see thumbUrl).
String imageProxyBase = '';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thin JSON client for the Apps Script web app (doPost dispatcher), or the Cloudflare Worker in front of it.
class Api {
  /// Apps Script web app: always works, used when no Worker is configured or the Worker is down.
  static const String execUrl =
      'https://script.google.com/macros/s/AKfycbwz492tw24mYnFwSvAG4pQ9oUU_OsW_g8EYPrTGZM119pwKzRdyQODpoGS5pfp3Z5a4zw/exec';
  /// {"url": "https://...workers.dev"} — the Cloudflare Worker to use (empty = Apps Script directly).
  static const String configUrl = 'https://starmis2-lgtm.github.io/operation-bulletin/api.json';
  static const String _prefKey = 'pb_api_url';

  final http.Client _client = http.Client();
  String token = '';
  String _base = execUrl;
  String get baseUrl => _base;
  set baseUrl(String v) {
    _base = v;
    imageProxyBase = v == execUrl ? '' : v;
  }

  /// X-Cache header of the last call from the Worker: HIT, STALE (old copy, a fresh one is coming), MISS, BYPASS.
  String lastCache = '';

  /// Uses the saved Worker URL at once and checks the config file for a new one in the background.
  Future<void> loadEndpoint() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_prefKey) ?? '';
      if (saved.startsWith('https://')) baseUrl = saved;
    } catch (_) {}
    unawaited(_refreshEndpoint());
  }

  Future<void> _refreshEndpoint() async {
    try {
      final r = await _client.get(Uri.parse('$configUrl?t=${DateTime.now().millisecondsSinceEpoch}')).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final url = ((jsonDecode(r.body) as Map)['url'] ?? '').toString().trim();
      final prefs = await SharedPreferences.getInstance();
      if (url.startsWith('https://')) {
        baseUrl = url;
        await prefs.setString(_prefKey, url);
      } else {
        baseUrl = execUrl;
        await prefs.remove(_prefKey);
      }
    } catch (_) {}
  }

  Future<dynamic> call(String fn, List<dynamic> args,
      {bool withToken = true, Duration timeout = const Duration(seconds: 45), int retries = 1}) async {
    try {
      return await _call(fn, args, withToken: withToken, timeout: timeout, url: baseUrl);
    } on ApiException catch (e) {
      final transient = e.message.startsWith('Network error') || e.message.startsWith('Server took too long') || e.message.startsWith('Server error 5');
      // Worker down → go to Apps Script directly.
      if (transient && baseUrl != execUrl) return _call(fn, args, withToken: withToken, timeout: timeout, url: execUrl);
      if (retries > 0 && transient) return call(fn, args, withToken: withToken, timeout: timeout, retries: retries - 1);
      rethrow;
    }
  }

  Future<dynamic> _call(String fn, List<dynamic> args, {required bool withToken, required Duration timeout, required String url}) async {
    final a = List<dynamic>.from(args);
    if (withToken) a.add(token);
    lastCache = '';
    if (kIsWeb) return _decodeResult(await _webPost(url, fn, a, timeout));
    final req = http.Request('POST', Uri.parse(url))
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
        lastCache = sres.headers['x-cache'] ?? '';
      }
    } on TimeoutException {
      throw ApiException('Server took too long to respond. Check your internet.');
    } on http.ClientException catch (e) {
      throw ApiException('Network error: ${e.message}');
    }

    return _decodeResult(text);
  }

  /// Browser: a plain-text POST (no CORS preflight); the browser follows Google's redirect itself.
  Future<String> _webPost(String url, String fn, List<dynamic> a, Duration timeout) async {
    try {
      final r = await _client
          .post(Uri.parse(url), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode({'fn': fn, 'args': a}))
          .timeout(timeout);
      if (r.statusCode >= 400) throw ApiException('Server error ${r.statusCode}');
      lastCache = r.headers['x-cache'] ?? '';
      return utf8.decode(r.bodyBytes);
    } on TimeoutException {
      throw ApiException('Server took too long to respond. Check your internet.');
    } on http.ClientException catch (e) {
      throw ApiException('Network error: ${e.message}');
    }
  }

  dynamic _decodeResult(String text) {
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
