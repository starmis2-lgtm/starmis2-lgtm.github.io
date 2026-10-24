import 'package:flutter/material.dart';

String s(dynamic v) => v == null ? '' : v.toString().trim();
num n(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v;
  return num.tryParse(v.toString().replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0;
}
bool b(dynamic v) => v == true || v == 'true';
List<dynamic> l(dynamic v) => v is List ? v : const [];
Map<String, dynamic> m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class Access {
  Access({
    this.email = '', this.name = '', this.designation = '', this.department = '',
    this.isManagement = false, this.canManageAccess = false, this.found = false, this.viaPin = false,
    this.tabs = const [], this.isPM = false, this.isGM = false,
  });
  final String email, name, designation, department;
  final bool isManagement, canManageAccess, found, viaPin, isPM, isGM;
  final List<String> tabs;

  factory Access.fromJson(Map<String, dynamic> j) => Access(
        email: s(j['email']), name: s(j['name']), designation: s(j['designation']), department: s(j['department']),
        isManagement: b(j['isManagement']), canManageAccess: b(j['canManageAccess']), found: b(j['found']), viaPin: b(j['viaPin']),
        tabs: l(j['tabs']).map(s).where((t) => t.isNotEmpty).toList(),
        isPM: b(j['isPM']) || RegExp(r'production\s*manager', caseSensitive: false).hasMatch(s(j['designation'])),
        isGM: b(j['isGM']),
      );
  String get displayName => name.isNotEmpty ? name : email;
}

class SrnInfo {
  SrnInfo({required this.srn, this.orderDate = '', this.shippingQty = 0, this.exFactoryDate = '', this.styleName = '', this.imageLink = ''});
  final String srn, orderDate, exFactoryDate, styleName, imageLink;
  final num shippingQty;
  factory SrnInfo.fromJson(Map<String, dynamic> j) => SrnInfo(
        srn: s(j['srn']), orderDate: s(j['orderDate']), shippingQty: n(j['shippingQty']),
        exFactoryDate: s(j['exFactoryDate']), styleName: s(j['styleName']), imageLink: s(j['imageLink']));
}

class ManpowerType {
  ManpowerType(this.name, this.wage);
  final String name;
  final num wage;
}

class Op {
  Op({
    required this.opName, required this.manpower, this.machine = '', this.op1pc = '',
    this.time = 0, this.type = 'R&D', this.rndTime = 0, this.prdTime = 0, this.target = 0, this.cost = 0,
    this.v1 = '', this.v2 = '', this.v3 = '', this.img = '', this.eff = 100,
  });
  final String opName, manpower, machine, op1pc, type, v1, v2, v3, img;
  final num time, rndTime, prdTime, target, cost, eff;

  /// DEO time at 100% efficiency (the sheet keeps the time after efficiency).
  num get rndAt100 => rndTime > 0 ? (rndTime * (eff > 0 ? eff : 100) / 100 * 100).round() / 100 : 0;
  factory Op.fromJson(Map<String, dynamic> j) => Op(
        opName: s(j['opName']), manpower: s(j['manpower']), machine: s(j['machine']), op1pc: s(j['op1pc']),
        time: n(j['time']), type: s(j['type']), rndTime: n(j['rndTime']), prdTime: n(j['prdTime']),
        target: n(j['target']), cost: n(j['cost']), v1: s(j['v1']), v2: s(j['v2']), v3: s(j['v3']), img: s(j['img']),
        eff: n(j['eff']) > 0 ? n(j['eff']) : 100);
}

class Bulletin {
  Bulletin({required this.srn, this.styleName = '', this.shippingQty = 0, this.imageLink = '', this.bulletinFor = '', this.ops = const []});
  final String srn, styleName, imageLink, bulletinFor;
  final num shippingQty;
  final List<Op> ops;
  factory Bulletin.fromJson(Map<String, dynamic> j) => Bulletin(
        srn: s(j['srn']), styleName: s(j['styleName']), shippingQty: n(j['shippingQty']), imageLink: s(j['imageLink']),
        bulletinFor: s(j['bulletinFor']), ops: l(j['rawOperations']).map((e) => Op.fromJson(m(e))).toList());
}

class TaskDelay {
  TaskDelay({this.due = '', this.hasDue = false, this.late = 0, this.impact = 0, this.daysLeft = 0, this.status = 'nodue', this.score = 10});
  final String due, status;
  final bool hasDue;
  final num late, impact, daysLeft, score;
  factory TaskDelay.fromJson(Map<String, dynamic> j) => TaskDelay(
        due: s(j['due']), hasDue: b(j['hasDue']), late: n(j['late']), impact: n(j['impact']),
        daysLeft: n(j['daysLeft']), status: s(j['status']), score: n(j['score']));
}

class PendingTask {
  PendingTask({required this.key, required this.label, required this.category, required this.type, required this.delay});
  final String key, label, category, type;
  final TaskDelay delay;
  factory PendingTask.fromJson(Map<String, dynamic> j) => PendingTask(
        key: s(j['key']), label: s(j['label']), category: s(j['category']), type: s(j['type']), delay: TaskDelay.fromJson(j));
}

class PendingItem {
  PendingItem({
    required this.srn, this.styleName = '', this.shippingQty = 0, this.imageLink = '', this.orderDate = '', this.stitchDate = '',
    this.missingRoles = const [], this.status = '', this.tasks = const [], this.rndDue = '', this.prodDue = '', this.worst,
  });
  final String srn, styleName, imageLink, orderDate, stitchDate, status, rndDue, prodDue;
  final num shippingQty;
  final List<String> missingRoles;
  final List<PendingTask> tasks;
  final TaskDelay? worst;
  factory PendingItem.fromJson(Map<String, dynamic> j) => PendingItem(
        srn: s(j['srn']), styleName: s(j['styleName']), shippingQty: n(j['shippingQty']), imageLink: s(j['imageLink']),
        orderDate: s(j['orderDate']), stitchDate: s(j['stitchDate']), missingRoles: l(j['missingRoles']).map(s).toList(),
        status: s(j['status']), tasks: l(j['tasks']).map((e) => PendingTask.fromJson(m(e))).toList(),
        rndDue: s(j['rndDue']), prodDue: s(j['prodDue']), worst: j['worst'] == null ? null : TaskDelay.fromJson(m(j['worst'])));
  String get worstKey {
    final w = worst;
    if (w == null || !w.hasDue) return 'nodue';
    return w.status == 'delayed' ? 'delayed' : (w.status == 'today' ? 'today' : 'upcoming');
  }
}

class ProdPending {
  ProdPending({
    required this.srn, this.styleName = '', this.shippingQty = 0, this.imageLink = '', this.category = 'Making',
    this.stitchDate = '', this.rndDate = '', required this.delay,
  });
  final String srn, styleName, imageLink, category, stitchDate, rndDate;
  final num shippingQty;
  final TaskDelay delay;
  bool get waiting => delay.status == 'waiting' || !delay.hasDue;
  factory ProdPending.fromJson(Map<String, dynamic> j) => ProdPending(
        srn: s(j['srn']), styleName: s(j['styleName']), shippingQty: n(j['shippingQty']), imageLink: s(j['imageLink']),
        category: s(j['category']), stitchDate: s(j['stitchDate']), rndDate: s(j['rndDate']), delay: TaskDelay.fromJson(j));
}

class PendingOp {
  PendingOp({
    this.operationName = '', this.manpowerType = '', this.machineType = '', this.operation1pc = '',
    this.time = '', this.target = '', this.cost = '', this.video1 = '', this.video2 = '', this.video3 = '', this.image = '',
    this.deoTime = '', this.pmTime = '', this.pmAdded = false, this.pmRemove = false, this.deoKept = false,
  });
  final String operationName, manpowerType, machineType, operation1pc, time, target, cost, video1, video2, video3, image;
  /// Production Manager review: DEO time kept aside, PM time, op added by PM, PM asked to remove, DEO kept it.
  final String deoTime, pmTime;
  final bool pmAdded, pmRemove, deoKept;
  factory PendingOp.fromJson(Map<String, dynamic> j) => PendingOp(
        operationName: s(j['operationName']), manpowerType: s(j['manpowerType']), machineType: s(j['machineType']),
        operation1pc: s(j['operation1pc']), time: s(j['time']), target: s(j['target']), cost: s(j['cost']),
        video1: s(j['video1']), video2: s(j['video2']), video3: s(j['video3']), image: s(j['image']),
        deoTime: s(j['deoTime']), pmTime: s(j['pmTime']), pmAdded: b(j['pmAdded']), pmRemove: b(j['pmRemove']), deoKept: b(j['deoKept']));
}

class MyPending {
  MyPending({
    required this.id, required this.srn, this.styleName = '', this.category = 'Making', this.type = 'R&D', this.bulletinFor = '',
    this.date = '', this.isEditMode = false, this.submittedBy = '', this.submittedEmail = '', this.submittedAt = '',
    this.operations = const [], this.mis, this.stage = 'GM', this.pmBy = '', this.pmAt = '', this.pmNote = '',
    this.isDeleteRequest = false, this.deleteReason = '', this.groupSrns = const [],
  });
  /// Master SRN request (634 = 634A / 634B / 634C): one approval saves the bulletin into all of them.
  final List<String> groupSrns;
  bool get isGroup => groupSrns.length > 1;
  /// Every SRN this request is for.
  List<String> get srns => isGroup ? groupSrns : [srn];
  bool covers(String s) => srns.contains(s);
  /// Request to delete the whole approved bulletin (GM approves it in the web app).
  final bool isDeleteRequest;
  final String deleteReason;
  final String id, srn, styleName, category, type, bulletinFor, date, submittedBy, submittedEmail, submittedAt;
  /// PM = with Production Manager, DEO = DEO to confirm removals, GM = waiting for GM approval.
  final String stage, pmBy, pmAt, pmNote;
  final bool isEditMode;
  bool get pmReviewed => pmBy.isNotEmpty;
  final List<PendingOp> operations;
  final TaskDelay? mis;
  factory MyPending.fromJson(Map<String, dynamic> j) => MyPending(
        id: s(j['id']), srn: s(j['srn']), styleName: s(j['styleName']), category: s(j['category']), type: s(j['type']),
        bulletinFor: s(j['bulletinFor']), date: s(j['date']), isEditMode: b(j['isEditMode']), submittedBy: s(j['submittedBy']),
        submittedEmail: s(j['submittedEmail']), submittedAt: s(j['submittedAt']),
        operations: l(j['operations']).map((e) => PendingOp.fromJson(m(e))).toList(),
        mis: j['mis'] == null ? null : TaskDelay.fromJson(m(j['mis'])),
        stage: const ['PM', 'DEO'].contains(s(j['stage']).toUpperCase()) ? s(j['stage']).toUpperCase() : 'GM',
        pmBy: s(m(j['pm'])['by']), pmAt: s(m(j['pm'])['at']), pmNote: s(m(j['pm'])['note']),
        isDeleteRequest: b(j['isDeleteRequest']), deleteReason: s(j['deleteReason']),
        groupSrns: l(j['groupSrns']).map((e) => s(e)).where((e) => e.isNotEmpty).toList());
  num get totalTime => operations.fold<num>(0, (a, o) => a + (n(o.time) > 0 ? n(o.time) : 0));
}

class Rejected {
  Rejected({
    required this.id, required this.srn, this.styleName = '', this.category = '', this.type = '', this.reason = '', this.rejectedBy = '',
    this.rejectedAt = '', this.submittedAt = '', this.ops = 0, this.isEditMode = false, this.isDeleteRequest = false, this.operations = const [],
  });
  final String id, srn, styleName, category, type, reason, rejectedBy, rejectedAt, submittedAt;
  final int ops;
  final bool isEditMode, isDeleteRequest;
  /// The rejected operations, so the DEO can fix and send them again.
  final List<PendingOp> operations;
  factory Rejected.fromJson(Map<String, dynamic> j) => Rejected(
        id: s(j['id']), srn: s(j['srn']), styleName: s(j['styleName']), category: s(j['category']), type: s(j['type']),
        reason: s(j['reason']), rejectedBy: s(j['rejectedBy']), rejectedAt: s(j['rejectedAt']), submittedAt: s(j['submittedAt']), ops: n(j['ops']).toInt(),
        isEditMode: b(j['isEditMode']), isDeleteRequest: b(j['isDeleteRequest']),
        operations: l(j['operations']).map((e) => PendingOp.fromJson(m(e))).toList());
}

class AccessUser {
  AccessUser({required this.email, this.name = '', this.designation = '', this.department = '', this.tabs = const [], this.pin = ''});
  final String email, name, designation, department, pin;
  final List<String> tabs;
  factory AccessUser.fromJson(Map<String, dynamic> j) => AccessUser(
        email: s(j['email']), name: s(j['name']), designation: s(j['designation']), department: s(j['department']),
        tabs: l(j['tabs']).map(s).toList(), pin: s(j['pin']));
}

class NotReq {
  NotReq({required this.srn, required this.task, this.role = '', this.by = ''});
  final String srn, task, role, by;
  factory NotReq.fromJson(Map<String, dynamic> j) => NotReq(srn: s(j['srn']), task: s(j['task']), role: s(j['role']), by: s(j['by']));
}

class Payload {
  Payload({
    required this.access, this.srns = const [], this.manpowerTypes = const [], this.machineTypes = const [],
    this.submitted = const [], this.packing = const [], this.pending = const [], this.prodPending = const [],
    this.myPending = const [], this.myRejected = const [], this.notRequired = const [], this.accessUsers = const [], this.allTabs = const [],
    this.approvalsCount = 0, this.pmQueue = const [],
  });
  final List<MyPending> pmQueue;
  final Access access;
  final List<SrnInfo> srns;
  final List<ManpowerType> manpowerTypes;
  final List<String> machineTypes;
  final List<Bulletin> submitted, packing;
  final List<PendingItem> pending;
  final List<ProdPending> prodPending;
  final List<MyPending> myPending;
  final List<Rejected> myRejected;
  final List<NotReq> notRequired;

  /// Manpower name as written in the sheet for a key from [mpKeyOf].
  String mpName(String key) {
    for (final x in manpowerTypes) {
      if (mpKeyOf(x.name) == key) return x.name;
    }
    return _mpDefaults[key] ?? key;
  }

  /// Manpower names allowed in an operation type.
  List<String> sectionManpower(String category, String sec) {
    final x = sectionByKey(category, sec);
    return x == null ? <String>[] : x.mpKeys.map(mpName).toList();
  }

  /// The NOT REQUIRED sheet row of an operation type, if it is marked.
  NotReq? typeNotRequired(String srn, String category, String sec) {
    final task = category == 'Packing' ? 'pkRnd' : 'mkRnd';
    final x = sectionByKey(category, sec);
    if (x == null) return null;
    final role = mpKeyOf(mpName(x.mpKeys.first));
    for (final n in notRequired) {
      if (n.srn == srn && n.task == task && n.role.isNotEmpty && mpKeyOf(n.role) == role) return n;
    }
    return null;
  }
  final List<AccessUser> accessUsers;
  final List<String> allTabs;
  final int approvalsCount;

  factory Payload.fromJson(Map<String, dynamic> j) => Payload(
        access: Access.fromJson(m(j['access'])),
        srns: l(j['srns']).map((e) => SrnInfo.fromJson(m(e))).toList(),
        manpowerTypes: l(j['manpowerTypes']).map((e) => ManpowerType(s(m(e)['name']), n(m(e)['wage']))).toList(),
        machineTypes: l(j['machineTypes']).map(s).toList(),
        submitted: l(j['submitted']).map((e) => Bulletin.fromJson(m(e))).toList(),
        packing: l(j['packing']).map((e) => Bulletin.fromJson(m(e))).toList(),
        pending: l(j['pending']).map((e) => PendingItem.fromJson(m(e))).toList(),
        prodPending: l(j['prodPending']).map((e) => ProdPending.fromJson(m(e))).toList(),
        myPending: l(j['myPending']).map((e) => MyPending.fromJson(m(e))).toList(),
        myRejected: l(j['myRejected']).map((e) => Rejected.fromJson(m(e))).toList(),
        notRequired: l(j['notRequired']).map((e) => NotReq.fromJson(m(e))).toList(),
        accessUsers: l(j['accessUsers']).map((e) => AccessUser.fromJson(m(e))).toList(),
        allTabs: l(j['allTabs']).map(s).toList(),
        approvalsCount: l(j['approvals']).length,
        pmQueue: l(j['pmQueue']).map((e) => MyPending.fromJson(m(e))).toList(),
      );

  SrnInfo? srn(String srn) {
    for (final o in srns) {
      if (o.srn == srn) return o;
    }
    return null;
  }

  /// Operations to copy from [srn] (one category): the latest edit still waiting for approval if there is one,
  /// else the approved bulletin plus every new request of that SRN still waiting for approval.
  List<Op> copyOps(String category, String srn) {
    final pend = myPending
        .where((x) => x.covers(srn) && !x.isDeleteRequest && x.type != 'Production' && (x.category == 'Packing' ? 'Packing' : 'Making') == category)
        .toList()
      ..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));
    Op toOp(PendingOp o) => Op(opName: o.operationName, manpower: o.manpowerType, machine: o.machineType,
        op1pc: o.operation1pc.isEmpty ? '1' : o.operation1pc, rndTime: n(o.time), img: o.image, v1: o.video1);
    final edits = pend.where((x) => x.isEditMode).toList();
    if (edits.isNotEmpty) return edits.last.operations.map(toOp).toList();
    return [...?bulletin(category, srn)?.ops, for (final r in pend) ...r.operations.map(toOp)];
  }

  /// SRNs (one category) that have operations to copy; true = some of them are not approved yet.
  Map<String, bool> copySrns(String category) {
    final out = <String, bool>{};
    for (final b in category == 'Packing' ? packing : submitted) {
      if (b.ops.isNotEmpty) out[b.srn] = false;
    }
    for (final x in myPending) {
      if (x.isDeleteRequest || x.type == 'Production' || (x.category == 'Packing' ? 'Packing' : 'Making') != category || x.operations.isEmpty) continue;
      for (final s in x.srns) {
        out[s] = true;
      }
    }
    return out;
  }

  Bulletin? bulletin(String category, String srn) {
    final src = category == 'Packing' ? packing : submitted;
    for (final b in src) {
      if (b.srn == srn) return b;
    }
    return null;
  }

  num wage(String role) {
    final r = role.trim().toLowerCase();
    for (final mp in manpowerTypes) {
      if (mp.name.trim().toLowerCase() == r) return mp.wage;
    }
    return 0;
  }

  num cost(String role, num timeSec) {
    final w = wage(role);
    if (w <= 0 || timeSec <= 0) return 0;
    return (w / 8) * (timeSec / 3600);
  }
}

/// One entry in the operation library built from historical bulletins.
class LibOp {
  LibOp({required this.key, required this.name, required this.count, required this.manpower, required this.machine, required this.op1pc, required this.time});
  final String key, name, manpower, machine, op1pc;
  final int count;
  final num time;
}

/// Friendly label for a manpower role used as "bulletin type".
String roleLabel(String role) {
  final r = role.trim().toLowerCase();
  if (r == 'operator') return 'Stitching';
  if (r == 'paster') return 'Pasting';
  if (r == 'thread cutter' || r == 'thread cutting') return 'Thread Cutting';
  if (r == 'endline qc' || r == 'end line checker') return 'Endline QC';
  if (r.contains('niddle') || r.contains('needle')) return 'Hand Needle';
  if (r == 'final qc' || r == 'finalqc') return 'Final QC';
  if (r == 'press man' || r == 'pressman') return 'Pressing';
  return role;
}

String _mpKey(String v) => v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Same rule as the web app: Packing uses only Final QC, Press Man and Helper; Making uses the rest.
bool mpAllowed(String name, String category) {
  final k = _mpKey(name);
  if (category == 'Packing') return k == 'finalqc' || k == 'pressman' || k == 'helper';
  return k != 'finalqc' && k != 'pressman';
}

/// Manpower name reduced to a fixed key ('operator', 'helper', 'paster', 'handneedle', 'threadcutter', 'endlineqc', 'finalqc', 'pressman').
String mpKeyOf(String name) {
  final k = _mpKey(name);
  if (k.contains('niddle') || k.contains('needle')) return 'handneedle';
  if (k == 'threadcutting') return 'threadcutter';
  if (k == 'endlinechecker') return 'endlineqc';
  return k;
}

/// One operation type of the data entry (a chip at the top) and the manpower allowed in it.
class OpSection {
  const OpSection(this.key, this.label, this.mpKeys, {this.machine = false});
  final String key, label;
  final List<String> mpKeys;
  /// Rows of this type need a machine (stitching).
  final bool machine;
}

const makingSections = [
  OpSection('stitching', 'Stitching', ['operator', 'helper'], machine: true),
  OpSection('pasting', 'Pasting', ['paster']),
  OpSection('helper', 'Helper', ['helper']),
  OpSection('handneedle', 'Hand Needle', ['handneedle']),
  OpSection('threadcut', 'Thread Cutting', ['threadcutter']),
  OpSection('endline', 'Endline QC', ['endlineqc']),
];

const packingSections = [
  OpSection('helper', 'Helper', ['helper']),
  OpSection('finalqc', 'Final QC', ['finalqc']),
  OpSection('pressing', 'Pressing', ['pressman']),
];

List<OpSection> sectionsFor(String category) => category == 'Packing' ? packingSections : makingSections;

OpSection? sectionByKey(String category, String key) {
  for (final x in sectionsFor(category)) {
    if (x.key == key) return x;
  }
  return null;
}

/// Operation type of a saved row. A Making helper row with a machine belongs to Stitching.
String sectionOf(String category, String manpower, String machine) {
  final k = mpKeyOf(manpower);
  if (category == 'Packing') {
    if (k == 'pressman') return 'pressing';
    return k;
  }
  switch (k) {
    case 'operator':
      return 'stitching';
    case 'helper':
      return machine.trim().isEmpty ? 'helper' : 'stitching';
    case 'paster':
      return 'pasting';
    case 'handneedle':
      return 'handneedle';
    case 'threadcutter':
      return 'threadcut';
    case 'endlineqc':
      return 'endline';
  }
  return k;
}

/// Chip label of an operation type; unknown types use the manpower name.
String sectionLabel(String category, String key, [String manpower = '']) =>
    sectionByKey(category, key)?.label ?? (manpower.isEmpty ? key : roleLabel(manpower));

const _mpDefaults = {
  'operator': 'Operator', 'helper': 'Helper', 'paster': 'Paster', 'handneedle': 'Hand Niddle Operator',
  'threadcutter': 'Thread cutter', 'endlineqc': 'Endline QC', 'finalqc': 'Final QC', 'pressman': 'Press Man',
};

const roleOrder = ['Operator', 'Paster', 'Helper', 'Hand Niddle Operator', 'Thread cutter', 'Endline QC'];

int roleRank(String role) {
  final i = roleOrder.indexWhere((x) => x.toLowerCase() == role.toLowerCase());
  return i < 0 ? 999 : i;
}

String stageLabel(String stage) {
  switch (stage) {
    case 'PM':
      return 'With Production Manager';
    case 'DEO':
      return 'Confirm removal';
    default:
      return 'Waiting for GM';
  }
}

Color stageColor(String stage) {
  switch (stage) {
    case 'PM':
      return const Color(0xFF6D28D9);
    case 'DEO':
      return const Color(0xFFC2410C);
    default:
      return const Color(0xFF0E7490);
  }
}

const taskLabels = {'mkRnd': 'Making R&D', 'pkRnd': 'Packing R&D', 'mkProd': 'Making Production', 'pkProd': 'Packing Production'};
const coreMakingRoles = ['Operator', 'Helper', 'Paster', 'Thread cutter', 'Endline QC'];
