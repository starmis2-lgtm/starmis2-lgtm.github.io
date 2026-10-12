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
  final _search = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
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
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(children: [
                        const _RowHead(),
                        if (rows.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Text('No rows yet. Type an operation name below.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                          ),
                        for (var i = 0; i < rows.length; i++) _OpRow(key: rows[i].key, index: i, op: rows[i], draft: e),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    _QuickAdd(search: _search, st: st),
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

class _RowHead extends StatelessWidget {
  const _RowHead();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: cs.onSurfaceVariant);
    return Container(
      color: cs.surfaceContainerHigh.withValues(alpha: 0.6),
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      child: Row(children: [
        SizedBox(width: 20, child: Text('#', style: st)),
        Expanded(child: Text('OPERATION NAME', style: st)),
        SizedBox(width: 42, child: Text('OPS', textAlign: TextAlign.center, style: st)),
        const SizedBox(width: 4),
        SizedBox(width: 60, child: Text('TIME (S)', textAlign: TextAlign.center, style: st)),
        SizedBox(width: 36, child: Text('PHOTO', textAlign: TextAlign.center, style: st.copyWith(fontSize: 8))),
        const SizedBox(width: 28),
      ]),
    );
  }
}

/// One compact row: name · ops per piece · time · photo.
class _OpRow extends StatefulWidget {
  const _OpRow({super.key, required this.index, required this.op, required this.draft});
  final int index;
  final OpDraft op;
  final EntryDraft draft;
  @override
  State<_OpRow> createState() => _OpRowState();
}

class _OpRowState extends State<_OpRow> {
  OpDraft get op => widget.op;
  EntryDraft get d => widget.draft;

  Future<void> _pickImage(BuildContext context) async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context, showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Take photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_rounded), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          if (op.img.isNotEmpty)
            ListTile(leading: Icon(Icons.delete_outline_rounded, color: Theme.of(ctx).colorScheme.error), title: const Text('Remove photo'), onTap: () {
              Navigator.pop(ctx);
              setState(() => op.img = '');
              d.touch();
            }),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (src == null || !context.mounted) return;
    final st = context.read<AppState>();
    final x = await ImagePicker().pickImage(source: src, maxWidth: 1200, maxHeight: 1200, imageQuality: 85);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() => op.uploading = true);
    try {
      final url = await st.uploadImage(bytes, 'image/jpeg', x.name, d.srn, op.name);
      op.img = url;
      d.touch();
      if (context.mounted) toast(context, url.startsWith('local:') ? 'Photo saved on phone, uploads with the bulletin.' : 'Photo uploaded.');
    } catch (e) {
      if (context.mounted) toast(context, 'Photo upload failed: $e', error: true);
    } finally {
      if (mounted) setState(() => op.uploading = false);
    }
  }

  InputDecoration _box(String hint, {Color? fill, Color? border}) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      hintText: hint, isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      fillColor: fill ?? cs.surfaceContainerLow,
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: BorderSide(color: border ?? cs.outlineVariant.withValues(alpha: 0.5))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: BorderSide(color: cs.primary, width: 1.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final odd = widget.index.isOdd;
    return Container(
      color: odd ? cs.surfaceContainerLowest : null,
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      child: Row(children: [
        SizedBox(width: 20, child: Text('${widget.index + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cs.outline))),
        Expanded(
          child: TextField(
            controller: op.nameCtl,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            onChanged: (_) => d.touch(),
            decoration: _box('Operation name', fill: op.name.isEmpty ? const Color(0xFFFFFBEB) : null),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 42,
          child: TextField(
            controller: op.op1pcCtl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            onTap: () => op.op1pcCtl.selection = TextSelection(baseOffset: 0, extentOffset: op.op1pcCtl.text.length),
            onChanged: (_) => d.touch(),
            decoration: _box('1'),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 60,
          child: TextField(
            controller: op.timeCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            textAlign: TextAlign.center,
            textInputAction: TextInputAction.next,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: op.suggested ? const Color(0xFF92400E) : const Color(0xFF3730A3)),
            onTap: () => op.timeCtl.selection = TextSelection(baseOffset: 0, extentOffset: op.timeCtl.text.length),
            onChanged: (_) {
              op.suggested = false;
              d.touch();
            },
            decoration: _box('sec', fill: op.suggested ? const Color(0xFFFFFBEB) : const Color(0xFFEEF2FF), border: op.suggested ? const Color(0xFFFDE68A) : const Color(0xFFC7D2FE)),
          ),
        ),
        SizedBox(
          width: 36,
          child: op.uploading
              ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
              : op.img.isNotEmpty
                  ? Center(child: GestureDetector(onTap: () => _pickImage(context), child: SrnThumb(op.img, size: 28, radius: 6)))
                  : IconButton(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact, tooltip: 'Photo', onPressed: () => _pickImage(context), icon: Icon(Icons.photo_camera_outlined, size: 19, color: cs.onSurfaceVariant)),
        ),
        SizedBox(
          width: 28,
          child: IconButton(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact, tooltip: 'Remove row', onPressed: () => d.remove(op), icon: Icon(Icons.close_rounded, size: 17, color: cs.outline)),
        ),
      ]),
    );
  }
}

/// Type a name: matching operations of this type from past bulletins, or add as new.
class _QuickAdd extends StatefulWidget {
  const _QuickAdd({required this.search, required this.st});
  final TextEditingController search;
  final AppState st;
  @override
  State<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends State<_QuickAdd> {
  final _focus = FocusNode();

  void _addLib(LibOp x) {
    widget.st.entry.add(name: x.name, op1pc: x.op1pc, time: x.time > 0 ? _fmtT(x.time) : '', suggested: x.time > 0);
    widget.search.clear();
    setState(() {});
  }

  void _addNew(String q) {
    widget.st.entry.add(name: q, op1pc: '1');
    widget.search.clear();
    setState(() {});
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.st;
    final e = st.entry;
    final cs = Theme.of(context).colorScheme;
    final q = widget.search.text.trim();
    final libAll = st.library(e.category);
    final libType = libAll.where((x) => x.manpower.toLowerCase() == e.mp.toLowerCase()).toList();
    final lib = libType.isEmpty ? libAll : libType;
    final have = e.haveKeys;
    final terms = q.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final hits = q.isEmpty ? <LibOp>[] : lib.where((x) => terms.every(x.key.contains)).take(6).toList();
    final exact = lib.any((x) => x.key == q.toLowerCase().replaceAll(RegExp(r'\s+'), ' '));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: widget.search, focusNode: _focus,
            textCapitalization: TextCapitalization.sentences, textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (v) {
              if (v.trim().isEmpty) return;
              if (hits.isNotEmpty) {
                _addLib(hits.first);
              } else {
                _addNew(v.trim());
              }
              _focus.requestFocus();
            },
            decoration: InputDecoration(
              hintText: 'Add ${roleLabel(e.mp)} operation…', prefixIcon: const Icon(Icons.add_rounded, size: 20), fillColor: cs.surface,
              suffixIcon: q.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() => widget.search.clear())),
            ),
          ),
        ),
        const SizedBox(width: 6),
        FilledButton.tonal(
          onPressed: () {
            if (q.isNotEmpty) {
              _addNew(q);
            } else {
              e.add(op1pc: '1');
            }
          },
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), minimumSize: const Size(44, 44)),
          child: const Icon(Icons.add_rounded),
        ),
      ]),
      if (q.isNotEmpty) ...[
        const SizedBox(height: 6),
        for (final x in hits)
          _SugRow(title: x.name, added: have.contains(x.key), sub: '${x.op1pc} ops · ${x.time > 0 ? '${_fmtT(x.time)}s' : '—'} · used ${x.count}×', onTap: () => _addLib(x)),
        if (!exact) _SugRow(title: 'Add “$q” as new operation', sub: 'you enter the time', highlight: true, onTap: () => _addNew(q)),
      ],
    ]);
  }
}

class _SugRow extends StatelessWidget {
  const _SugRow({required this.title, required this.sub, required this.onTap, this.added = false, this.highlight = false});
  final String title, sub;
  final VoidCallback onTap;
  final bool added, highlight;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: highlight ? cs.primaryContainer.withValues(alpha: 0.5) : cs.surface,
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
                  Row(children: [
                    Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: highlight ? cs.primary : cs.onSurface))),
                    if (added) const Padding(padding: EdgeInsets.only(left: 6), child: Pill('added', color: Color(0xFF065F46))),
                  ]),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                ]),
              ),
              Icon(Icons.add_circle_rounded, color: cs.primary, size: 20),
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
