import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'models.dart';

/// A write that is saved on the device and sent to the server when online.
class OutboxItem {
  OutboxItem({
    required this.id, required this.kind, required this.data, required this.srn, required this.label,
    required this.createdAt, this.attempts = 0, this.lastError = '', this.status = 'waiting',
  });
  final String id, kind, srn, label;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  int attempts;
  String lastError;
  String status; // waiting | syncing | failed

  Map<String, dynamic> toJson() => {'id': id, 'kind': kind, 'data': data, 'srn': srn, 'label': label, 'createdAt': createdAt.toIso8601String(), 'attempts': attempts, 'lastError': lastError, 'status': status == 'syncing' ? 'waiting' : status};

  static OutboxItem fromJson(Map<String, dynamic> j) => OutboxItem(
        id: s(j['id']), kind: s(j['kind']), data: m(j['data']), srn: s(j['srn']), label: s(j['label']),
        createdAt: DateTime.tryParse(s(j['createdAt'])) ?? DateTime.now(), attempts: n(j['attempts']).toInt(), lastError: s(j['lastError']), status: s(j['status']).isEmpty ? 'waiting' : s(j['status']));
}

class Outbox extends ChangeNotifier {
  Outbox(this.api);
  final Api api;
  final List<OutboxItem> items = [];
  bool processing = false;
  bool loaded = false;

  /// Messages produced while syncing (shown as snackbars by the shell).
  final ValueNotifier<String?> message = ValueNotifier(null);

  int get pendingCount => items.length;
  bool get hasFailed => items.any((i) => i.status == 'failed');

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/outbox.json');
  }

  Future<Directory> imageDir() async {
    final dir = await getApplicationSupportDirectory();
    final d = Directory('${dir.path}/images');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString()) as List<dynamic>;
        items
          ..clear()
          ..addAll(list.map((e) => OutboxItem.fromJson(m(e))));
      }
    } catch (_) {}
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(items.map((i) => i.toJson()).toList()), flush: true);
    } catch (_) {}
  }

  Future<OutboxItem> add({required String kind, required Map<String, dynamic> data, required String srn, required String label}) async {
    final item = OutboxItem(id: 'ob${DateTime.now().millisecondsSinceEpoch}', kind: kind, data: data, srn: srn, label: label, createdAt: DateTime.now());
    items.add(item);
    await _save();
    notifyListeners();
    return item;
  }

  Future<void> remove(String id) async {
    items.removeWhere((i) => i.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> retry(String id) async {
    final it = items.where((i) => i.id == id);
    for (final i in it) {
      i.status = 'waiting';
      i.lastError = '';
    }
    notifyListeners();
    await process();
  }

  static bool _isNetwork(String msg) => msg.startsWith('Network error') || msg.startsWith('Server took too long') || msg.startsWith('Server error 5') || msg.startsWith('Redirect') || msg.startsWith('Unexpected response');

  /// Uploads any locally stored images referenced by the operations, replacing them with Drive links.
  Future<void> _resolveImages(List<dynamic> ops, String srn) async {
    for (final o in ops) {
      if (o is! Map) continue;
      final img = s(o['image']);
      if (!img.startsWith('local:')) continue;
      final path = img.substring(6);
      final f = File(path);
      if (!await f.exists()) {
        o['image'] = '';
        continue;
      }
      final bytes = await f.readAsBytes();
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      final r = await api.callJson('uploadOperationImage', [dataUrl, 'image/jpeg', f.uri.pathSegments.last, srn, s(o['operationName'])]);
      if (r['error'] != null) throw ApiException(r['error'].toString());
      o['image'] = s(r['url']);
      try { await f.delete(); } catch (_) {}
    }
  }

  /// Sends queued items in order. Stops at the first network failure (keeps order), skips server-rejected items.
  Future<bool> process() async {
    if (processing || items.isEmpty || api.token.isEmpty) return false;
    processing = true;
    notifyListeners();
    var synced = false;
    try {
      for (final item in List<OutboxItem>.from(items)) {
        if (item.status == 'failed') continue;
        item.status = 'syncing';
        item.attempts++;
        notifyListeners();
        try {
          String msg;
          if (item.kind == 'submit') {
            final ops = l(item.data['operations']);
            await _resolveImages(ops, item.srn);
            await _save();
            msg = await api.callMsg('submitBulletinData', [item.data]);
          } else if (item.kind == 'updatePending') {
            final ops = l(item.data['ops']);
            await _resolveImages(ops, item.srn);
            await _save();
            msg = await api.callMsg('updatePendingSubmission', [s(item.data['id']), jsonEncode(ops)]);
          } else if (item.kind == 'notRequired') {
            msg = await api.callMsg('setNotRequired', [item.srn, jsonEncode(item.data['items'])]);
          } else {
            msg = 'Unknown item';
          }
          items.remove(item);
          synced = true;
          message.value = '${item.srn}: $msg';
        } on ApiException catch (e) {
          if (_isNetwork(e.message)) {
            item.status = 'waiting';
            item.lastError = e.message;
            break;
          }
          item.status = 'failed';
          item.lastError = e.message;
          message.value = '${item.srn}: ${e.message}';
        } catch (e) {
          item.status = 'failed';
          item.lastError = e.toString();
        }
        await _save();
        notifyListeners();
      }
      await _save();
    } finally {
      processing = false;
      notifyListeners();
    }
    return synced;
  }
}
