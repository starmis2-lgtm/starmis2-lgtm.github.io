import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';
import 'update.dart';

const kTokenKey = 'pb_auth_token';
const kDraftKey = 'pb_entry_draft';

enum EntryMode { fresh, editRnd, prod, editPending }

/// One operation row in the entry form.
class OpDraft {
  OpDraft({
    String name = '', this.manpower = '', this.machine = '', String op1pc = '', String time = '',
    String v1 = '', String v2 = '', String v3 = '', this.img = '', this.rnd = 0, this.suggested = false, this.expanded = false,
  })  : nameCtl = TextEditingController(text: name),
        op1pcCtl = TextEditingController(text: op1pc),
        timeCtl = TextEditingController(text: time),
        v1Ctl = TextEditingController(text: v1),
        v2Ctl = TextEditingController(text: v2),
        v3Ctl = TextEditingController(text: v3);

  final Key key = UniqueKey();
  final TextEditingController nameCtl, op1pcCtl, timeCtl, v1Ctl, v2Ctl, v3Ctl;
  String manpower, machine, img;
  num rnd;
  bool suggested, expanded, uploading = false;

  String get name => nameCtl.text.trim();
  String get time => timeCtl.text.trim();
  num get timeNum => num.tryParse(time) ?? 0;

  num target() => timeNum > 0 ? double.parse((3600 / timeNum).toStringAsFixed(2)) : 0;
  num cost(Payload p) => timeNum > 0 ? double.parse(p.cost(manpower, timeNum).toStringAsFixed(2)) : 0;

  Map<String, dynamic> toJson(Payload p, {required bool prod, required bool mediaEdited}) {
    final c = cost(p);
    return {
      'operationName': name,
      'manpowerType': manpower,
      'machineType': machine,
      'operation1pc': op1pcCtl.text.trim(),
      'time': time,
      'target': timeNum > 0 ? target().toString() : '',
      'cost': c > 0 ? c.toStringAsFixed(2) : '',
      'video1': v1Ctl.text.trim(),
      'video2': prod ? v2Ctl.text.trim() : '',
      'video3': prod ? v3Ctl.text.trim() : '',
      'image': img,
      if (mediaEdited) 'mediaEdited': true,
    };
  }

  Map<String, dynamic> save() => {
        'n': nameCtl.text, 'mp': manpower, 'mc': machine, 'pc': op1pcCtl.text, 't': timeCtl.text,
        'v1': v1Ctl.text, 'v2': v2Ctl.text, 'v3': v3Ctl.text, 'img': img, 'rnd': rnd, 'sug': suggested,
      };

  static OpDraft restore(Map<String, dynamic> j) => OpDraft(
        name: s(j['n']), manpower: s(j['mp']), machine: s(j['mc']), op1pc: s(j['pc']), time: s(j['t']),
        v1: s(j['v1']), v2: s(j['v2']), v3: s(j['v3']), img: s(j['img']), rnd: n(j['rnd']), suggested: b(j['sug']));

  void dispose() {
    for (final c in [nameCtl, op1pcCtl, timeCtl, v1Ctl, v2Ctl, v3Ctl]) {
      c.dispose();
    }
  }
}

class AppState extends ChangeNotifier {
  AppState(this.api);
  final Api api;

  bool booted = false;
  bool needLogin = true;
  bool loading = false;
  bool offline = false;
  int pendingWrites = 0;
  String loginHint = '';
  String? error;
  Payload? data;
  AppUpdate? update;
  bool updateShown = false;
  String appVersion = '';
  DateTime? lastSync;

  bool get syncing => loading || pendingWrites > 0;

  /// Bottom-nav index requested by another screen (e.g. Home → Entry).
  int? requestedTab;

  void goToTab(int index) {
    requestedTab = index;
    notifyListeners();
  }

  // ---------------- boot / auth ----------------
  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/payload.json');
  }

  static Map<String, dynamic> _decode(String text) => jsonDecode(text) as Map<String, dynamic>;

  /// Parses payload JSON off the UI thread.
  Future<Map<String, dynamic>> _parse(String text) => compute(_decode, text);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    api.token = prefs.getString(kTokenKey) ?? '';
    entry.onChanged = _persistDraft;
    AppUpdate.currentVersion().then((v) {
      appVersion = v;
      notifyListeners();
    });
    Connectivity().onConnectivityChanged.listen((res) {
      final off = res.every((r) => r == ConnectivityResult.none);
      if (off != offline) {
        offline = off;
        notifyListeners();
        if (!off && data == null && !needLogin) load(silent: true);
      }
    });
    AppUpdate.check().then((u) {
      if (u != null) {
        update = u;
        notifyListeners();
      }
    });
    // Show cached data instantly, then refresh from the server in the background.
    if (api.token.isNotEmpty) {
      try {
        final f = await _cacheFile();
        if (await f.exists()) {
          final j = await _parse(await f.readAsString());
          if (j['needLogin'] != true && j['error'] == null) {
            data = Payload.fromJson(j);
            needLogin = false;
            booted = true;
            notifyListeners();
          }
        }
      } catch (_) {}
    }
    await load(silent: true);
    await _restoreDraft(prefs);
    booted = true;
    notifyListeners();
  }

  Future<void> _restoreDraft(SharedPreferences prefs) async {
    final raw = prefs.getString(kDraftKey);
    if (raw == null || raw.isEmpty || data == null) return;
    try {
      entry.restoreFrom(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }

  Future<void> _persistDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (entry.isEmpty) {
        await prefs.remove(kDraftKey);
      } else {
        await prefs.setString(kDraftKey, jsonEncode(entry.save()));
      }
    } catch (_) {}
  }

  /// Refresh in the background without blocking the caller.
  void refreshLater() {
    Future<void>.delayed(const Duration(milliseconds: 50), () => load(silent: true));
  }

  Future<void> load({bool silent = false}) async {
    if (loading) return;
    loading = true;
    if (!silent) notifyListeners();
    try {
      final r = await api.call('getInitialPayload', const []);
      final text = r.toString();
      final j = await _parse(text);
      if (j['needLogin'] == true) {
        needLogin = true;
        loginHint = s(j['email']);
        data = null;
        try { final f = await _cacheFile(); if (await f.exists()) await f.delete(); } catch (_) {}
      } else {
        if (j['error'] != null) throw ApiException(j['error'].toString());
        data = Payload.fromJson(j);
        needLogin = false;
        _lib.clear();
        lastSync = DateTime.now();
        try { (await _cacheFile()).writeAsString(text, flush: true); } catch (_) {}
      }
      error = null;
      offline = false;
    } on ApiException catch (e) {
      error = e.message;
      if (e.message.startsWith('Network error')) offline = true;
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  /// Runs a write against the server; the data refresh happens in the background.
  Future<String> _write(Future<String> Function() fn) async {
    pendingWrites++;
    notifyListeners();
    try {
      final msg = await fn();
      refreshLater();
      return msg;
    } finally {
      pendingWrites--;
      notifyListeners();
    }
  }

  Future<String?> login(String pin) async {
    try {
      final j = await api.callJson('loginWithPin', [pin], withToken: false);
      if (j['error'] != null) return j['error'].toString();
      api.token = s(j['token']);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kTokenKey, api.token);
      await load();
      if (needLogin) return 'Login failed. Please try again.';
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<void> logout() async {
    api.token = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kTokenKey);
    try { final f = await _cacheFile(); if (await f.exists()) await f.delete(); } catch (_) {}
    data = null;
    needLogin = true;
    loginHint = '';
    entry.reset(null);
    notifyListeners();
  }

  // ---------------- access / tabs ----------------
  bool _tabAllowed(String tab) {
    final a = data?.access;
    if (a == null) return false;
    if (tab == 'Settings') return a.canManageAccess;
    if (tab == 'My Pending') return true;
    if (tab == 'Dashboard') return a.isManagement;
    if (a.isManagement || a.tabs.isEmpty) return true;
    final want = a.tabs.map((t) => t.trim().toLowerCase().replaceAll(RegExp(r'[_-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ')).toSet();
    const aliases = {
      'Pending Bulletins': ['pending bulletins', 'pending bulletin', 'pending'],
      'Production Pending': ['production pending', 'prod pending', 'production bulletin pending'],
      'Data Entry': ['data entry', 'entry', 'bulletin entry'],
    };
    return (aliases[tab] ?? [tab.toLowerCase()]).any(want.contains);
  }

  bool get showHome => _tabAllowed('Pending Bulletins');
  bool get showProduction => _tabAllowed('Production Pending');
  bool get showEntry => _tabAllowed('Data Entry');
  bool get showSettings => _tabAllowed('Settings');

  // ---------------- actions ----------------
  Future<String> submitBulletin(Map<String, dynamic> payload) => _write(() => api.callMsg('submitBulletinData', [payload]));

  Future<String> updatePending(String id, List<Map<String, dynamic>> ops) => _write(() => api.callMsg('updatePendingSubmission', [id, jsonEncode(ops)]));

  Future<String> setNotRequired(String srn, List<Map<String, String>> items) => _write(() => api.callMsg('setNotRequired', [srn, jsonEncode(items)]));

  Future<String> saveUser(Map<String, dynamic> u) => _write(() => api.callMsg('saveAccessUser', [jsonEncode(u)]));

  Future<String> deleteUser(String email) => _write(() => api.callMsg('deleteAccessUser', [email]));

  Future<String> uploadImage(Uint8List bytes, String mime, String fileName, String srn, String opName) async {
    final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
    final j = await api.callJson('uploadOperationImage', [dataUrl, mime, fileName, srn, opName]);
    if (j['error'] != null) throw ApiException(j['error'].toString());
    return s(j['url']);
  }

  // ---------------- operation library ----------------
  final Map<String, List<LibOp>> _lib = {};

  List<LibOp> library(String category) {
    final cached = _lib[category];
    if (cached != null) return cached;
    final src = category == 'Packing' ? (data?.packing ?? const []) : (data?.submitted ?? const []);
    final map = <String, _LibAcc>{};
    for (final bltn in src) {
      for (final op in bltn.ops) {
        final k = op.opName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        if (k.isEmpty || k == 'unnamed operation') continue;
        final e = map.putIfAbsent(k, () => _LibAcc(k));
        e.count++;
        e.names.update(op.opName.trim(), (v) => v + 1, ifAbsent: () => 1);
        if (op.manpower.isNotEmpty) e.mp.update(op.manpower, (v) => v + 1, ifAbsent: () => 1);
        if (op.machine.isNotEmpty) e.mc.update(op.machine, (v) => v + 1, ifAbsent: () => 1);
        if (op.op1pc.isNotEmpty) e.pc.update(op.op1pc, (v) => v + 1, ifAbsent: () => 1);
        if (op.rndTime > 0) e.times.add(op.rndTime);
      }
    }
    final list = map.values.map((e) {
      e.times.sort();
      final med = e.times.isEmpty ? 0 : e.times[e.times.length ~/ 2];
      return LibOp(key: e.key, name: _mode(e.names), count: e.count, manpower: _mode(e.mp), machine: _mode(e.mc), op1pc: _mode(e.pc).isEmpty ? '1' : _mode(e.pc), time: med);
    }).toList()
      ..sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : a.name.compareTo(b.name));
    _lib[category] = list;
    return list;
  }

  static String _mode(Map<String, int> counts) {
    var best = '';
    var nBest = 0;
    counts.forEach((k, v) {
      if (v > nBest) {
        nBest = v;
        best = k;
      }
    });
    return best;
  }

  String _hasMp(String name) {
    final nm = name.toLowerCase();
    for (final mp in data?.manpowerTypes ?? const <ManpowerType>[]) {
      if (mp.name.toLowerCase() == nm) return mp.name;
    }
    return '';
  }

  /// Guess manpower / machine for a brand-new operation name.
  (String, String) guess(String name, String category) {
    final nm = name.toLowerCase();
    var mp = '';
    var mc = '';
    if (category == 'Packing') {
      if (RegExp(r'thread|cut').hasMatch(nm)) mp = _hasMp('Thread cutter');
      if (mp.isEmpty && RegExp(r'check|qc|inspect|final').hasMatch(nm)) mp = _hasMp('Endline QC').isNotEmpty ? _hasMp('Endline QC') : _hasMp('Final QC');
      if (mp.isEmpty) mp = _hasMp('Helper').isNotEmpty ? _hasMp('Helper') : _hasMp('Packer');
    } else {
      if (RegExp(r'hand|needle|niddle').hasMatch(nm)) {
        mp = _hasMp('Hand Niddle Operator').isNotEmpty ? _hasMp('Hand Niddle Operator') : _hasMp('Hand Needle Operator');
      } else if (RegExp(r'thread').hasMatch(nm)) {
        mp = _hasMp('Thread cutter');
      } else if (RegExp(r'check|qc|inspect|endline|end line').hasMatch(nm)) {
        mp = _hasMp('Endline QC');
      } else if (RegExp(r'past|glue|gum|fold|turn|mark|skiv').hasMatch(nm)) {
        mp = _hasMp('Paster').isNotEmpty ? _hasMp('Paster') : _hasMp('Helper');
      } else if (RegExp(r'stitch|attach|sew|run|join|tack|hem|closing|top|lining|zip').hasMatch(nm)) {
        mp = _hasMp('Operator');
        mc = (data?.machineTypes ?? const []).firstWhere((x) => x.toLowerCase().contains('stitch'), orElse: () => '');
      }
      if (mp.isEmpty) mp = _hasMp('Helper');
    }
    return (mp, mc);
  }

  // ---------------- entry draft ----------------
  final EntryDraft entry = EntryDraft();
}

class _LibAcc {
  _LibAcc(this.key);
  final String key;
  int count = 0;
  final names = <String, int>{};
  final mp = <String, int>{};
  final mc = <String, int>{};
  final pc = <String, int>{};
  final times = <num>[];
}

/// The data-entry form state. Lives in AppState so it survives tab switches.
class EntryDraft extends ChangeNotifier {
  Future<void> Function()? onChanged;

  @override
  void notifyListeners() {
    super.notifyListeners();
    onChanged?.call();
  }

  bool get isEmpty => srn.isEmpty && ops.isEmpty;

  Map<String, dynamic> save() => {
        'category': category, 'type': type, 'srn': srn, 'role': role, 'date': date.toIso8601String(),
        'mode': mode.index, 'pendingId': pendingId, 'bulletinFor': bulletinFor,
        'ops': ops.map((o) => o.save()).toList(),
      };

  void restoreFrom(Map<String, dynamic> j) {
    _clearOps();
    category = s(j['category']).isEmpty ? 'Making' : s(j['category']);
    type = s(j['type']).isEmpty ? 'R&D' : s(j['type']);
    srn = s(j['srn']);
    role = s(j['role']);
    date = DateTime.tryParse(s(j['date'])) ?? DateTime.now();
    final mi = n(j['mode']).toInt();
    mode = (mi >= 0 && mi < EntryMode.values.length) ? EntryMode.values[mi] : EntryMode.fresh;
    pendingId = s(j['pendingId']);
    bulletinFor = s(j['bulletinFor']);
    for (final o in l(j['ops'])) {
      ops.add(OpDraft.restore(m(o)));
    }
    super.notifyListeners();
  }

  String category = 'Making';
  String type = 'R&D';
  String srn = '';
  /// Selected bulletin type = manpower role ('' = none yet, 'All' = show everything).
  String role = '';
  DateTime date = DateTime.now();
  EntryMode mode = EntryMode.fresh;
  String pendingId = '';
  String bulletinFor = '';
  final List<OpDraft> ops = [];

  bool get isProd => type == 'Production';
  bool get roleChosen => role.isNotEmpty;
  List<OpDraft> get visibleOps => role == 'All' || role.isEmpty ? ops : ops.where((o) => o.manpower == role).toList();
  int countFor(String r) => ops.where((o) => o.manpower == r).length;

  void setRole(String r) {
    role = r;
    notifyListeners();
  }
  bool get locked => mode == EntryMode.prod || (mode == EntryMode.editPending && isProd);
  bool get editing => mode == EntryMode.editPending;

  void reset(Payload? p) {
    category = 'Making';
    type = 'R&D';
    srn = '';
    role = '';
    date = DateTime.now();
    pendingId = '';
    _reload(p);
  }

  void setCategory(String c, Payload? p) {
    if (editing) return;
    category = c;
    _reload(p);
  }

  void setType(String t, Payload? p) {
    if (editing) return;
    type = t;
    _reload(p);
  }

  void setSrn(String v, Payload? p) {
    if (editing) return;
    srn = v;
    role = '';
    _reload(p);
  }

  void setDate(DateTime d) {
    date = d;
    notifyListeners();
  }

  /// Start a bulletin for [srn] (from Home / Production tabs).
  void start(String srnV, String cat, String typ, Payload? p, {String role = ''}) {
    pendingId = '';
    category = cat == 'Packing' ? 'Packing' : 'Making';
    type = typ == 'Production' ? 'Production' : 'R&D';
    srn = srnV;
    this.role = role;
    date = DateTime.now();
    _reload(p);
  }

  void _clearOps() {
    for (final o in ops) {
      o.dispose();
    }
    ops.clear();
  }

  void _reload(Payload? p) {
    _clearOps();
    pendingId = '';
    bulletinFor = '';
    final bltn = (p != null && srn.isNotEmpty) ? p.bulletin(category, srn) : null;
    if (isProd) {
      mode = EntryMode.prod;
      if (bltn != null) {
        for (final op in bltn.ops) {
          ops.add(OpDraft(
            name: op.opName, manpower: op.manpower, machine: op.machine, op1pc: op.op1pc,
            time: op.prdTime > 0 ? _fmt(op.prdTime) : '', rnd: op.rndTime, v1: op.v1, v2: op.v2, v3: op.v3, img: op.img,
          ));
        }
      }
    } else if (bltn != null && bltn.ops.isNotEmpty) {
      mode = EntryMode.editRnd;
      bulletinFor = category == 'Packing' ? '' : bltn.bulletinFor;
      for (final op in bltn.ops) {
        ops.add(OpDraft(
          name: op.opName, manpower: op.manpower, machine: op.machine, op1pc: op.op1pc,
          time: op.rndTime > 0 ? _fmt(op.rndTime) : '', v1: op.v1, v2: op.v2, v3: op.v3, img: op.img,
        ));
      }
    } else {
      mode = EntryMode.fresh;
    }
    notifyListeners();
  }

  void loadPending(MyPending a, Payload? p) {
    _clearOps();
    category = a.category == 'Packing' ? 'Packing' : 'Making';
    type = a.type == 'Production' ? 'Production' : 'R&D';
    srn = a.srn;
    role = 'All';
    date = DateTime.tryParse(a.date) ?? DateTime.now();
    mode = EntryMode.editPending;
    pendingId = a.id;
    final cur = p?.bulletin(category, a.srn);
    for (var i = 0; i < a.operations.length; i++) {
      final op = a.operations[i];
      ops.add(OpDraft(
        name: op.operationName, manpower: op.manpowerType, machine: op.machineType, op1pc: op.operation1pc,
        time: op.time, v1: op.video1, v2: op.video2, v3: op.video3, img: op.image,
        rnd: (isProd && cur != null && i < cur.ops.length) ? cur.ops[i].rndTime : 0,
      ));
    }
    notifyListeners();
  }

  static String _fmt(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  OpDraft add({String name = '', String manpower = '', String machine = '', String op1pc = '', String time = '', bool suggested = false, bool expanded = false}) {
    final mp = (role.isNotEmpty && role != 'All') ? role : manpower;
    final d = OpDraft(name: name, manpower: mp, machine: machine, op1pc: op1pc.isEmpty ? '1' : op1pc, time: time, suggested: suggested, expanded: expanded);
    ops.add(d);
    notifyListeners();
    return d;
  }

  void remove(OpDraft d) {
    ops.remove(d);
    d.dispose();
    notifyListeners();
  }

  void replaceWith(List<Op> src) {
    _clearOps();
    for (final op in src) {
      ops.add(OpDraft(name: op.opName, manpower: op.manpower, machine: op.machine, op1pc: op.op1pc, time: op.rndTime > 0 ? _fmt(op.rndTime) : '', suggested: op.rndTime > 0));
    }
    notifyListeners();
  }

  void touch() => notifyListeners();

  Set<String> get haveKeys => ops.map((o) => o.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ')).where((k) => k.isNotEmpty).toSet();

  /// Validation for R&D submission; returns index of first bad row or -1.
  int firstInvalid() {
    if (isProd) return -1;
    for (var i = 0; i < ops.length; i++) {
      final o = ops[i];
      if (o.name.isEmpty && o.time.isEmpty) continue;
      if (o.name.isEmpty || o.timeNum <= 0 || o.manpower.isEmpty) return i;
    }
    return -1;
  }

  List<Map<String, dynamic>> collect(Payload p) {
    final media = mode == EntryMode.editRnd || mode == EntryMode.editPending;
    return ops.where((o) => isProd || o.name.isNotEmpty || o.time.isNotEmpty).map((o) => o.toJson(p, prod: isProd, mediaEdited: media)).toList();
  }

  Map<String, dynamic> payload(Payload p) {
    final info = p.srn(srn);
    final isEdit = mode == EntryMode.editRnd;
    final d = date;
    final dateStr = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return {
      'header': {
        'category': category,
        'type': type,
        'bulletinFor': isEdit ? bulletinFor : '',
        'date': dateStr,
        'srnList': [
          {'srn': srn, 'styleName': info?.styleName ?? '', 'styleImage': info?.imageLink ?? ''}
        ],
        'isEditMode': isEdit,
        'editSrn': isEdit ? srn : null,
      },
      'operations': collect(p),
    };
  }
}
