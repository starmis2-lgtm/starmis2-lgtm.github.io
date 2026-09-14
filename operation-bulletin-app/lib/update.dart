import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Checks the published version file on GitHub Pages.
class AppUpdate {
  AppUpdate({required this.versionName, required this.versionCode, required this.apkUrl, required this.notes});
  final String versionName, apkUrl, notes;
  final int versionCode;

  static const versionUrl = 'https://starmis2-lgtm.github.io/operation-bulletin/app/version.json';

  static Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version} (${info.buildNumber})';
  }

  /// Returns the newer release, or null when up to date / offline.
  static Future<AppUpdate?> check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final cur = int.tryParse(info.buildNumber) ?? 0;
      final r = await http.get(Uri.parse('$versionUrl?t=${DateTime.now().millisecondsSinceEpoch}')).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final code = (j['versionCode'] as num?)?.toInt() ?? 0;
      if (code <= cur) return null;
      return AppUpdate(versionName: j['versionName']?.toString() ?? '', versionCode: code, apkUrl: j['apk']?.toString() ?? '', notes: j['notes']?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }
}
