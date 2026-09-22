import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';

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

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = st.data!;
    return ListenableBuilder(
      listenable: st.entry,
      builder: (context, _) {
        final e = st.entry;
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            title: Text(e.editing ? 'Edit Pending Submission' : 'Data Entry'),
            actions: [
              if (e.ops.isNotEmpty || e.srn.isNotEmpty)
                IconButton(tooltip: 'Clear form', onPressed: () async {
                  if (await confirm(context, 'Clear form', 'Discard everything entered in this form?', yes: 'Clear', danger: true)) e.reset(p);
                }, icon: const Icon(Icons.restart_alt_rounded)),
              const UserMenu(),
            ],
          ),
          body: Column(children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                children: [
                  _SetupCard(e: e, p: p),
                  const SizedBox(height: 10),
                  if (e.srn.isNotEmpty && !e.roleChosen)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                        child: Column(children: [
                          Icon(Icons.category_outlined, color: cs.primary, size: 30),
                          const SizedBox(height: 6),
                          Text('Select a bulletin type above to start.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                        ]),
                      ),
                    )
                  else ...[
                  SectionLabel(
                    e.role == 'All' || e.role.isEmpty ? 'Operations · ${e.ops.length}' : '${roleLabel(e.role)} · ${e.visibleOps.length} ops  (total ${e.ops.length})',
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (!e.locked && !e.editing)
                        TextButton.icon(onPressed: () => _copyFrom(context, st), icon: const Icon(Icons.copy_all_rounded, size: 18), label: const Text('Copy from SRN'), style: TextButton.styleFrom(visualDensity: VisualDensity.compact)),
                    ]),
                  ),
                  if (e.visibleOps.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                        child: Column(children: [
                          Icon(Icons.playlist_add_rounded, color: cs.outline, size: 30),
                          const SizedBox(height: 6),
                          Text(e.locked ? (e.srn.isEmpty ? 'Select an SRN.' : (e.ops.isEmpty ? 'No R&D bulletin for this SRN.' : 'No ${roleLabel(e.role)} operations.')) : 'No operations yet. Type a name below.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                        ]),
                      ),
                    ),
                  for (var i = 0; i < e.visibleOps.length; i++) ...[
                    _OpRow(key: e.visibleOps[i].key, index: i, op: e.visibleOps[i], draft: e, payload: p),
                    const SizedBox(height: 6),
                  ],
                  if (!e.locked) ...[const SizedBox(height: 6), _QuickAdd(search: _search, st: st)],
                  ],
                ],
              ),
            ),
            _BottomBar(busy: _busy, onSubmit: () => _submit(context, st)),
          ]),
        );
      },
    );
  }

  Future<void> _copyFrom(BuildContext context, AppState st) async {
    final e = st.entry;
    final p = st.data!;
    final src = e.category == 'Packing' ? p.packing : p.submitted;
    final opts = src.where((bl) => bl.srn != e.srn && bl.ops.isNotEmpty).map((bl) => SrnInfo(srn: bl.srn, styleName: '${bl.styleName} · ${bl.ops.length} ops', imageLink: bl.imageLink)).toList();
    final from = await pickSrn(context, options: opts, title: 'Copy operations from');
    if (from == null || !context.mounted) return;
    final bl = p.bulletin(e.category, from);
    if (bl == null) return;
    if (e.ops.isNotEmpty) {
      final ok = await confirm(context, 'Copy operations', 'Replace the ${e.ops.length} operation(s) already added with ${bl.ops.length} from $from?', yes: 'Replace');
      if (!ok) return;
    }
    e.replaceWith(bl.ops);
    if (context.mounted) toast(context, 'Copied ${bl.ops.length} operations from $from. Check the times.');
  }

  Future<void> _submit(BuildContext context, AppState st) async {
    final e = st.entry;
    final p = st.data!;
    if (e.srn.isEmpty) {
      toast(context, 'Please select an SRN.', error: true);
      return;
    }
    final ops = e.collect(p);
    if (ops.isEmpty) {
      toast(context, 'Please add at least one operation.', error: true);
      return;
    }
    if (e.isProd) {
      if (!ops.any((o) => (num.tryParse(o['time'].toString()) ?? 0) > 0)) {
        toast(context, 'Enter production time for at least one operation.', error: true);
        return;
      }
    } else {
      final bad = e.firstInvalid();
      if (bad >= 0) {
        final o = e.ops[bad];
        e.role = (o.manpower.isNotEmpty && e.role != 'All') ? o.manpower : 'All';
        e.touch();
        toast(context, '"${o.name.isEmpty ? 'Operation ${bad + 1}' : o.name}" needs a name, type and time greater than 0.', error: true);
        return;
      }
    }
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      final String msg;
      final wasEditing = e.editing;
      final label = '${e.category} ${e.type}${e.role.isNotEmpty && e.role != 'All' ? ' · ${roleLabel(e.role)}' : ''}';
      if (wasEditing) {
        msg = await st.updatePending(e.pendingId, ops, srn: e.srn, label: label);
      } else {
        msg = await st.submitBulletin(e.payload(p), srn: e.srn, label: label);
      }
      if (!context.mounted) return;
      toast(context, msg);
      e.reset(st.data);
      st.goToTab(wasEditing ? Tabs.myPending : Tabs.home);
    } catch (err) {
      if (context.mounted) toast(context, err.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.e, required this.p});
  final EntryDraft e;
  final Payload p;

  /// Roles offered as bulletin types: all manpower types from Validation plus any extra role already in the draft.
  static List<String> _roles(Payload p, EntryDraft e) {
    final set = <String>{...p.manpowerTypes.map((x) => x.name), ...e.ops.map((o) => o.manpower).where((x) => x.isNotEmpty)};
    final list = set.toList()..sort((a, b) => roleRank(a) != roleRank(b) ? roleRank(a).compareTo(roleRank(b)) : a.compareTo(b));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = e.srn.isEmpty ? null : p.srn(e.srn);
    final segStyle = ButtonStyle(visualDensity: VisualDensity.compact, textStyle: WidgetStateProperty.all(const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)));
    String noteText = '';
    Color noteColor = cs.primary;
    IconData noteIcon = Icons.info_outline_rounded;
    switch (e.mode) {
      case EntryMode.prod:
        if (e.srn.isNotEmpty && e.ops.isEmpty) {
          noteText = 'No R&D bulletin yet for ${e.srn}. Create R&D first.';
          noteColor = const Color(0xFFB45309);
          noteIcon = Icons.warning_amber_rounded;
        } else if (e.srn.isNotEmpty) {
          noteText = 'Production time entry · operations locked to R&D';
          noteIcon = Icons.lock_outline_rounded;
        }
      case EntryMode.editRnd:
        noteText = 'Editing existing R&D · photo/video save directly, operation changes go for approval';
        noteColor = const Color(0xFF9A3412);
        noteIcon = Icons.edit_outlined;
      case EntryMode.editPending:
        noteText = 'Editing pending submission';
        noteColor = const Color(0xFF9A3412);
        noteIcon = Icons.pending_actions_outlined;
      case EntryMode.fresh:
        break;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: SegmentedButton<String>(
                style: segStyle, showSelectedIcon: false,
                segments: const [ButtonSegment(value: 'Making', label: Text('Making')), ButtonSegment(value: 'Packing', label: Text('Packing'))],
                selected: {e.category},
                onSelectionChanged: e.editing ? null : (v) => e.setCategory(v.first, p),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SegmentedButton<String>(
                style: segStyle, showSelectedIcon: false,
                segments: const [ButtonSegment(value: 'R&D', label: Text('R&D')), ButtonSegment(value: 'Production', label: Text('Prod'))],
                selected: {e.type},
                onSelectionChanged: e.editing ? null : (v) => e.setType(v.first, p),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: e.editing ? null : () async {
              final v = await pickSrn(context, options: p.srns);
              if (v != null) e.setSrn(v, p);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(12), border: Border.all(color: e.srn.isEmpty ? cs.primary.withValues(alpha: 0.5) : cs.outlineVariant.withValues(alpha: 0.5))),
              child: Row(children: [
                if (info != null) ...[SrnThumb(info.imageLink, size: 44, radius: 10), const SizedBox(width: 10)] else Icon(Icons.qr_code_2_rounded, color: cs.primary),
                if (info == null) const SizedBox(width: 10),
                Expanded(
                  child: info == null
                      ? Text(e.srn.isEmpty ? 'Select SRN' : e.srn, style: TextStyle(fontWeight: FontWeight.w700, color: e.srn.isEmpty ? cs.primary : cs.onSurface))
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(info.srn, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          Text(info.styleName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                          Text('Qty ${info.shippingQty}${info.orderDate.isNotEmpty ? ' · Order ${info.orderDate}' : ''}', style: TextStyle(fontSize: 10.5, color: cs.outline, fontWeight: FontWeight.w600)),
                        ]),
                ),
                Icon(e.editing ? Icons.lock_outline_rounded : Icons.expand_more_rounded, color: cs.outline),
              ]),
            ),
          ),
          if (e.srn.isNotEmpty) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: e.role.isEmpty ? null : e.role,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'Bulletin type', prefixIcon: const Icon(Icons.category_outlined, size: 20), fillColor: e.role.isEmpty ? const Color(0xFFFFFBEB) : null),
              hint: const Text('Select bulletin type'),
              items: [
                for (final r in _roles(p, e))
                  DropdownMenuItem(value: r, child: Row(children: [Expanded(child: Text(roleLabel(r), overflow: TextOverflow.ellipsis)), if (e.countFor(r) > 0) Pill('${e.countFor(r)} ops', color: cs.primary)])),
                DropdownMenuItem(value: 'All', child: Row(children: [const Expanded(child: Text('All types')), if (e.ops.isNotEmpty) Pill('${e.ops.length} ops', color: cs.secondary)])),
              ],
              onChanged: (v) => e.setRole(v ?? ''),
            ),
          ],
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: e.date, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) e.setDate(d);
              },
              icon: const Icon(Icons.calendar_month_rounded, size: 17),
              label: Text('${e.date.day.toString().padLeft(2, '0')}-${e.date.month.toString().padLeft(2, '0')}-${e.date.year}', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12), foregroundColor: cs.onSurface),
            ),
            const SizedBox(width: 8),
            catPill(e.category),
            const SizedBox(width: 6),
            typePill(e.type),
          ]),
          if (noteText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(color: noteColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: noteColor.withValues(alpha: 0.25))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(noteIcon, size: 16, color: noteColor),
                const SizedBox(width: 8),
                Expanded(child: Text(noteText, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: noteColor))),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

class _OpRow extends StatefulWidget {
  const _OpRow({super.key, required this.index, required this.op, required this.draft, required this.payload});
  final int index;
  final OpDraft op;
  final EntryDraft draft;
  final Payload payload;
  @override
  State<_OpRow> createState() => _OpRowState();
}

class _OpRowState extends State<_OpRow> {
  OpDraft get op => widget.op;
  EntryDraft get d => widget.draft;
  Payload get p => widget.payload;

  /// Auto-select manpower / machine from the operation name (only fills blanks).
  void _autoFill(BuildContext context, String name) {
    if (name.trim().length < 3) return;
    final st = context.read<AppState>();
    final g = st.guess(name, d.category);
    var changed = false;
    if (op.manpower.isEmpty && g.$1.isNotEmpty) {
      op.manpower = g.$1;
      changed = true;
    }
    if (d.category != 'Packing' && op.machine.isEmpty && op.manpower.toLowerCase() == 'operator' && g.$2.isNotEmpty) {
      op.machine = g.$2;
      changed = true;
    }
    if (changed) setState(() {});
  }

  Future<void> _pickImage(BuildContext context) async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context, showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Take photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_rounded), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          if (op.img.isNotEmpty)
            ListTile(leading: Icon(Icons.delete_outline_rounded, color: Theme.of(ctx).colorScheme.error), title: const Text('Remove image'), onTap: () {
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
      if (context.mounted) toast(context, 'Image upload failed: $e', error: true);
    } finally {
      if (mounted) setState(() => op.uploading = false);
    }
  }

  Widget _miniDropdown({required String value, required List<String> items, required String hint, required ValueChanged<String?>? onChanged, IconData? icon, bool flex = true}) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    final child = Container(
      height: 32,
      padding: const EdgeInsets.only(left: 8, right: 4),
      decoration: BoxDecoration(
        color: value.isEmpty ? const Color(0xFFFFFBEB) : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: value.isEmpty ? const Color(0xFFFDE68A) : cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value.isEmpty ? null : value,
          isDense: true, isExpanded: true,
          icon: Icon(enabled ? Icons.arrow_drop_down_rounded : Icons.lock_outline_rounded, size: enabled ? 20 : 13, color: cs.outline),
          hint: Row(children: [if (icon != null) ...[Icon(icon, size: 13, color: const Color(0xFFB45309)), const SizedBox(width: 4)], Flexible(child: Text(hint, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFB45309))))]),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface, fontFamily: 'Inter'),
          items: items.map((x) => DropdownMenuItem(value: x, child: Text(x, overflow: TextOverflow.ellipsis))).toList(),
          selectedItemBuilder: (_) => items.map((x) => Row(children: [if (icon != null) ...[Icon(icon, size: 13, color: cs.primary), const SizedBox(width: 4)], Flexible(child: Text(x, overflow: TextOverflow.ellipsis))])).toList(),
          onChanged: onChanged,
        ),
      ),
    );
    return flex ? Expanded(child: child) : child;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locked = d.locked;
    final prod = d.isProd;
    final isPacking = d.category == 'Packing';
    final mps = p.manpowerTypes.map((x) => x.name).toList();
    if (op.manpower.isNotEmpty && !mps.contains(op.manpower)) mps.add(op.manpower);
    final mcs = ['', ...p.machineTypes];
    if (op.machine.isNotEmpty && !mcs.contains(op.machine)) mcs.add(op.machine);
    final cost = op.cost(p);

    final pc = int.tryParse(op.op1pcCtl.text.trim()) ?? 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 6, 8),
        child: Column(children: [
          Row(children: [
            Container(
              width: 22, height: 22, alignment: Alignment.center,
              decoration: BoxDecoration(color: cs.surfaceContainerHigh, shape: BoxShape.circle),
              child: Text('${widget.index + 1}', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: op.nameCtl,
                readOnly: locked,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                onChanged: (v) {
                  _autoFill(context, v);
                  d.touch();
                },
                decoration: InputDecoration(
                  hintText: 'Operation name', isDense: true, filled: false,
                  border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: cs.primary)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                  hintStyle: TextStyle(color: cs.outline, fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 70,
              child: TextField(
                controller: op.timeCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: op.suggested ? const Color(0xFF92400E) : const Color(0xFF3730A3)),
                onChanged: (_) {
                  op.suggested = false;
                  d.touch();
                },
                onTap: () => op.timeCtl.selection = TextSelection(baseOffset: 0, extentOffset: op.timeCtl.text.length),
                decoration: InputDecoration(
                  hintText: 'sec', isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                  fillColor: op.suggested ? const Color(0xFFFFFBEB) : const Color(0xFFEEF2FF),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: op.suggested ? const Color(0xFFFDE68A) : const Color(0xFFC7D2FE))),
                  suffixText: 's', suffixStyle: TextStyle(fontSize: 10, color: cs.outline),
                ),
              ),
            ),
            if (locked)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.lock_outline_rounded, size: 15, color: cs.outlineVariant))
            else
              IconButton(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), tooltip: 'Remove', onPressed: () => d.remove(op), icon: Icon(Icons.delete_outline_rounded, size: 19, color: cs.outline)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const SizedBox(width: 30),
            _miniDropdown(
              value: op.manpower, items: mps, hint: 'Manpower', icon: Icons.person_outline_rounded,
              onChanged: locked ? null : (v) {
                op.manpower = v ?? '';
                if (op.manpower.toLowerCase() == 'operator' && op.machine.isEmpty && !isPacking) {
                  op.machine = p.machineTypes.firstWhere((x) => x.toLowerCase().contains('stitch'), orElse: () => '');
                }
                setState(() {});
                d.touch();
              },
            ),
            if (!isPacking) ...[
              const SizedBox(width: 6),
              _miniDropdown(
                value: op.machine, items: mcs.where((x) => x.isNotEmpty).toList(), hint: 'Machine', icon: Icons.precision_manufacturing_outlined,
                onChanged: locked ? null : (v) {
                  op.machine = v ?? '';
                  setState(() {});
                  d.touch();
                },
              ),
            ],
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const SizedBox(width: 30),
            // Ops per piece stepper
            Container(
              height: 32,
              decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _stepBtn(Icons.remove_rounded, locked || pc <= 1 ? null : () { op.op1pcCtl.text = '${pc - 1}'; setState(() {}); d.touch(); }),
                SizedBox(
                  width: 34,
                  child: TextField(
                    controller: op.op1pcCtl, readOnly: locked, textAlign: TextAlign.center, keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                    onChanged: (_) { setState(() {}); d.touch(); },
                    decoration: const InputDecoration(isDense: true, filled: false, border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, contentPadding: EdgeInsets.zero),
                  ),
                ),
                _stepBtn(Icons.add_rounded, locked ? null : () { op.op1pcCtl.text = '${pc + 1}'; setState(() {}); d.touch(); }),
                Padding(padding: const EdgeInsets.only(right: 8), child: Text('ops/pc', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))),
              ]),
            ),
            const SizedBox(width: 6),
            // Photo
            if (op.uploading)
              const SizedBox(width: 32, height: 32, child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))))
            else if (op.img.isNotEmpty)
              GestureDetector(onTap: () => _pickImage(context), child: SrnThumb(op.img, size: 32, radius: 8))
            else
              _iconBox(Icons.photo_camera_outlined, 'Photo', () => _pickImage(context), cs),
            const SizedBox(width: 6),
            // Video link(s)
            _iconBox(op.v1Ctl.text.trim().isEmpty ? Icons.link_rounded : Icons.play_circle_fill_rounded, 'Video', () => _editVideo(context), cs, active: op.v1Ctl.text.trim().isNotEmpty, activeColor: const Color(0xFFE11D48)),
            const Spacer(),
            if (prod && op.rnd > 0) Padding(padding: const EdgeInsets.only(right: 6), child: Text('R&D ${op.rnd}s', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF7E22CE)))),
            if (op.timeNum > 0)
              Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                Text('₹${cost.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF047857))),
                Text('${op.target()} /hr', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: cs.outline)),
              ]),
          ]),
        ]),
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 30, height: 32, child: Icon(icon, size: 17, color: onTap == null ? cs.outlineVariant : cs.primary)),
    );
  }

  Widget _iconBox(IconData icon, String tip, VoidCallback onTap, ColorScheme cs, {bool active = false, Color? activeColor}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36, height: 32,
          decoration: BoxDecoration(color: active ? (activeColor ?? cs.primary).withValues(alpha: 0.10) : cs.surfaceContainerLow, borderRadius: BorderRadius.circular(8), border: Border.all(color: active ? (activeColor ?? cs.primary).withValues(alpha: 0.4) : cs.outlineVariant.withValues(alpha: 0.5))),
          child: Icon(icon, size: 18, color: active ? (activeColor ?? cs.primary) : cs.onSurfaceVariant),
        ),
      ),
    );
  }

  Future<void> _editVideo(BuildContext context) async {
    final prod = d.isProd;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Video link'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: op.v1Ctl, keyboardType: TextInputType.url, autofocus: true, decoration: const InputDecoration(labelText: 'Video link', hintText: 'https://...')),
          if (prod) ...[
            const SizedBox(height: 8),
            TextField(controller: op.v2Ctl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Video link 2')),
            const SizedBox(height: 8),
            TextField(controller: op.v3Ctl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Video link 3')),
          ],
        ]),
        actions: [
          if (op.v1Ctl.text.trim().isNotEmpty) TextButton.icon(onPressed: () => openLink(op.v1Ctl.text), icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('Open')),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
    setState(() {});
    d.touch();
  }
}

class _QuickAdd extends StatefulWidget {
  const _QuickAdd({required this.search, required this.st});
  final TextEditingController search;
  final AppState st;
  @override
  State<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends State<_QuickAdd> {
  final _focus = FocusNode();

  void _addLib(LibOp e) {
    widget.st.entry.add(name: e.name, manpower: e.manpower, machine: e.machine, op1pc: e.op1pc, time: e.time > 0 ? (e.time == e.time.roundToDouble() ? e.time.toInt().toString() : e.time.toString()) : '', suggested: e.time > 0);
    widget.search.clear();
    setState(() {});
  }

  void _addNew(String q) {
    if (q.isEmpty) return;
    final e = widget.st.entry;
    final g = widget.st.guess(q, e.category);
    final mp = (e.role.isEmpty || e.role == 'All') ? g.$1 : e.role;
    widget.st.entry.add(name: q, manpower: mp, machine: mp.toLowerCase() == 'operator' ? g.$2 : '', op1pc: '1', expanded: false);
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
    final roleSel = e.role == 'All' ? '' : e.role;
    final libAll = st.library(e.category);
    final libRole = roleSel.isEmpty ? libAll : libAll.where((x) => x.manpower.toLowerCase() == roleSel.toLowerCase()).toList();
    final lib = libRole.isEmpty ? libAll : libRole;
    final have = e.haveKeys;
    final terms = q.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final hits = q.isEmpty ? <LibOp>[] : lib.where((x) => terms.every(x.key.contains)).take(8).toList();
    final exact = lib.any((x) => x.key == q.toLowerCase().replaceAll(RegExp(r'\s+'), ' '));

    return Card(
      color: cs.primary.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: cs.primary.withValues(alpha: 0.25))),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: widget.search, focusNode: _focus,
                textCapitalization: TextCapitalization.sentences, textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (v) {
                  if (hits.isNotEmpty && q.isNotEmpty) {
                    _addLib(hits.first);
                  } else {
                    _addNew(v.trim());
                  }
                  _focus.requestFocus();
                },
                decoration: InputDecoration(
                  hintText: roleSel.isEmpty ? 'Type operation name to add…' : 'Add ${roleLabel(roleSel)} operation…', prefixIcon: const Icon(Icons.add_rounded), fillColor: cs.surface,
                  suffixIcon: q.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() => widget.search.clear())),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () {
                if (q.isNotEmpty) {
                  _addNew(q);
                } else {
                  e.add(expanded: true);
                }
              },
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
              child: const Icon(Icons.add_rounded),
            ),
          ]),
          if (q.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final x in hits)
              _SugRow(
                title: x.name, added: have.contains(x.key),
                sub: '${x.manpower.isEmpty ? '?' : x.manpower}${x.machine.isNotEmpty ? ' · ${x.machine}' : ''} · ${x.op1pc} pc · ${x.time > 0 ? '${x.time}s' : '—'} · used ${x.count}×',
                onTap: () => _addLib(x),
              ),
            if (!exact)
              Builder(builder: (_) {
                final g = st.guess(q, e.category);
                final mp = roleSel.isEmpty ? g.$1 : roleSel;
                return _SugRow(title: 'Add “$q” as new operation', sub: '${mp.isEmpty ? 'manpower?' : mp}${g.$2.isNotEmpty && mp.toLowerCase() == 'operator' ? ' · ${g.$2}' : ''} · you enter the time', highlight: true, onTap: () => _addNew(q));
              }),
          ],
        ]),
      ),
    );
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
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: highlight ? cs.primaryContainer.withValues(alpha: 0.5) : cs.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: highlight ? cs.primary : cs.onSurface))),
                    if (added) const Padding(padding: EdgeInsets.only(left: 6), child: Pill('added', color: Color(0xFF065F46))),
                  ]),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                ]),
              ),
              Icon(Icons.add_circle_rounded, color: cs.primary),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.busy, required this.onSubmit});
  final bool busy;
  final VoidCallback onSubmit;
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final e = st.entry;
    final p = st.data!;
    final cs = Theme.of(context).colorScheme;
    var ops = 0, rOps = 0;
    num time = 0, cost = 0, rTime = 0;
    final roleSel = e.role == 'All' ? '' : e.role;
    for (final o in e.ops) {
      if (o.timeNum <= 0) continue;
      ops++;
      time += o.timeNum;
      cost += o.cost(p);
      if (roleSel.isNotEmpty && o.manpower == roleSel) {
        rOps++;
        rTime += o.timeNum;
      }
    }
    final label = e.editing ? 'Save changes' : (e.mode == EntryMode.editRnd ? 'Update' : 'Submit');
    return Material(
      color: cs.surface, elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (roleSel.isNotEmpty) Text('${roleLabel(roleSel)}: $rOps ops · ${(rTime / 60).toStringAsFixed(2)} min', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: cs.primary)),
                Text('Total $ops ops · ${(time / 60).toStringAsFixed(2)} min · ₹${cost.toStringAsFixed(2)}/pc', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: roleSel.isNotEmpty ? cs.onSurfaceVariant : cs.onSurface)),
              ]),
            ),
            if (e.editing) ...[
              OutlinedButton(onPressed: busy ? null : () => e.reset(p), child: const Text('Cancel')),
              const SizedBox(width: 8),
            ],
            FilledButton.icon(
              onPressed: busy ? null : onSubmit,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
              icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(e.editing ? Icons.save_rounded : Icons.cloud_upload_rounded, size: 20),
              label: Text(busy ? 'Saving…' : label),
            ),
          ]),
        ),
      ),
    );
  }
}
