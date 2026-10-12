import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';

String _fmtT(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

/// One operation type already sent for the selected SRN (approved, pending or still on the phone).
class _Sent {
  _Sent(this.mp);
  final String mp;
  int ops = 0;
  num sec = 0;
  String status = '';
  Color color = const Color(0xFF047857);
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
    _Sent get(String mp) => out.putIfAbsent(mp, () => _Sent(mp));
    final bl = p.bulletin(e.category, e.srn);
    final pend = p.myPending.where((a) => a.srn == e.srn && a.category == e.category && a.type == 'R&D').toList();
    final editPending = pend.any((a) => a.isEditMode);
    if (bl != null) {
      for (final op in bl.ops) {
        if (op.rndTime <= 0) continue;
        final x = get(op.manpower);
        x.ops++;
        x.sec += op.rndAt100;
        x.approved = true;
        x.status = 'Approved';
        x.color = const Color(0xFF047857);
        if (!editPending && !e.editingAny) x.onEdit = () => e.startEdit(p, op.manpower);
      }
    }
    final me = p.access.email.toLowerCase();
    for (final a in pend) {
      final mine = a.submittedEmail.toLowerCase() == me;
      final seen = <String>{};
      for (final op in a.operations) {
        if (seen.add(op.manpowerType) && a.isEditMode && out.containsKey(op.manpowerType)) {
          out[op.manpowerType]!.status = 'Edit · ${stageLabel(a.stage)}';
          out[op.manpowerType]!.color = stageColor(a.stage);
          out[op.manpowerType]!.onEdit = null;
          continue;
        }
        if (a.isEditMode) continue;
        final x = get(op.manpowerType);
        x.ops++;
        x.sec += n(op.time);
        x.pending = true;
        x.status = stageLabel(a.stage);
        x.color = stageColor(a.stage);
        x.onEdit = (mine && !a.pmReviewed && !e.editingAny) ? () => e.loadPending(a, p, manpower: op.manpowerType) : null;
      }
    }
    for (final it in st.outbox.items) {
      if (it.kind != 'submit') continue;
      final h = m(it.data['header']);
      final list = l(h['srnList']);
      if (list.isEmpty || s(m(list.first)['srn']) != e.srn || s(h['category']) != e.category) continue;
      for (final o in l(it.data['operations'])) {
        final x = get(s(m(o)['manpowerType']));
        x.ops++;
        x.sec += n(m(o)['time']);
        x.pending = true;
        x.status = it.status == 'failed' ? 'Not sent' : 'Sending…';
        x.color = it.status == 'failed' ? const Color(0xFFBE123C) : const Color(0xFF64748B);
      }
    }
    final list = out.values.toList()..sort((a, b) => roleRank(a.mp) != roleRank(b.mp) ? roleRank(a.mp).compareTo(roleRank(b.mp)) : a.mp.compareTo(b.mp));
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
        final dup = e.mode == EntryMode.fresh && e.mp.isNotEmpty ? sent.where((x) => x.mp == e.mp && (x.approved || x.pending)).firstOrNull : null;
        final rows = e.visibleOps;
        return Scaffold(
          appBar: AppBar(
            title: Text(e.mode == EntryMode.editRnd ? 'Edit bulletin' : (e.editing ? 'Edit pending' : 'Data Entry')),
            actions: [
              if (e.editingAny)
                TextButton(onPressed: () => e.nextType(), child: const Text('Cancel edit'))
              else if (e.ops.isNotEmpty)
                IconButton(tooltip: 'Clear rows', onPressed: () async {
                  if (await confirm(context, 'Clear rows', 'Remove all rows entered for this type?', yes: 'Clear', danger: true)) e.nextType();
                }, icon: const Icon(Icons.restart_alt_rounded)),
              const UserMenu(),
            ],
          ),
          body: Column(children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 16),
                children: [
                  _Header(e: e, p: p, sent: sent, dup: dup),
                  if (e.srn.isNotEmpty && e.mp.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SectionLabel(
                      '${roleLabel(e.mp)} operations · ${rows.where((o) => o.name.isNotEmpty || o.time.isNotEmpty).length}',
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
                            _OpTile(key: rows[i].key, index: i, op: rows[i], onTap: () => _openOpSheet(context, st, op: rows[i]), onDelete: () => e.remove(rows[i])),
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
                        label: Text('Add ${roleLabel(e.mp)} operation', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (e.srn.isNotEmpty && e.mp.isNotEmpty) _BottomBar(busy: _busy, blocked: dup != null, onSubmit: () => _submit(context, st)),
          ]),
        );
      },
    );
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
        onSave: (name, pc, time, bytes, fileName, removePhoto) {
          final target = op ?? e.add(name: name, op1pc: pc, time: time);
          if (op != null) {
            op.nameCtl.text = name;
            op.op1pcCtl.text = pc;
            op.timeCtl.text = time;
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
    final src = e.category == 'Packing' ? p.packing : p.submitted;
    final opts = <SrnInfo>[];
    for (final bl in src) {
      if (bl.srn == e.srn) continue;
      final k = bl.ops.where((o) => o.manpower == e.mp).length;
      if (k > 0) opts.add(SrnInfo(srn: bl.srn, styleName: '${bl.styleName} · $k ${roleLabel(e.mp)} ops', imageLink: bl.imageLink));
    }
    if (opts.isEmpty) {
      toast(context, 'No other SRN has ${roleLabel(e.mp)} operations.', error: true);
      return;
    }
    final from = await pickSrn(context, options: opts, title: 'Copy ${roleLabel(e.mp)} operations from');
    if (from == null || !context.mounted) return;
    final bl = p.bulletin(e.category, from);
    if (bl == null) return;
    final list = bl.ops.where((o) => o.manpower == e.mp).toList();
    e.copyFrom(list);
    toast(context, 'Copied ${list.length} operations from $from. Check the times.');
  }

  Future<void> _submit(BuildContext context, AppState st) async {
    final e = st.entry;
    final p = st.data!;
    if (e.needsMachine && e.mc.isEmpty) {
      toast(context, 'Please select the machine.', error: true);
      return;
    }
    if (e.filledCount == 0) {
      toast(context, 'Please add at least one operation.', error: true);
      return;
    }
    if (e.visibleOps.any((o) => o.uploading)) {
      toast(context, 'A photo is still uploading. Please wait a moment.', error: true);
      return;
    }
    final bad = e.firstInvalid();
    if (bad >= 0) {
      final o = e.visibleOps[bad];
      toast(context, 'Row ${bad + 1}${o.name.isEmpty ? '' : ' "${o.name}"'} needs a name and a time.', error: true);
      return;
    }
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      final label = '${e.category} · ${roleLabel(e.mp)}';
      final String msg;
      if (e.editing) {
        msg = await st.updatePending(e.pendingId, e.collect(p), srn: e.srn, label: label);
      } else {
        msg = await st.submitBulletin(e.payload(p), srn: e.srn, label: label);
      }
      if (!context.mounted) return;
      toast(context, '$msg  You can fill the next type now.');
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
  const _Header({required this.e, required this.p, required this.sent, required this.dup});
  final EntryDraft e;
  final Payload p;
  final List<_Sent> sent;
  final _Sent? dup;

  List<String> _types() {
    final list = p.manpowerTypes.map((x) => x.name).where((x) => mpAllowed(x, e.category)).toList();
    if (e.mp.isNotEmpty && !list.contains(e.mp)) list.add(e.mp);
    list.sort((a, b) => roleRank(a) != roleRank(b) ? roleRank(a).compareTo(roleRank(b)) : a.compareTo(b));
    return list;
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
                  if (v != null) e.setSrn(v, p);
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
            _CatToggle(value: e.category, onChanged: lockTop ? null : (v) => e.setCategory(v, p)),
          ]),
          if (e.srn.isNotEmpty) ...[
            // 2. What is already sent for this SRN
            if (sent.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5))),
                padding: const EdgeInsets.fromLTRB(8, 6, 4, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('ALREADY SUBMITTED · ${e.srn}', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  for (final x in sent)
                    SizedBox(
                      height: 30,
                      child: Row(children: [
                        Icon(x.approved && !x.pending ? Icons.check_circle_rounded : Icons.schedule_rounded, size: 15, color: x.color),
                        const SizedBox(width: 6),
                        Expanded(child: Text(roleLabel(x.mp), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
                        Text('${x.ops} ops · ${(x.sec / 60).toStringAsFixed(2)} m', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                        const SizedBox(width: 6),
                        Text(x.status, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: x.color)),
                        SizedBox(
                          width: 34,
                          child: x.onEdit == null
                              ? null
                              : IconButton(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact, tooltip: 'Edit', onPressed: x.onEdit, icon: Icon(Icons.edit_outlined, size: 16, color: cs.primary)),
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
              for (final t in types)
                ChoiceChip(
                  label: Text(roleLabel(t)),
                  selected: e.mp == t,
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                  avatar: sent.any((x) => x.mp == t) ? Icon(Icons.check_rounded, size: 14, color: sent.firstWhere((x) => x.mp == t).color) : null,
                  onSelected: (_) => e.setType(t),
                ),
            ]),
            if (e.mp.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: _Drop(
                    label: 'Manpower', value: e.mp, icon: Icons.person_outline_rounded,
                    items: {...types, e.mp}.toList(),
                    onChanged: (v) => e.setType(v),
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
            ],
            if (dup != null) ...[
              const SizedBox(height: 8),
              _Note(
                color: const Color(0xFFB45309), icon: Icons.info_outline_rounded,
                text: '${roleLabel(dup!.mp)} is already submitted (${dup!.status}). Pick another type${dup!.onEdit != null ? ' or edit it' : ''}.',
                action: dup!.onEdit == null ? null : TextButton(onPressed: dup!.onEdit, child: const Text('Edit')),
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
        color: empty ? const Color(0xFFFFFBEB) : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: empty ? const Color(0xFFFDE68A) : cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: empty ? null : value,
          isExpanded: true, isDense: true,
          hint: Row(children: [if (icon != null) Icon(icon, size: 15, color: const Color(0xFFB45309)), const SizedBox(width: 4), Text('Select $label', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFFB45309)))]),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color))),
        if (action != null) action!,
      ]),
    );
  }
}

/// One operation in the list: tap to edit, swipe left to delete.
class _OpTile extends StatelessWidget {
  const _OpTile({super.key, required this.index, required this.op, required this.onTap, required this.onDelete});
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
      background: Container(color: const Color(0xFFFFE4E6), alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 18), child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFBE123C))),
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
                      ? SrnThumb(op.img, size: 40, radius: 8)
                      : Container(decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.photo_camera_outlined, size: 18, color: cs.outline)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(op.name.isEmpty ? 'No name' : op.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: op.name.isEmpty ? cs.error : cs.onSurface)),
                Text('$pc ops', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: bad ? const Color(0xFFFFFBEB) : const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(8)),
              child: Text(op.timeNum > 0 ? '${op.time}s' : 'time?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: bad ? const Color(0xFFB45309) : const Color(0xFF3730A3))),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.outlineVariant),
          ]),
        ),
      ),
    );
  }
}

typedef _SaveOp = void Function(String name, String pc, String time, Uint8List? bytes, String fileName, bool removePhoto);

/// Popup to add / edit one operation. "Add & next" keeps it open for the next operation.
class _OpSheet extends StatefulWidget {
  const _OpSheet({required this.st, required this.op, required this.onSave});
  final AppState st;
  final OpDraft? op;
  final _SaveOp onSave;
  @override
  State<_OpSheet> createState() => _OpSheetState();
}

class _OpSheetState extends State<_OpSheet> {
  late final _name = TextEditingController(text: widget.op?.name ?? '');
  late final _time = TextEditingController(text: widget.op?.time ?? '');
  final _nameFocus = FocusNode();
  final _timeFocus = FocusNode();
  late int _pc = int.tryParse(widget.op?.op1pcCtl.text.trim() ?? '') ?? 1;
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

  void _useLib(LibOp x) {
    setState(() {
      _name.text = x.name;
      _pc = int.tryParse(x.op1pc) ?? 1;
      if (x.time > 0 && _time.text.trim().isEmpty) _time.text = _fmtT(x.time);
    });
    _timeFocus.requestFocus();
    _time.selection = TextSelection(baseOffset: 0, extentOffset: _time.text.length);
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
      toast(context, 'Enter the time in seconds.', error: true);
      _timeFocus.requestFocus();
      return false;
    }
    HapticFeedback.lightImpact();
    widget.onSave(name, '${_pc < 1 ? 1 : _pc}', _time.text.trim(), _bytes, _fileName, _removePhoto);
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
    final q = _name.text.trim().toLowerCase();
    final libAll = widget.st.library(e.category);
    final libType = libAll.where((x) => x.manpower.toLowerCase() == e.mp.toLowerCase()).toList();
    final lib = libType.isEmpty ? libAll : libType;
    final terms = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final hits = q.length < 2 ? <LibOp>[] : lib.where((x) => terms.every(x.key.contains) && x.key != q.replaceAll(RegExp(r'\s+'), ' ')).take(4).toList();
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
                ? SrnThumb(curImg, size: 86, radius: 12)
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
            Expanded(child: Text(_edit ? 'Edit operation' : 'Add ${roleLabel(e.mp)} operation', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            if (_added > 0) Pill('$_added added', color: const Color(0xFF047857)),
          ]),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              photo,
              if (_bytes != null || showOld)
                TextButton(
                  onPressed: () => setState(() {
                    _bytes = null;
                    _removePhoto = true;
                  }),
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
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF3730A3)),
                      decoration: const InputDecoration(labelText: 'Time', suffixText: 'sec', fillColor: Color(0xFFEEF2FF)),
                    ),
                  ),
                ]),
              ]),
            ),
          ]),
          if (hits.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('FROM PAST BULLETINS', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            for (final x in hits)
              _SugRow(title: x.name, sub: '${x.op1pc} ops · ${x.time > 0 ? '${_fmtT(x.time)}s' : '—'} · used ${x.count}×', onTap: () => _useLib(x)),
          ],
          const SizedBox(height: 14),
          if (_edit)
            Row(children: [
              OutlinedButton.icon(
                onPressed: () {
                  widget.st.entry.remove(widget.op!);
                  Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(foregroundColor: cs.error, minimumSize: const Size(0, 48)),
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
                label: const Text('Delete'),
              ),
              const SizedBox(width: 10),
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

class _SugRow extends StatelessWidget {
  const _SugRow({required this.title, required this.sub, required this.onTap});
  final String title, sub;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface)),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                ]),
              ),
              Icon(Icons.north_west_rounded, color: cs.primary, size: 18),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.busy, required this.blocked, required this.onSubmit});
  final bool busy, blocked;
  final VoidCallback onSubmit;
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final e = st.entry;
    final p = st.data!;
    final cs = Theme.of(context).colorScheme;
    var ops = 0;
    num time = 0, cost = 0;
    for (final o in e.visibleOps) {
      if (o.timeNum <= 0) continue;
      ops++;
      time += o.timeNum;
      cost += p.cost(e.mp, o.timeNum);
    }
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
                Text('${e.srn} · ${roleLabel(e.mp)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: cs.primary)),
                Text('$ops ops · ${(time / 60).toStringAsFixed(2)} min · ₹${cost.toStringAsFixed(2)}/pc', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5)),
              ]),
            ),
            FilledButton.icon(
              onPressed: busy || blocked ? null : onSubmit,
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
