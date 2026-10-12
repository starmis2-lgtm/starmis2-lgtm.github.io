import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';
import 'outbox.dart';
import 'update.dart';

const kTokenKey = 'pb_auth_token';
const kDraftKey = 'pb_entry_draft';
const kRejSeenKey = 'pb_rej_seen';

enum EntryMode { fresh, editRnd, prod, editPending }

/// One operation row in the entry form.
class OpDraft {
  OpDraft({
    String name = '', this.manpower = '', this.machine = '', String op1pc = '', String time = '',
    String v1 = '', String v2 = '', String v3 = '', this.img = '', this.rnd = 0, this.suggested = false, this.expanded = false,
    this.fromHeader = false,
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
  /// Manpower / machine come from the type chosen at the top of the form.
  bool fromHeader;

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
        'v1': v1Ctl.text, 'v2': v2Ctl.text, 'v3': v3Ctl.text, 'img': img, 'rnd': rnd, 'sug': suggested, 'fh': fromHeader,
      };

  static OpDraft restore(Map<String, dynamic> j) => OpDraft(
        name: s(j['n']), manpower: s(j['mp']), machine: s(j['mc']), op1pc: s(j['pc']), time: s(j['t']),
        v1: s(j['v1']), v2: s(j['v2']), v3: s(j['v3']), img: s(j['img']), rnd: n(j['rnd']), suggested: b(j['sug']), fromHeader: b(j['fh']));

  void dispose() {
    for (final c in [nameCtl, op1pcCtl, timeCtl, v1Ctl, v2Ctl, v3Ctl]) {
      c.dispose();
    }
  }
}

class AppState extends ChangeNotifier {
  AppState(this.api) : outbox = Outbox(api) {
    outbox.addListener(notifyListeners);
  }
  final Api api;
  final Outbox outbox;

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

  bool get syncing => loading || pendingWrites > 0 || outbox.processing;

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
    await outbox.load();
    Connectivity().onConnectivityChanged.listen((res) {
      final off = res.every((r) => r == ConnectivityResult.none);
      if (off != offline) {
        offline = off;
        notifyListeners();
        if (!off) {
          if (data == null && !needLogin) load(silent: true);
          syncOutbox();
        }
      }
    });
    try {
      final res = await Connectivity().checkConnectivity();
      offline = res.every((r) => r == ConnectivityResult.none);
    } catch (_) {}
    checkUpdate();
    // Show cached data instantly, then refresh from the server in the background.
    if (api.token.isNotEmpty) {
      try {
        final f = await _cacheFile();
        if (await f.exists()) {
          final j = await _parse(await f.readAsString());
          if (j['needLogin'] != true && j['error'] == null) {
            data = Payload.fromJson(j);
            rejected = List<Rejected>.from(data!.myRejected);
            needLogin = false;
            booted = true;
            notifyListeners();
          }
        }
      } catch (_) {}
    }
    seenRejected.addAll(prefs.getStringList(kRejSeenKey) ?? const []);
    await load(silent: true);
    await _restoreDraft(prefs);
    booted = true;
    notifyListeners();
    syncOutbox();
    startRejectedPolling();
  }

  /// Sends queued offline writes; refreshes data if anything was sent.
  Future<void> syncOutbox() async {
    if (needLogin || api.token.isEmpty) return;
    final sent = await outbox.process();
    if (sent) refreshLater();
  }

  /// Called when the app comes back to the foreground.
  DateTime? _lastUpdateCheck;

  /// Looks for a newer app version (at start, when the app comes back after 15 min, or from the menu).
  Future<bool> checkUpdate({bool force = false}) async {
    final last = _lastUpdateCheck;
    if (!force && last != null && DateTime.now().difference(last) < const Duration(minutes: 15)) return update != null;
    _lastUpdateCheck = DateTime.now();
    final u = await AppUpdate.check();
    if (u != null && (update == null || update!.versionCode != u.versionCode)) {
      update = u;
      updateShown = false;
      notifyListeners();
    }
    return update != null;
  }

  void onResume() {
    checkUpdate();
    syncOutbox();
    pollRejected();
    startRejectedPolling();
    final last = lastSync;
    if (last == null || DateTime.now().difference(last) > const Duration(minutes: 2)) load(silent: true);
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
        rejected = List<Rejected>.from(data!.myRejected);
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
      syncOutbox();
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
  /// Production Manager review tab (management can open it too).
  bool get showPmReview => (data?.access.isPM ?? false) || (data?.access.isManagement ?? false);
  bool get isPM => data?.access.isPM ?? false;
  /// My requests where the Production Manager asked to remove operations.
  List<MyPending> get toConfirm => (data?.myPending ?? const <MyPending>[]).where((a) => a.stage == 'DEO' && a.submittedEmail.toLowerCase() == (data?.access.email ?? '').toLowerCase()).toList();

  // ---------------- actions ----------------
  /// Queues a bulletin submission; it is sent right away when online, otherwise when the connection returns.
  Future<String> submitBulletin(Map<String, dynamic> payload, {required String srn, required String label}) async {
    await outbox.add(kind: 'submit', data: payload, srn: srn, label: label);
    if (offline) return 'Saved on phone. Will sync when internet is back.';
    syncOutbox();
    return 'Saved. Syncing to server…';
  }

  Future<String> updatePending(String id, List<Map<String, dynamic>> ops, {required String srn, required String label}) async {
    await outbox.add(kind: 'updatePending', data: {'id': id, 'ops': ops}, srn: srn, label: label);
    if (offline) return 'Saved on phone. Will sync when internet is back.';
    syncOutbox();
    return 'Saved. Syncing to server…';
  }

  /// Production Manager review: PM times, added operations, operations to remove.
  Future<String> pmReview(String id, Map<String, dynamic> review) => _write(() => api.callMsg('pmReviewSubmit', [id, jsonEncode(review)]));

  /// DEO answer to the Production Manager's removal requests: op index -> true (remove) / false (keep).
  Future<String> deoConfirm(String id, Map<String, bool> decisions) => _write(() => api.callMsg('deoConfirmRemoval', [id, jsonEncode(decisions)]));

  Future<String> rejectRequest(String id, String reason) => _write(() => api.callMsg('rejectBulletin', [id, reason]));

  Future<String> setNotRequired(String srn, List<Map<String, String>> items) => _write(() => api.callMsg('setNotRequired', [srn, jsonEncode(items)]));

  Future<String> saveUser(Map<String, dynamic> u) => _write(() => api.callMsg('saveAccessUser', [jsonEncode(u)]));

  final Set<String> dismissedRejected = {};
  List<Rejected> rejected = [];
  final Set<String> seenRejected = {};
  Timer? _rejTimer;

  List<Rejected> get visibleRejected => rejected.where((r) => !dismissedRejected.contains(r.id)).toList();
  List<Rejected> get unseenRejected => visibleRejected.where((r) => !seenRejected.contains(r.id)).toList();

  Future<void> markRejectedSeen() async {
    seenRejected.addAll(rejected.map((r) => r.id));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(kRejSeenKey, seenRejected.toList());
    } catch (_) {}
  }

  Future<void> pollRejected() async {
    if (needLogin || offline || api.token.isEmpty) return;
    try {
      final j = await api.callJson('getMyRejectedLight', const []);
      if (j['needLogin'] == true || j['error'] != null) return;
      rejected = l(j['myRejected']).map((e) => Rejected.fromJson(m(e))).toList();
      notifyListeners();
    } catch (_) {}
  }

  void startRejectedPolling() {
    _rejTimer?.cancel();
    _rejTimer = Timer.periodic(const Duration(minutes: 2), (_) => pollRejected());
  }

  void stopRejectedPolling() {
    _rejTimer?.cancel();
    _rejTimer = null;
  }

  Future<void> dismissRejected(String id) async {
    dismissedRejected.add(id);
    notifyListeners();
    try {
      await api.callMsg('dismissRejected', [id]);
    } catch (_) {}
  }

  Future<String> deleteUser(String email) => _write(() => api.callMsg('deleteAccessUser', [email]));

  /// Uploads a photo; when offline (or the upload fails on the network) it is kept on the phone
  /// and uploaded together with the bulletin later. Returns a Drive link or a `local:` path.
  Future<String> uploadImage(Uint8List bytes, String mime, String fileName, String srn, String opName) async {
    Future<String> keepLocal() async {
      final dir = await outbox.imageDir();
      final f = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await f.writeAsBytes(bytes, flush: true);
      return 'local:${f.path}';
    }
    if (offline) return keepLocal();
    try {
      final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
      final j = await api.callJson('uploadOperationImage', [dataUrl, mime, fileName, srn, opName]);
      if (j['error'] != null) throw ApiException(j['error'].toString());
      return s(j['url']);
    } on ApiException catch (e) {
      if (e.message.startsWith('Network error') || e.message.startsWith('Server took too long')) return keepLocal();
      rethrow;
    }
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
        if (op.rndAt100 > 0) e.times.add(op.rndAt100);
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
///
/// One submission = one operation type of one SRN: SRN, type (manpower) and machine are chosen once at the
/// top, the rows only carry name, ops per piece, time and photo. After submit the same SRN stays selected
/// so the next type can be filled.
class EntryDraft extends ChangeNotifier {
  Future<void> Function()? onChanged;

  @override
  void notifyListeners() {
    super.notifyListeners();
    onChanged?.call();
  }

  bool get isEmpty => srn.isEmpty && ops.isEmpty;

  Map<String, dynamic> save() => {
        'category': category, 'srn': srn, 'mp': mp, 'mc': mc, 'date': date.toIso8601String(),
        'mode': mode.index, 'pendingId': pendingId, 'bulletinFor': bulletinFor,
        'ops': ops.map((o) => o.save()).toList(),
      };

  void restoreFrom(Map<String, dynamic> j) {
    _clearOps();
    category = s(j['category']).isEmpty ? 'Making' : s(j['category']);
    srn = s(j['srn']);
    mp = s(j['mp']);
    mc = s(j['mc']);
    date = DateTime.tryParse(s(j['date'])) ?? DateTime.now();
    final mi = n(j['mode']).toInt();
    mode = (mi >= 0 && mi < EntryMode.values.length) ? EntryMode.values[mi] : EntryMode.fresh;
    if (mode == EntryMode.prod) mode = EntryMode.fresh;
    pendingId = s(j['pendingId']);
    bulletinFor = s(j['bulletinFor']);
    for (final o in l(j['ops'])) {
      ops.add(OpDraft.restore(m(o)));
    }
    super.notifyListeners();
  }

  String category = 'Making';
  final String type = 'R&D';
  String srn = '';
  /// Operation type = manpower for the whole submission ('' = not chosen yet).
  String mp = '';
  /// Machine for the whole submission (stitching only).
  String mc = '';
  DateTime date = DateTime.now();
  EntryMode mode = EntryMode.fresh;
  String pendingId = '';
  String bulletinFor = '';
  final List<OpDraft> ops = [];

  bool get isProd => false;
  bool get locked => false;
  bool get editing => mode == EntryMode.editPending;
  bool get editingAny => mode != EntryMode.fresh;
  /// Old name used by the quick-add box.
  String get role => mp;
  bool get needsMachine => category != 'Packing' && mp.toLowerCase() == 'operator';

  /// Rows on screen: everything for a new type; only the chosen type when editing a whole bulletin.
  List<OpDraft> get visibleOps => (mode == EntryMode.fresh || mp.isEmpty) ? ops : ops.where((o) => o.fromHeader || o.manpower == mp).toList();

  void reset(Payload? p) {
    category = 'Making';
    srn = '';
    date = DateTime.now();
    _fresh();
  }

  /// After a submit: same SRN, empty form for the next type.
  void nextType() {
    date = DateTime.now();
    _fresh();
  }

  void _fresh() {
    _clearOps();
    mp = '';
    mc = '';
    mode = EntryMode.fresh;
    pendingId = '';
    bulletinFor = '';
    notifyListeners();
  }

  void setCategory(String c, Payload? p) {
    if (editingAny) return;
    category = c;
    _fresh();
  }

  void setSrn(String v, Payload? p) {
    if (editingAny) return;
    srn = v;
    _fresh();
  }

  void setType(String manpower) {
    mp = manpower;
    if (!needsMachine) mc = '';
    notifyListeners();
  }

  void setMachine(String v) {
    mc = v;
    notifyListeners();
  }

  void setDate(DateTime d) {
    date = d;
    notifyListeners();
  }

  void _clearOps() {
    for (final o in ops) {
      o.dispose();
    }
    ops.clear();
  }

  /// Edit the approved bulletin of [srn]; rows of [manpower] are shown, the rest is kept as it is.
  void startEdit(Payload p, String manpower) {
    final bltn = p.bulletin(category, srn);
    if (bltn == null) return;
    _clearOps();
    mode = EntryMode.editRnd;
    pendingId = '';
    bulletinFor = category == 'Packing' ? '' : bltn.bulletinFor;
    mp = manpower;
    mc = '';
    for (final op in bltn.ops) {
      ops.add(OpDraft(
        name: op.opName, manpower: op.manpower, machine: op.machine, op1pc: op.op1pc,
        time: op.rndAt100 > 0 ? _fmt(op.rndAt100) : '', v1: op.v1, v2: op.v2, v3: op.v3, img: op.img,
      ));
      if (mc.isEmpty && op.manpower == manpower) mc = op.machine;
    }
    notifyListeners();
  }

  /// Edit my request before the Production Manager review.
  void loadPending(MyPending a, Payload? p, {String? manpower}) {
    _clearOps();
    category = a.category == 'Packing' ? 'Packing' : 'Making';
    srn = a.srn;
    date = DateTime.tryParse(a.date) ?? DateTime.now();
    mode = EntryMode.editPending;
    pendingId = a.id;
    mp = manpower ?? (a.operations.isNotEmpty ? a.operations.first.manpowerType : '');
    mc = '';
    for (final op in a.operations) {
      ops.add(OpDraft(
        name: op.operationName, manpower: op.manpowerType, machine: op.machineType, op1pc: op.operation1pc,
        time: op.time, v1: op.video1, v2: op.video2, v3: op.video3, img: op.image,
      ));
      if (mc.isEmpty && op.manpowerType == mp) mc = op.machineType;
    }
    notifyListeners();
  }

  static String _fmt(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  OpDraft add({String name = '', String op1pc = '', String time = '', bool suggested = false, String manpower = '', String machine = '', bool expanded = false}) {
    final d = OpDraft(name: name, manpower: mp, machine: mc, op1pc: op1pc.isEmpty ? '1' : op1pc, time: time, suggested: suggested, fromHeader: true);
    ops.add(d);
    notifyListeners();
    return d;
  }

  void remove(OpDraft d) {
    ops.remove(d);
    d.dispose();
    notifyListeners();
  }

  /// Copy the rows of one type from another SRN (times at 100%).
  void copyFrom(List<Op> src) {
    for (final op in src) {
      ops.add(OpDraft(name: op.opName, manpower: mp, machine: mc, op1pc: op.op1pc, time: op.rndAt100 > 0 ? _fmt(op.rndAt100) : '', suggested: op.rndTime > 0, img: op.img, fromHeader: true));
    }
    notifyListeners();
  }

  void touch() => notifyListeners();

  Set<String> get haveKeys => visibleOps.map((o) => o.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ')).where((k) => k.isNotEmpty).toSet();

  bool _filled(OpDraft o) => o.name.isNotEmpty || o.time.isNotEmpty;

  /// Index (in [visibleOps]) of the first row without name or time, or -1.
  int firstInvalid() {
    final v = visibleOps;
    for (var i = 0; i < v.length; i++) {
      final o = v[i];
      if (!_filled(o)) continue;
      if (o.name.isEmpty || o.timeNum <= 0) return i;
    }
    return -1;
  }

  int get filledCount => visibleOps.where(_filled).length;

  List<Map<String, dynamic>> collect(Payload p) {
    final media = mode == EntryMode.editRnd || mode == EntryMode.editPending;
    final out = <Map<String, dynamic>>[];
    for (final o in ops) {
      if (!_filled(o)) continue;
      if (o.fromHeader) {
        o.manpower = mp;
        o.machine = needsMachine ? mc : (category == 'Packing' ? '' : o.machine);
      } else if (needsMachine && mc.isNotEmpty && o.manpower == mp) {
        o.machine = mc;
      }
      out.add(o.toJson(p, prod: false, mediaEdited: media));
    }
    return out;
  }

  Map<String, dynamic> payload(Payload p) {
    final info = p.srn(srn);
    final isEdit = mode == EntryMode.editRnd;
    final d = date;
    final dateStr = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return {
      'header': {
        'category': category,
        'type': 'R&D',
        'bulletinFor': isEdit ? bulletinFor : '',
        'date': dateStr,
        'srnList': [
          {'srn': srn, 'styleName': info?.styleName ?? '', 'styleImage': info?.imageLink ?? ''}
        ],
        'isEditMode': isEdit,
        'editSrn': isEdit ? srn : null,
        'timesAt100': isEdit,
      },
      'operations': collect(p),
    };
  }
}
