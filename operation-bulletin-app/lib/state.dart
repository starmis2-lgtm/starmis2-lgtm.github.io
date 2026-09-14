import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';

const kTokenKey = 'pb_auth_token';

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
  String loginHint = '';
  String? error;
  Payload? data;

  /// Bottom-nav index requested by another screen (e.g. Home → Entry).
  int? requestedTab;

  void goToTab(int index) {
    requestedTab = index;
    notifyListeners();
  }

  // ---------------- boot / auth ----------------
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    api.token = prefs.getString(kTokenKey) ?? '';
    await load(silent: true);
    booted = true;
    notifyListeners();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      loading = true;
      notifyListeners();
    }
    try {
      final j = await api.callJson('getInitialPayload', const []);
      if (j['needLogin'] == true) {
        needLogin = true;
        loginHint = s(j['email']);
        data = null;
      } else {
        if (j['error'] != null) throw ApiException(j['error'].toString());
        data = Payload.fromJson(j);
        needLogin = false;
        _lib.clear();
      }
      error = null;
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
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
  Future<String> submitBulletin(Map<String, dynamic> payload) async {
    final msg = await api.callMsg('submitBulletinData', [payload]);
    await load(silent: true);
    return msg;
  }

  Future<String> updatePending(String id, List<Map<String, dynamic>> ops) async {
    final msg = await api.callMsg('updatePendingSubmission', [id, jsonEncode(ops)]);
    await load(silent: true);
    return msg;
  }

  Future<String> setNotRequired(String srn, List<Map<String, String>> items) async {
    final msg = await api.callMsg('setNotRequired', [srn, jsonEncode(items)]);
    await load(silent: true);
    return msg;
  }

  Future<String> saveUser(Map<String, dynamic> u) async {
    final msg = await api.callMsg('saveAccessUser', [jsonEncode(u)]);
    await load(silent: true);
    return msg;
  }

  Future<String> deleteUser(String email) async {
    final msg = await api.callMsg('deleteAccessUser', [email]);
    await load(silent: true);
    return msg;
  }

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
  String category = 'Making';
  String type = 'R&D';
  String srn = '';
  DateTime date = DateTime.now();
  EntryMode mode = EntryMode.fresh;
  String pendingId = '';
  String bulletinFor = '';
  final List<OpDraft> ops = [];

  bool get isProd => type == 'Production';
  bool get locked => mode == EntryMode.prod || (mode == EntryMode.editPending && isProd);
  bool get editing => mode == EntryMode.editPending;

  void reset(Payload? p) {
    category = 'Making';
    type = 'R&D';
    srn = '';
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
    _reload(p);
  }

  void setDate(DateTime d) {
    date = d;
    notifyListeners();
  }

  /// Start a bulletin for [srn] (from Home / Production tabs).
  void start(String srnV, String cat, String typ, Payload? p) {
    pendingId = '';
    category = cat == 'Packing' ? 'Packing' : 'Making';
    type = typ == 'Production' ? 'Production' : 'R&D';
    srn = srnV;
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
    final d = OpDraft(name: name, manpower: manpower, machine: machine, op1pc: op1pc, time: time, suggested: suggested, expanded: expanded);
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
