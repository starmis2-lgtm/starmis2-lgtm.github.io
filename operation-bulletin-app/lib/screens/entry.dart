import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';
import '../widgets/tone.dart';

String _fmtT(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

/// One operation type already sent for the selected SRN (approved, pending or still on the phone).
class _Sent {
  _Sent(this.mp, this.label);
  /// Operation type key (see [sectionOf]).
  final String mp;
  final String label;
  /// Marked not required in the NOT REQUIRED sheet; [onEdit] then makes it required again.
  bool notReq = false;
  int ops = 0;
  num sec = 0;
  String status = '';
  Color color = ink(const Color(0xFF047857));
  bool approved = false, pending = false;
  VoidCallback? onEdit;
}

class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key});
  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  final _scroll = ScrollController();
  bool _busy = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Types already sent for this SRN / category.
  List<_Sent> _sent(AppState st, EntryDraft e) {
    final p = st.data!;
    final out = <String, _Sent>{};
    _Sent get(String key, String manpower) => out.putIfAbsent(key, () => _Sent(key, sectionLabel(e.category, key, manpower)));
    final bl = p.bulletin(e.category, e.srn);
    final pend = p.myPending.where((a) => a.covers(e.srn) && a.category == e.category && a.type == 'R&D').toList();
    final editPending = pend.any((a) => a.isEditMode);
    if (bl != null) {
      for (final op in bl.ops) {
        if (op.rndTime <= 0) continue;
        final key = sectionOf(e.category, op.manpower, op.machine);
        final x = get(key, op.manpower);
        x.ops++;
        x.sec += op.rndAt100;
        x.approved = true;
        x.status = 'Approved';
        x.color = ink(const Color(0xFF047857));
        if (!editPending && !e.editingAny) x.onEdit = () => e.startEdit(p, key);
      }
    }
    final me = p.access.email.toLowerCase();
    for (final a in pend) {
      if (a.isDeleteRequest) {
        for (final x in out.values) {
          x.status = 'Delete requested';
          x.color = ink(const Color(0xFFBE123C));
          x.onEdit = null;
        }
        continue;
      }
      final mine = a.submittedEmail.toLowerCase() == me;
      final seen = <String>{};
      for (final op in a.operations) {
        final key = sectionOf(e.category, op.manpowerType, op.machineType);
        if (seen.add(key) && a.isEditMode && out.containsKey(key)) {
          out[key]!.status = 'Edit · ${stageLabel(a.stage)}';
          out[key]!.color = stageColor(a.stage);
          out[key]!.onEdit = null;
          continue;
        }
        if (a.isEditMode) continue;
        final x = get(key, op.manpowerType);
        x.ops++;
        x.sec += n(op.time);
        x.pending = true;
        x.status = stageLabel(a.stage);
        x.color = stageColor(a.stage);
        x.onEdit = (mine && !a.pmReviewed && !e.editingAny) ? () => e.loadPending(a, p, section: key) : null;
      }
    }
    for (final it in st.outbox.items) {
      if (it.kind != 'submit') continue;
      final h = m(it.data['header']);
      final list = l(h['srnList']);
      if (list.isEmpty || s(m(list.first)['srn']) != e.srn || s(h['category']) != e.category) continue;
      for (final o in l(it.data['operations'])) {
        final x = get(sectionOf(e.category, s(m(o)['manpowerType']), s(m(o)['machineType'])), s(m(o)['manpowerType']));
        x.ops++;
        x.sec += n(m(o)['time']);
        x.pending = true;
        x.status = it.status == 'failed' ? 'Not sent' : 'Sending…';
        x.color = it.status == 'failed' ? ink(const Color(0xFFBE123C)) : ink(const Color(0xFF64748B));
      }
    }
    final order = sectionsFor(e.category).map((x) => x.key).toList();
    for (final key in order) {
      if (out.containsKey(key) || !st.isTypeNotRequired(e.srn, e.category, key)) continue;
      final x = get(key, '');
      x.notReq = true;
      x.status = 'Not required';
      x.color = ink(const Color(0xFF64748B));
      if (!e.editingAny) x.onEdit = () => _setNotRequired(context, st, key, false);
    }
    int rank(String k) {
      final i = order.indexOf(k);
      return i < 0 ? 99 : i;
    }
    final list = out.values.toList()..sort((a, b) => rank(a.mp).compareTo(rank(b.mp)));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = st.data!;
    return ListenableBuilder(
      listenable: st.entry,
      builder: (context, _) {
        final e = st.entry;
        final cs = Theme.of(context).colorScheme;
        final sent = e.srn.isEmpty ? <_Sent>[] : _sent(st, e);
        final sentTypes = {for (final x in sent) if (x.approved || x.pending || x.notReq) x.mp};
        final dup = e.mode == EntryMode.fresh && e.sec.isNotEmpty ? sent.where((x) => x.mp == e.sec && (x.approved || x.pending || x.notReq)).firstOrNull : null;
        final blockedTypes = e.mode == EntryMode.fresh ? e.typeCounts.keys.where(sentTypes.contains).toList() : <String>[];
        final rows = e.visibleOps;
        return Scaffold(
          appBar: AppBar(
            title: Text(e.mode == EntryMode.editRnd ? 'Edit bulletin' : (e.editing ? 'Edit pending' : 'Data Entry')),
            actions: [
              if (e.editingAny)
                TextButton(onPressed: () => e.nextType(), child: const Text('Cancel edit'))
              else if (e.sec.isNotEmpty && rows.isNotEmpty)
                IconButton(tooltip: 'Clear ${e.labelOf(e.sec)} rows', onPressed: () async {
                  if (await confirm(context, 'Clear rows', 'Remove all ${rows.length} ${e.labelOf(e.sec)} operation(s) entered? Other types stay.', yes: 'Clear', danger: true)) e.clearType();
                }, icon: const Icon(Icons.restart_alt_rounded)),
              const UserMenu(),
            ],
          ),
          body: Column(children: [
            Expanded(
              child: RefreshIndicator(
              onRefresh: () => st.load(silent: true),
              child: ListView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 16),
                children: [
                  _Header(
                    e: e, p: p, sent: sent, dup: dup,
                    canManage: !e.editingAny && p.bulletin(e.category, e.srn) != null && !p.myPending.any((a) => a.covers(e.srn) && a.category == e.category && a.type == 'R&D'),
                    onUndo: () => _undoLastEdit(context, st),
                    onDelete: () => _requestDelete(context, st),
                    onNotRequired: () => _setNotRequired(context, st, e.sec, true),
                  ),
                  if (e.srn.isNotEmpty && e.sec.isNotEmpty && (dup == null || rows.isNotEmpty)) ...[
                    const SizedBox(height: 8),
                    SectionLabel(
                      '${e.labelOf(e.sec)} operations · ${rows.where((o) => o.name.isNotEmpty || o.time.isNotEmpty).length}',
                      trailing: e.mode == EntryMode.fresh
                          ? TextButton.icon(onPressed: () => _copyFrom(context, st), icon: const Icon(Icons.copy_all_rounded, size: 16), label: const Text('Copy from SRN'), style: TextButton.styleFrom(visualDensity: VisualDensity.compact))
                          : null,
                    ),
                    if (rows.isNotEmpty)
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(children: [
                          for (var i = 0; i < rows.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            _OpTile(
                              key: rows[i].key, index: i, op: rows[i],
                              onTap: () => _openOpSheet(context, st, op: rows[i]),
                              confirmDelete: () => _confirmRemoveOp(context, e, rows[i]),
                              onDelete: () => _removeWithUndo(context, e, rows[i]),
                            ),
                          ],
                        ]),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text('No operations yet. Tap "Add operation".', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                      ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 48,
                      child: FilledButton.tonalIcon(
                        onPressed: () => _openOpSheet(context, st),
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        label: Text('Add ${e.labelOf(e.sec)} operation', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                      ),
                    ),
                  ],
                ],
              ),
              ),
            ),
            if (e.srn.isNotEmpty && ((e.sec.isNotEmpty && dup == null) || e.totalFilled > 0)) _BottomBar(busy: _busy, blocked: blockedTypes, onSubmit: () => _submit(context, st)),
          ]),
        );
      },
    );
  }

  Future<bool> _confirmRemoveOp(BuildContext context, EntryDraft e, OpDraft op) => confirm(
      context, 'Delete operation', 'Delete "${op.name.isEmpty ? 'this row' : op.name}" from ${e.labelOf(op.sec)}?', yes: 'Delete', danger: true);

  void _removeWithUndo(BuildContext context, EntryDraft e, OpDraft op) {
    final i = e.detach(op);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('"${op.name.isEmpty ? 'Row' : op.name}" removed'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: 'UNDO', onPressed: () => e.insertAt(i, op)),
      ));
  }

  Future<void> _undoLastEdit(BuildContext context, AppState st) async {
    final e = st.entry;
    final ok = await confirm(context, 'Undo last approved edit',
        'The version of ${e.srn} (${e.category}) that was approved before the last edit will be sent for approval again. The current bulletin stays until it is approved.',
        yes: 'Send');
    if (!ok || !context.mounted) return;
    try {
      final msg = await st.restorePrevious(e.srn, e.category);
      if (context.mounted) toast(context, msg);
    } catch (err) {
      if (context.mounted) toast(context, err.toString(), error: true);
    }
  }

  Future<void> _requestDelete(BuildContext context, AppState st) async {
    final e = st.entry;
    final ctl = TextEditingController();
    final why = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_forever_outlined, color: ink(const Color(0xFFBE123C))),
        title: Text('Delete ${e.srn} bulletin?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('The whole ${e.category} R&D bulletin of ${e.srn} (all types) is removed once GM approves. It stays in the raw data sheet.',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(controller: ctl, autofocus: true, maxLines: 2, decoration: const InputDecoration(labelText: 'Reason')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFBE123C)),
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: const Text('Send delete request'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (why == null || !context.mounted) return;
    if (why.isEmpty) {
      toast(context, 'Please write the reason.', error: true);
      return;
    }
    try {
      final msg = await st.requestDelete(e.srn, e.category, why);
      if (context.mounted) toast(context, msg);
    } catch (err) {
      if (context.mounted) toast(context, err.toString(), error: true);
    }
  }

  /// Add (op == null) or edit one operation in a popup: photo, name, number of operations, time.
  Future<void> _openOpSheet(BuildContext context, AppState st, {OpDraft? op}) async {
    final e = st.entry;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => _OpSheet(
        st: st,
        op: op,
        onCopy: op == null ? null : () {
          final i = e.ops.indexOf(op);
          final c = OpDraft(name: op.name, manpower: op.manpower, machine: op.machine, op1pc: op.op1pcCtl.text, time: op.time, img: op.img, fromHeader: op.fromHeader);
          e.insertAt(i + 1, c);
        },
        onSave: (name, pc, time, manpower, machine, bytes, fileName, removePhoto) {
          final target = op ?? e.add(name: name, op1pc: pc, time: time, manpower: manpower, machine: machine);
          if (op != null) {
            op.nameCtl.text = name;
            op.op1pcCtl.text = pc;
            op.timeCtl.text = time;
            if (manpower.isNotEmpty) op.manpower = manpower;
            if (machine.isNotEmpty && e.needsMachineFor(op.sec)) op.machine = machine;
            op.suggested = false;
          }
          if (removePhoto) target.img = '';
          e.touch();
          if (bytes != null) _upload(st, target, bytes, fileName);
        },
      ),
    );
  }

  Future<void> _upload(AppState st, OpDraft op, Uint8List bytes, String fileName) async {
    op.uploading = true;
    st.entry.touch();
    try {
      op.img = await st.uploadImage(bytes, 'image/jpeg', fileName, st.entry.srn, op.name);
      if (mounted && op.img.startsWith('local:')) toast(context, 'Photo saved on phone, uploads with the bulletin.');
    } catch (err) {
      if (mounted) toast(context, 'Photo upload failed: $err', error: true);
    } finally {
      op.uploading = false;
      st.entry.touch();
    }
  }

  Future<void> _copyFrom(BuildContext context, AppState st) async {
    final e = st.entry;
    final p = st.data!;
    final opts = <SrnInfo>[];
    final srns = p.copySrns(e.category).entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    for (final x in srns) {
      if (x.key == e.srn) continue;
      final list = p.copyOps(e.category, x.key);
      if (list.isEmpty) continue;
      final k = list.where((o) => sectionOf(e.category, o.manpower, o.machine) == e.sec).length;
      final info = p.srn(x.key);
      opts.add(SrnInfo(srn: x.key, styleName: '${info?.styleName ?? ''} · ${list.length} ops${k > 0 ? ' ($k ${e.labelOf(e.sec)})' : ''}${x.value ? ' · not approved yet' : ''}', imageLink: info?.imageLink ?? ''));
    }
    if (opts.isEmpty) {
      toast(context, 'No other ${e.category} SRN has operations to copy.', error: true);
      return;
    }
    final from = await pickSrn(context, options: opts, title: 'Copy operations from');
    if (from == null || !context.mounted) return;
    final list = p.copyOps(e.category, from);
    final mine = list.where((o) => sectionOf(e.category, o.manpower, o.machine) == e.sec).toList();
    var all = true;
    if (e.sec.isNotEmpty && mine.isNotEmpty && mine.length < list.length) {
      final pick = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Copy from $from'),
          content: Text('${list.length} operations of all types (${e.labelOf(e.sec)}: ${mine.length}).'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Only ${e.labelOf(e.sec)}')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('All types')),
          ],
        ),
      );
      if (pick == null || !context.mounted) return;
      all = pick;
    } else if (e.sec.isNotEmpty && mine.length == list.length) {
      all = false;
    }
    if (all) {
      e.copyAll(list, p);
      toast(context, 'Copied ${list.length} operations of all types from $from. Check the times.');
    } else {
      e.copyFrom(mine, p.sectionManpower(e.category, e.sec));
      toast(context, 'Copied ${mine.length} operations from $from. Check the times.');
    }
  }

  /// Shows operation type [key]; the manpower is always picked by hand.
  static void _showType(Payload p, EntryDraft e, String key) {
    e.setType(key, '');
  }

  /// Marks the operation type [key] of the selected SRN as not required ([on]) or required again.
  Future<void> _setNotRequired(BuildContext context, AppState st, String key, bool on) async {
    final e = st.entry;
    final p = st.data!;
    final x = sectionByKey(e.category, key);
    if (x == null) return;
    final label = x.label;
    final ok = await confirm(
      context,
      on ? '$label not required?' : '$label required again?',
      on
          ? '$label operations are not required for ${e.srn} (${e.category}). This is saved in the NOT REQUIRED sheet.'
          : '$label operations will be required again for ${e.srn} (${e.category}).',
      yes: on ? 'Not required' : 'Required',
      danger: on,
    );
    if (!ok || !context.mounted) return;
    try {
      final msg = await st.markTypeNotRequired(e.srn, e.category, p.mpName(x.mpKeys.first), on);
      if (context.mounted) toast(context, msg);
    } catch (err) {
      if (context.mounted) toast(context, err.toString(), error: true);
    }
  }

  /// Review before submit: every type with its operations, times and totals.
  Future<bool?> _review(BuildContext context, Payload p, EntryDraft e) {
    final groups = <String, List<OpDraft>>{};
    for (final o in e.filledOps) {
      groups.putIfAbsent(o.sec, () => []).add(o);
    }
    num all = 0;
    for (final o in e.filledOps) {
      all += o.timeNum;
    }
    final action = e.editing ? 'Save' : (e.mode == EntryMode.editRnd ? 'Send edit' : 'Submit');
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Review · ${e.srn}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('${e.category} · ${groups.length} type(s) · ${e.totalFilled} operations · total ${_fmtT(all)} s (${(all / 60).toStringAsFixed(2)} min)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
              ]),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                children: [
                  for (final g in groups.entries) ...[
                    Builder(builder: (_) {
                      num tt = 0;
                      for (final o in g.value) {
                        tt += o.timeNum;
                      }
                      final multi = p.sectionManpower(e.category, g.key).length > 1;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        clipBehavior: Clip.antiAlias,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Container(
                            color: cs.primary.withValues(alpha: 0.08),
                            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                            child: Row(children: [
                              Expanded(child: Text(e.labelOf(g.key), style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: cs.primary))),
                              Text('${g.value.length} ops · ${_fmtT(tt)} s · ${(tt / 60).toStringAsFixed(2)} min', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                            ]),
                          ),
                          if (g.value.any((o) => o.machine.isNotEmpty))
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                              child: Text(
                                // e.g. "Stitching Machine: 5 ops · MI machine: 2 ops"
                                () {
                                  final byMc = <String, int>{};
                                  for (final o in g.value) {
                                    if (o.machine.isNotEmpty) byMc.update(o.machine, (v) => v + 1, ifAbsent: () => 1);
                                  }
                                  return byMc.entries.map((x) => '${x.key}: ${x.value} ops').join(' · ');
                                }(),
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
                              ),
                            ),
                          for (var i = 0; i < g.value.length; i++)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
                              child: Row(children: [
                                SizedBox(width: 22, child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))),
                                if (g.value[i].img.isNotEmpty) ...[
                                  SrnThumb(g.value[i].img, size: 34, radius: 6, title: g.value[i].name),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(g.value[i].name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                                    Text(
                                      [
                                        '${g.value[i].op1pcCtl.text.trim().isEmpty ? '1' : g.value[i].op1pcCtl.text.trim()} ops',
                                        if (multi) g.value[i].manpower,
                                        if (g.value[i].machine.isNotEmpty) g.value[i].machine,
                                      ].join(' · '),
                                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                                    ),
                                  ]),
                                ),
                                Text('${_fmtT(g.value[i].timeNum)} s', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: ink(const Color(0xFF3730A3)))),
                              ]),
                            ),
                        ]),
                      );
                    }),
                  ],
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(children: [
                  OutlinedButton(onPressed: () => Navigator.pop(ctx, false), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)), child: const Text('Back to edit')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.cloud_upload_rounded), label: Text('$action ${e.totalFilled} operations')),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }

  Future<void> _submit(BuildContext context, AppState st) async {
    final e = st.entry;
    final p = st.data!;
    if (e.totalFilled == 0) {
      toast(context, 'Please add at least one operation.', error: true);
      return;
    }
    final noMc = e.mode == EntryMode.fresh ? e.typeWithoutMachine() : (e.needsMachine && e.mc.isEmpty ? e.sec : null);
    if (noMc != null) {
      _showType(p, e, noMc);
      toast(context, 'Please select the machine for ${e.labelOf(noMc)}.', error: true);
      return;
    }
    if (e.ops.any((o) => o.uploading)) {
      toast(context, 'A photo is still uploading. Please wait a moment.', error: true);
      return;
    }
    final bad = e.firstInvalid();
    if (bad != null) {
      _showType(p, e, bad.sec);
      final i = e.visibleOps.indexOf(bad);
      toast(context, '${e.labelOf(bad.sec)} row ${i + 1}${bad.name.isEmpty ? '' : ' "${bad.name}"'} ${bad.manpower.isEmpty ? 'needs a manpower' : 'needs a name and a time'}.', error: true);
      return;
    }
    final counts = e.typeCounts;
    if (await _review(context, p, e) != true || !context.mounted) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      final label = '${e.category} · ${counts.keys.map(e.labelOf).join(', ')}';
      final String msg;
      if (e.editing) {
        msg = await st.updatePending(e.pendingId, e.collect(p), srn: e.srn, label: label);
      } else {
        msg = await st.submitBulletin(e.payload(p), srn: e.srn, label: label);
      }
      if (!context.mounted) return;
      toast(context, msg);
      e.nextType();
      _scroll.jumpTo(0);
    } catch (err) {
      if (context.mounted) toast(context, err.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// SRN, category, what is already sent, and the type / manpower / machine for the whole submission.
class _Header extends StatelessWidget {
  const _Header({required this.e, required this.p, required this.sent, required this.dup, this.canManage = false, this.onUndo, this.onDelete, this.onNotRequired});
  final EntryDraft e;
  final Payload p;
  final List<_Sent> sent;
  final _Sent? dup;
  /// An approved bulletin exists and nothing is waiting: undo-edit and delete are offered.
  final bool canManage;
  final VoidCallback? onUndo, onDelete;
  /// Marks the chosen operation type as not required for this SRN.
  final VoidCallback? onNotRequired;

  /// Operation type keys: the fixed list of the category, then any other type found in the rows (old data).
  List<String> _types() {
    final list = sectionsFor(e.category).map((x) => x.key).toList();
    for (final o in e.ops) {
      if (!list.contains(o.sec)) list.add(o.sec);
    }
    return list;
  }

  /// Manpower allowed in the chosen type; an old unknown type keeps the manpower of its rows.
  List<String> _manpower() {
    final list = p.sectionManpower(e.category, e.sec);
    if (list.isNotEmpty) return list;
    return {for (final o in e.ops) if (o.sec == e.sec) o.manpower, if (e.mp.isNotEmpty) e.mp}.toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = e.srn.isEmpty ? null : p.srn(e.srn);
    final lockTop = e.editingAny;
    final types = _types();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // 1. SRN + category + date
          Row(children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: lockTop ? null : () async {
                  final key = e.category == 'Packing' ? 'pkRnd' : 'mkRnd';
                  final due = {for (final it in p.pending) if (it.tasks.any((t) => t.key == key)) it.srn};
                  final opts = [
                    ...p.srns.where((o) => due.contains(o.srn)).map((o) => SrnInfo(srn: o.srn, styleName: 'R&D pending · ${o.styleName}', shippingQty: o.shippingQty, imageLink: o.imageLink, orderDate: o.orderDate)),
                    ...p.srns.where((o) => !due.contains(o.srn)),
                  ];
                  final v = await pickSrn(context, options: opts);
                  if (v == null || v == e.srn || !context.mounted) return;
                  if (e.totalFilled > 0 && !await confirm(context, 'Change SRN', 'The ${e.totalFilled} operation(s) entered for ${e.srn} will be cleared. Continue?', yes: 'Change', danger: true)) return;
                  e.setSrn(v, p);
                },
                child: Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(10), border: Border.all(color: e.srn.isEmpty ? cs.primary.withValues(alpha: 0.6) : cs.outlineVariant.withValues(alpha: 0.5))),
                  child: Row(children: [
                    if (info != null) SrnThumb(info.imageLink, size: 36, radius: 8) else Icon(Icons.qr_code_2_rounded, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: info == null
                          ? Text(e.srn.isEmpty ? 'Select SRN' : e.srn, style: TextStyle(fontWeight: FontWeight.w800, color: e.srn.isEmpty ? cs.primary : cs.onSurface))
                          : Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(info.srn, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                              Text('${info.styleName} · Qty ${info.shippingQty}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                            ]),
                    ),
                    Icon(lockTop ? Icons.lock_outline_rounded : Icons.expand_more_rounded, size: 18, color: cs.outline),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _CatToggle(value: e.category, onChanged: lockTop ? null : (v) async {
              if (v == e.category) return;
              if (e.totalFilled > 0 && !await confirm(context, 'Change to $v', 'The ${e.totalFilled} operation(s) entered for ${e.category} will be cleared. Continue?', yes: 'Change', danger: true)) return;
              e.setCategory(v, p);
            }),
          ]),
          if (e.srn.isNotEmpty && !lockTop && _siblings(p, e.srn).length > 1) ...[
            const SizedBox(height: 6),
            _MasterNote(srn: e.srn, siblings: _siblings(p, e.srn), onlySrn: e.onlySrn, onChanged: e.setOnlySrn),
          ],
          if (e.srn.isNotEmpty) ...[
            // 2. What is already sent for this SRN
            if (sent.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(color: wash(const Color(0xFFF8FAFC)), borderRadius: BorderRadius.circular(10), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5))),
                padding: const EdgeInsets.fromLTRB(8, 6, 4, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text('ALREADY SUBMITTED · ${e.srn}', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: cs.onSurfaceVariant))),
                    if (canManage)
                      SizedBox(
                        height: 26, width: 30,
                        child: PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          tooltip: 'More',
                          icon: Icon(Icons.more_horiz_rounded, size: 20, color: cs.onSurfaceVariant),
                          onSelected: (v) => v == 'undo' ? onUndo?.call() : onDelete?.call(),
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'undo', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.undo_rounded), title: Text('Undo last approved edit'))),
                            PopupMenuItem(value: 'delete', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.delete_forever_outlined, color: ink(const Color(0xFFBE123C))), title: Text('Delete this bulletin'))),
                          ],
                        ),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  for (final x in sent)
                    SizedBox(
                      height: 30,
                      child: Row(children: [
                        Icon(x.notReq ? Icons.block_rounded : (x.approved && !x.pending ? Icons.check_circle_rounded : Icons.schedule_rounded), size: 15, color: x.color),
                        const SizedBox(width: 6),
                        Expanded(child: Text(x.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
                        if (!x.notReq) Text('${x.ops} ops · ${(x.sec / 60).toStringAsFixed(2)} m', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                        const SizedBox(width: 6),
                        Text(x.status, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: x.color)),
                        SizedBox(
                          width: 34,
                          child: x.onEdit == null
                              ? null
                              : IconButton(
                                  padding: EdgeInsets.zero, visualDensity: VisualDensity.compact, tooltip: x.notReq ? 'Make required again' : 'Edit', onPressed: x.onEdit,
                                  icon: Icon(x.notReq ? Icons.undo_rounded : Icons.edit_outlined, size: 16, color: cs.primary),
                                ),
                        ),
                      ]),
                    ),
                ]),
              ),
            ],
            // 3. Type / manpower / machine for this submission
            const SizedBox(height: 10),
            Text(e.mode == EntryMode.fresh ? 'OPERATION TYPE' : 'EDITING TYPE', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in types)
                Builder(builder: (_) {
                  final n = e.typeCounts[k] ?? 0;
                  final done = sent.where((x) => x.mp == k).firstOrNull;
                  final label = e.labelOf(k);
                  return ChoiceChip(
                    label: Text(n > 0 ? '$label · $n' : label),
                    selected: e.sec == k,
                    visualDensity: VisualDensity.compact,
                    showCheckmark: false,
                    avatar: done == null ? null : Icon(done.notReq ? Icons.block_rounded : Icons.check_rounded, size: 14, color: done.color),
                    onSelected: (_) => e.setType(k, ''),
                  );
                }),
            ]),
            if (e.sec.isNotEmpty && dup == null) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: _Drop(
                    label: 'Manpower', value: e.mp, icon: Icons.person_outline_rounded,
                    items: _manpower(),
                    onChanged: (v) => e.setManpower(v),
                  ),
                ),
                if (e.needsMachine) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Drop(
                      label: 'Machine', value: e.mc, icon: Icons.precision_manufacturing_outlined,
                      items: {...p.machineTypes, if (e.mc.isNotEmpty) e.mc}.toList(),
                      onChanged: (v) => e.setMachine(v),
                    ),
                  ),
                ],
              ]),
              if (e.mode == EntryMode.fresh && onNotRequired != null && sectionByKey(e.category, e.sec) != null && !e.ops.any((o) => o.sec == e.sec))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onNotRequired,
                    style: TextButton.styleFrom(foregroundColor: cs.error, visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4)),
                    icon: const Icon(Icons.block_rounded, size: 17),
                    label: Text('${e.labelOf(e.sec)} not required for this SRN'),
                  ),
                ),
            ],
            if (dup != null) ...[
              const SizedBox(height: 8),
              _Note(
                color: dup!.notReq ? ink(const Color(0xFF475569)) : ink(const Color(0xFFB45309)),
                icon: dup!.notReq ? Icons.block_rounded : Icons.info_outline_rounded,
                text: dup!.notReq
                    ? '${dup!.label} is marked not required for this SRN.'
                    : '${dup!.label} is already submitted (${dup!.status}). Pick another type${dup!.onEdit != null ? ' or edit it' : ''}.',
                action: dup!.onEdit == null ? null : TextButton(onPressed: dup!.onEdit, child: Text(dup!.notReq ? 'Undo' : 'Edit')),
              ),
            ],
            if (e.mode == EntryMode.editRnd)
              const Padding(padding: EdgeInsets.only(top: 8), child: _Note(color: Color(0xFF9A3412), icon: Icons.edit_outlined, text: 'Editing the approved bulletin · times at 100% efficiency · changes go for review')),
            if (e.editing)
              const Padding(padding: EdgeInsets.only(top: 8), child: _Note(color: Color(0xFF9A3412), icon: Icons.pending_actions_outlined, text: 'Editing your pending submission')),
          ],
        ]),
      ),
    );
  }
}

class _CatToggle extends StatelessWidget {
  const _CatToggle({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget seg(String v) {
      final on = value == v;
      return InkWell(
        onTap: onChanged == null || on ? null : () => onChanged!(v),
        child: Container(
          width: 64, alignment: Alignment.center,
          color: on ? catColor(v) : Colors.transparent,
          child: Text(v, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: on ? Colors.white : cs.onSurfaceVariant)),
        ),
      );
    }

    return Container(
      height: 50,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: cs.outlineVariant)),
      child: Column(children: [Expanded(child: seg('Making')), Expanded(child: seg('Packing'))]),
    );
  }
}

class _Drop extends StatelessWidget {
  const _Drop({required this.label, required this.value, required this.items, required this.onChanged, this.icon});
  final String label, value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final empty = value.isEmpty;
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 8, right: 2),
      decoration: BoxDecoration(
        color: empty ? wash(const Color(0xFFFFFBEB)) : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: empty ? edge(const Color(0xFFFDE68A)) : cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: empty ? null : value,
          isExpanded: true, isDense: true,
          hint: Row(children: [if (icon != null) Icon(icon, size: 15, color: ink(const Color(0xFFB45309))), const SizedBox(width: 4), Text('Select $label', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink(const Color(0xFFB45309))))]),
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.onSurface, fontFamily: 'Inter'),
          selectedItemBuilder: (_) => items.map((x) => Row(children: [if (icon != null) Icon(icon, size: 15, color: cs.primary), const SizedBox(width: 4), Flexible(child: Text(x, overflow: TextOverflow.ellipsis))])).toList(),
          items: items.map((x) => DropdownMenuItem(value: x, child: Text(x, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => onChanged(v ?? ''),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.color, required this.icon, required this.text, this.action});
  final Color color;
  final IconData icon;
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final c = ink(color);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(color: c.withValues(alpha: darkUi ? 0.12 : 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withValues(alpha: 0.25))),
      child: Row(children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c))),
        if (action != null) action!,
      ]),
    );
  }
}

/// One operation in the list: tap to edit, swipe left to delete.
class _OpTile extends StatelessWidget {
  const _OpTile({super.key, required this.index, required this.op, required this.onTap, required this.onDelete, required this.confirmDelete});
  final Future<bool> Function() confirmDelete;
  final int index;
  final OpDraft op;
  final VoidCallback onTap, onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pc = op.op1pcCtl.text.trim().isEmpty ? '1' : op.op1pcCtl.text.trim();
    final bad = op.name.isEmpty || op.timeNum <= 0;
    return Dismissible(
      key: ValueKey('d${op.key}'),
      direction: DismissDirection.endToStart,
      background: Container(color: wash(const Color(0xFFFFE4E6)), alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 18), child: Icon(Icons.delete_outline_rounded, color: ink(const Color(0xFFBE123C)))),
      confirmDismiss: (_) => confirmDelete(),
      onDismissed: (_) => onDelete(),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Row(children: [
            SizedBox(width: 22, child: Text('${index + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.outline))),
            SizedBox(
              width: 40, height: 40,
              child: op.uploading
                  ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : op.img.isNotEmpty
                      ? SrnThumb(op.img, size: 40, radius: 8, title: op.name)
                      : Container(decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.photo_camera_outlined, size: 18, color: cs.outline)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(op.name.isEmpty ? 'No name' : op.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: op.name.isEmpty ? cs.error : cs.onSurface)),
                Text(op.sec == 'stitching' ? ['$pc ops', if (op.manpower.isNotEmpty) op.manpower, if (op.machine.isNotEmpty) op.machine].join(' · ') : '$pc ops',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: bad ? wash(const Color(0xFFFFFBEB)) : wash(const Color(0xFFEEF2FF)), borderRadius: BorderRadius.circular(8)),
              child: Text(op.timeNum > 0 ? '${op.time}s' : 'time?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: bad ? ink(const Color(0xFFB45309)) : ink(const Color(0xFF3730A3)))),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.outlineVariant),
          ]),
        ),
      ),
    );
  }
}

typedef _SaveOp = void Function(String name, String pc, String time, String manpower, String machine, Uint8List? bytes, String fileName, bool removePhoto);

/// Popup to add / edit one operation. "Add & next" keeps it open for the next operation.
class _OpSheet extends StatefulWidget {
  const _OpSheet({required this.st, required this.op, required this.onSave, this.onCopy});
  final AppState st;
  final OpDraft? op;
  final _SaveOp onSave;
  final VoidCallback? onCopy;
  @override
  State<_OpSheet> createState() => _OpSheetState();
}

class _OpSheetState extends State<_OpSheet> {
  late final _name = TextEditingController(text: widget.op?.name ?? '');
  late final _time = TextEditingController(text: widget.op?.time ?? '');
  final _nameFocus = FocusNode();
  final _timeFocus = FocusNode();
  late int _pc = int.tryParse(widget.op?.op1pcCtl.text.trim() ?? '') ?? 1;
  /// Manpower of this row (Stitching offers Operator and Helper).
  late String _mp = widget.op?.manpower ?? widget.st.entry.mp;
  /// Machine of this row (stitching): the row's own, or the one chosen at the top for a new row.
  late String _mc = (widget.op?.machine.isNotEmpty ?? false) ? widget.op!.machine : widget.st.entry.mc;
  Uint8List? _bytes;
  String _fileName = 'photo.jpg';
  bool _removePhoto = false;
  int _added = 0;

  bool get _edit => widget.op != null;

  @override
  void dispose() {
    _name.dispose();
    _time.dispose();
    _nameFocus.dispose();
    _timeFocus.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context, showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Take photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_rounded), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (src == null) return;
    final x = await ImagePicker().pickImage(source: src, maxWidth: 1200, maxHeight: 1200, imageQuality: 85);
    if (x == null) return;
    final b = await x.readAsBytes();
    if (!mounted) return;
    setState(() {
      _bytes = b;
      _fileName = x.name;
      _removePhoto = false;
    });
  }

  bool _save({required bool next}) {
    final name = _name.text.trim();
    final t = num.tryParse(_time.text.trim()) ?? 0;
    if (name.isEmpty) {
      toast(context, 'Enter the operation name.', error: true);
      _nameFocus.requestFocus();
      return false;
    }
    if (t <= 0) {
      toast(context, 'Enter the total time in seconds.', error: true);
      _timeFocus.requestFocus();
      return false;
    }
    if (_mp.isEmpty) {
      toast(context, 'Select the manpower.', error: true);
      return false;
    }
    HapticFeedback.lightImpact();
    if (widget.st.entry.needsMachineFor(widget.op?.sec ?? widget.st.entry.sec) && _mc.isEmpty) {
      toast(context, 'Select the machine.', error: true);
      return false;
    }
    widget.onSave(name, '${_pc < 1 ? 1 : _pc}', _time.text.trim(), _mp, _mc, _bytes, _fileName, _removePhoto);
    if (next) {
      setState(() {
        _added++;
        _name.clear();
        _time.clear();
        _pc = 1;
        _bytes = null;
        _removePhoto = false;
      });
      _nameFocus.requestFocus();
    } else {
      Navigator.of(context).pop();
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final e = widget.st.entry;
    final mps = widget.st.data?.sectionManpower(e.category, e.sec) ?? const <String>[];
    final curImg = widget.op?.img ?? '';
    final showOld = _bytes == null && !_removePhoto && curImg.isNotEmpty;

    Widget photo = InkWell(
      onTap: _pickPhoto,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 86, height: 86,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant)),
        child: _bytes != null
            ? Image.memory(_bytes!, fit: BoxFit.cover)
            : showOld
                ? SrnThumb(curImg, size: 86, radius: 12, tappable: false)
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_a_photo_outlined, color: cs.primary),
                    const SizedBox(height: 4),
                    Text('Photo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.primary)),
                  ]),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(_edit ? 'Edit ${e.labelOf(widget.op!.sec)} operation' : 'Add ${e.labelOf(e.sec)} operation', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            if (_added > 0) Pill('$_added added', color: const Color(0xFF047857)),
          ]),
          if (e.needsMachineFor(widget.op?.sec ?? e.sec)) ...[
            const SizedBox(height: 10),
            _Drop(
              label: 'Machine', value: _mc, icon: Icons.precision_manufacturing_outlined,
              items: {...widget.st.data?.machineTypes ?? const <String>[], if (_mc.isNotEmpty) _mc}.toList(),
              onChanged: (v) => setState(() => _mc = v),
            ),
          ],
          if (mps.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('Manpower', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
              for (final x in mps)
                ChoiceChip(label: Text(x), selected: _mp == x, showCheckmark: false, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => _mp = x)),
            ]),
          ],
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              photo,
              if (_bytes != null || showOld)
                TextButton(
                  onPressed: () => showPhoto(context, curImg, bytes: _bytes, title: _name.text.trim()),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('View', style: TextStyle(fontSize: 11.5)),
                ),
              if (_bytes != null || showOld)
                TextButton(
                  onPressed: () async {
                    if (!await confirm(context, 'Remove photo', 'Remove the photo of this operation?', yes: 'Remove', danger: true)) return;
                    setState(() {
                      _bytes = null;
                      _removePhoto = true;
                    });
                  },
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Remove', style: TextStyle(fontSize: 11.5)),
                ),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _name,
                  focusNode: _nameFocus,
                  autofocus: !_edit,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _timeFocus.requestFocus(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(labelText: 'Operation name'),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  // number of operations
                  Container(
                    height: 46,
                    decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(visualDensity: VisualDensity.compact, onPressed: _pc <= 1 ? null : () => setState(() => _pc--), icon: const Icon(Icons.remove_rounded, size: 18)),
                      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('$_pc', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        Text('ops', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                      ]),
                      IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => _pc++), icon: const Icon(Icons.add_rounded, size: 18)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _time,
                      focusNode: _timeFocus,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(next: !_edit),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink(const Color(0xFF3730A3))),
                      decoration: InputDecoration(labelText: 'Total time', suffixText: 'sec', fillColor: wash(const Color(0xFFEEF2FF))),
                    ),
                  ),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          if (_edit)
            Row(children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final op = widget.op!;
                  if (!await confirm(context, 'Delete operation', 'Delete "${op.name.isEmpty ? 'this row' : op.name}"?', yes: 'Delete', danger: true)) return;
                  if (!context.mounted) return;
                  widget.st.entry.remove(op);
                  Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(foregroundColor: cs.error, minimumSize: const Size(0, 48)),
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
                label: const Text('Delete'),
              ),
              const SizedBox(width: 8),
              if (widget.onCopy != null)
                OutlinedButton.icon(
                  onPressed: () {
                    widget.onCopy!();
                    toast(context, 'Copy added below.');
                    Navigator.of(context).pop();
                  },
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy'),
                ),
              const SizedBox(width: 8),
              Expanded(child: SizedBox(height: 48, child: FilledButton(onPressed: () => _save(next: false), child: const Text('Save')))),
            ])
          else
            Row(children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                child: Text(_added > 0 ? 'Done' : 'Close'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(onPressed: () => _save(next: true), icon: const Icon(Icons.add_rounded), label: const Text('Add & next')),
                ),
              ),
            ]),
        ]),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.busy, required this.blocked, required this.onSubmit});
  final bool busy;
  /// Types in the form that are already submitted for this SRN.
  final List<String> blocked;
  final VoidCallback onSubmit;
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final e = st.entry;
    final p = st.data!;
    final cs = Theme.of(context).colorScheme;
    var ops = 0;
    num time = 0, cost = 0;
    for (final o in e.filledOps) {
      if (o.timeNum <= 0) continue;
      ops++;
      time += o.timeNum;
      cost += p.cost(o.manpower, o.timeNum);
    }
    final types = e.typeCounts.keys.toList();
    final label = e.editing ? 'Save' : (e.mode == EntryMode.editRnd ? 'Send edit' : 'Submit');
    return Material(
      color: cs.surface, elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('${e.srn} · ${types.isEmpty ? e.labelOf(e.sec) : types.length == 1 ? e.labelOf(types.first) : '${types.length} types'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: cs.primary)),
                if (blocked.isNotEmpty)
                  Text('${blocked.map(e.labelOf).join(', ')} already submitted or not required · remove those rows', maxLines: 2, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: cs.error))
                else
                  Text('$ops ops · ${(time / 60).toStringAsFixed(2)} min · ₹${cost.toStringAsFixed(2)}/pc', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5)),
              ]),
            ),
            FilledButton.icon(
              onPressed: busy || blocked.isNotEmpty ? null : onSubmit,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
              icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.cloud_upload_rounded, size: 20),
              label: Text(busy ? 'Saving…' : label),
            ),
          ]),
        ),
      ),
    );
  }
}


String _srnBase(String srn) {
  final s = srn.trim().toUpperCase();
  final b = s.replaceAll(RegExp(r'[A-Z]+$'), '');
  return RegExp(r'\d$').hasMatch(b) ? b : s;
}

/// Every SRN of the order list with the same master number (634A, 634B, 634C), sorted.
List<String> _siblings(Payload p, String srn) {
  final base = _srnBase(srn);
  final out = p.srns.where((o) => _srnBase(o.srn) == base).map((o) => o.srn).toSet()..add(srn);
  return out.toList()..sort();
}

/// Master SRN note with the "Only this SRN" switch (the A / B / C bulletins differ now and then).
class _MasterNote extends StatelessWidget {
  const _MasterNote({required this.srn, required this.siblings, required this.onlySrn, required this.onChanged});
  final String srn;
  final List<String> siblings;
  final bool onlySrn;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = _srnBase(srn);
    return Container(
      decoration: BoxDecoration(color: wash(const Color(0xFFFDF4FF)), borderRadius: BorderRadius.circular(10), border: Border.all(color: ink(const Color(0xFFF5D0FE)))),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(onlySrn ? 'Only $srn' : 'Master SRN $base', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: ink(const Color(0xFFA21CAF)))),
            Text(onlySrn ? 'Saved in $srn only. The other SRNs of $base keep their own bulletin.' : 'One request for ${siblings.join(', ')}. On approval it is saved in all of them.',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ]),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Only this SRN', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
          Switch(value: onlySrn, onChanged: onChanged),
        ]),
      ]),
    );
  }
}
