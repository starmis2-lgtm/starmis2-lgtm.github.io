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
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  _SetupCard(e: e, p: p),
                  const SizedBox(height: 14),
                  SectionLabel(
                    'Operations · ${e.ops.length}',
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (!e.locked && !e.editing)
                        TextButton.icon(onPressed: () => _copyFrom(context, st), icon: const Icon(Icons.copy_all_rounded, size: 18), label: const Text('Copy from SRN'), style: TextButton.styleFrom(visualDensity: VisualDensity.compact)),
                      if (e.ops.isNotEmpty)
                        IconButton(
                          tooltip: 'Expand / collapse all', visualDensity: VisualDensity.compact,
                          onPressed: () {
                            final anyClosed = e.ops.any((o) => !o.expanded);
                            for (final o in e.ops) {
                              o.expanded = anyClosed;
                            }
                            e.touch();
                          },
                          icon: const Icon(Icons.unfold_more_rounded, size: 20),
                        ),
                    ]),
                  ),
                  if (e.ops.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                        child: Column(children: [
                          Icon(Icons.playlist_add_rounded, color: cs.outline, size: 30),
                          const SizedBox(height: 6),
                          Text(e.locked ? (e.srn.isEmpty ? 'Select an SRN to load its R&D operations.' : 'No R&D bulletin found for this SRN.') : 'No operations yet. Add from the list below or copy from a similar SRN.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                        ]),
                      ),
                    ),
                  for (var i = 0; i < e.ops.length; i++) ...[
                    _OpRow(key: e.ops[i].key, index: i, op: e.ops[i], draft: e, payload: p),
                    const SizedBox(height: 8),
                  ],
                  if (!e.locked) ...[const SizedBox(height: 6), _QuickAdd(search: _search, st: st)],
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
        e.ops[bad].expanded = true;
        e.touch();
        toast(context, 'Operation ${bad + 1} needs a name, manpower and time greater than 0.', error: true);
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final String msg;
      final wasEditing = e.editing;
      if (wasEditing) {
        msg = await st.updatePending(e.pendingId, ops);
      } else {
        msg = await st.submitBulletin(e.payload(p));
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
        if (e.srn.isEmpty) {
          noteText = 'Production: select the SRN. Operations come from its R&D bulletin, you only enter the production time.';
        } else if (e.ops.isEmpty) {
          noteText = 'No ${e.category} R&D bulletin found for ${e.srn}. Create the R&D bulletin first.';
          noteColor = const Color(0xFFB45309);
          noteIcon = Icons.warning_amber_rounded;
        } else {
          noteText = 'Operations are locked to the R&D bulletin. Type the production time in each row.';
          noteIcon = Icons.lock_outline_rounded;
        }
      case EntryMode.editRnd:
        noteText = 'Editing existing ${e.category} R&D bulletin of ${e.srn}. Image / video changes save directly. Adding, removing or changing operations goes for approval.';
        noteColor = const Color(0xFF9A3412);
        noteIcon = Icons.edit_outlined;
      case EntryMode.editPending:
        noteText = 'Editing your pending submission for ${e.srn}. Changes are saved to the approval queue.';
        noteColor = const Color(0xFF9A3412);
        noteIcon = Icons.pending_actions_outlined;
      case EntryMode.fresh:
        if (e.srn.isNotEmpty) noteText = 'New ${e.category} R&D bulletin for ${e.srn}. First submission goes for management approval.';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
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
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: e.editing ? null : () async {
              final v = await pickSrn(context, options: p.srns);
              if (v != null) e.setSrn(v, p);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          const SizedBox(height: 10),
          Row(children: [
            ActionChip(
              avatar: const Icon(Icons.calendar_month_rounded, size: 16),
              label: Text('${e.date.day.toString().padLeft(2, '0')}-${e.date.month.toString().padLeft(2, '0')}-${e.date.year}'),
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: e.date, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) e.setDate(d);
              },
            ),
            const SizedBox(width: 8),
            catPill(e.category),
            const SizedBox(width: 6),
            typePill(e.type),
          ]),
          if (noteText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
      if (context.mounted) toast(context, 'Image uploaded.');
    } catch (e) {
      if (context.mounted) toast(context, 'Image upload failed: $e', error: true);
    } finally {
      if (mounted) setState(() => op.uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locked = d.locked;
    final prod = d.isProd;
    final isPacking = d.category == 'Packing';
    final mps = p.manpowerTypes.map((x) => x.name).toList();
    if (op.manpower.isNotEmpty && !mps.contains(op.manpower)) mps.add(op.manpower);
    final mcs = List<String>.from(p.machineTypes);
    if (op.machine.isNotEmpty && !mcs.contains(op.machine)) mcs.add(op.machine);
    final cost = op.cost(p);
    final subParts = <String>[
      if (op.manpower.isNotEmpty) op.manpower,
      if (!isPacking && op.machine.isNotEmpty) op.machine,
      if (op.op1pcCtl.text.trim().isNotEmpty) '${op.op1pcCtl.text.trim()} pc',
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => op.expanded = !op.expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            child: Row(children: [
              Container(
                width: 26, height: 26, alignment: Alignment.center,
                decoration: BoxDecoration(color: op.expanded ? cs.primary : cs.surfaceContainerHigh, shape: BoxShape.circle),
                child: Text('${widget.index + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: op.expanded ? cs.onPrimary : cs.onSurfaceVariant)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(op.name.isEmpty ? 'Untitled operation' : op.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: op.name.isEmpty ? cs.outline : cs.onSurface)),
                  Row(children: [
                    Flexible(
                      child: Text(
                        subParts.isEmpty ? 'Tap to set manpower' : subParts.join(' · '),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: subParts.isEmpty ? const Color(0xFFB45309) : cs.onSurfaceVariant),
                      ),
                    ),
                    if (cost > 0) Text('  ₹${cost.toStringAsFixed(2)}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF047857))),
                    if (op.img.isNotEmpty) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.image_rounded, size: 12, color: Color(0xFF4338CA))),
                    if (op.v1Ctl.text.trim().isNotEmpty) const Padding(padding: EdgeInsets.only(left: 3), child: Icon(Icons.play_circle_fill_rounded, size: 12, color: Color(0xFFE11D48))),
                  ]),
                ]),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 74,
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
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                    fillColor: op.suggested ? const Color(0xFFFFFBEB) : const Color(0xFFEEF2FF),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: op.suggested ? const Color(0xFFFDE68A) : const Color(0xFFC7D2FE))),
                    suffixText: prod ? 'p' : 's', suffixStyle: TextStyle(fontSize: 10, color: cs.outline),
                  ),
                ),
              ),
              if (locked)
                Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.lock_outline_rounded, size: 16, color: cs.outlineVariant))
              else
                IconButton(
                  visualDensity: VisualDensity.compact, tooltip: 'Remove',
                  onPressed: () => d.remove(op),
                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: cs.outline),
                ),
            ]),
          ),
        ),
        if (op.expanded) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: op.nameCtl, readOnly: locked, textCapitalization: TextCapitalization.sentences, onChanged: (_) => d.touch(), decoration: const InputDecoration(labelText: 'Operation name')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: op.manpower.isEmpty ? null : op.manpower,
                    isExpanded: true,
                    items: mps.map((x) => DropdownMenuItem(value: x, child: Text(x, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: locked ? null : (v) {
                      op.manpower = v ?? '';
                      d.touch();
                    },
                    decoration: const InputDecoration(labelText: 'Manpower'),
                  ),
                ),
                if (!isPacking) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: op.machine.isEmpty ? null : op.machine,
                      isExpanded: true,
                      items: [const DropdownMenuItem(value: '', child: Text('None')), ...mcs.map((x) => DropdownMenuItem(value: x, child: Text(x, overflow: TextOverflow.ellipsis)))],
                      onChanged: locked ? null : (v) {
                        op.machine = v ?? '';
                        d.touch();
                      },
                      decoration: const InputDecoration(labelText: 'Machine'),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: op.op1pcCtl, readOnly: locked, keyboardType: TextInputType.number, onChanged: (_) => d.touch(), decoration: const InputDecoration(labelText: 'Op / 1pc'))),
                const SizedBox(width: 10),
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Hr target / cost'),
                    child: Text(op.timeNum > 0 ? '${op.target()} /hr  ·  ₹${cost.toStringAsFixed(2)}' : '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
              ]),
              if (prod && op.rnd > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('R&D time: ${op.rnd}s', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF7E22CE)))),
              const SizedBox(height: 12),
              Row(children: [
                if (op.uploading)
                  const SizedBox(width: 48, height: 48, child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))))
                else if (op.img.isNotEmpty)
                  Stack(clipBehavior: Clip.none, children: [
                    SrnThumb(op.img, size: 48, radius: 10),
                    Positioned(right: -6, top: -6, child: GestureDetector(onTap: () => _pickImage(context), child: CircleAvatar(radius: 10, backgroundColor: cs.primary, child: const Icon(Icons.edit, size: 11, color: Colors.white)))),
                  ])
                else
                  OutlinedButton.icon(onPressed: () => _pickImage(context), icon: const Icon(Icons.photo_camera_outlined, size: 18), label: const Text('Photo'), style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact)),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: op.v1Ctl, keyboardType: TextInputType.url, onChanged: (_) => d.touch(),
                    decoration: InputDecoration(labelText: 'Video link (optional)', suffixIcon: op.v1Ctl.text.trim().isEmpty ? null : IconButton(icon: const Icon(Icons.open_in_new_rounded, size: 18), onPressed: () => openLink(op.v1Ctl.text))),
                  ),
                ),
              ]),
              if (prod) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: op.v2Ctl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Video link 2'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: op.v3Ctl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Video link 3'))),
                ]),
              ],
            ]),
          ),
        ],
      ]),
    );
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
    final g = widget.st.guess(q, widget.st.entry.category);
    widget.st.entry.add(name: q, manpower: g.$1, machine: g.$2, op1pc: '1', expanded: false);
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
    final lib = st.library(e.category);
    final have = e.haveKeys;
    final terms = q.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final hits = q.isEmpty ? lib.where((x) => !have.contains(x.key)).take(14).toList() : lib.where((x) => terms.every(x.key.contains)).take(8).toList();
    final exact = lib.any((x) => x.key == q.toLowerCase().replaceAll(RegExp(r'\s+'), ' '));

    return Card(
      color: cs.primary.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: cs.primary.withValues(alpha: 0.25))),
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                  hintText: 'Type operation name to add…', prefixIcon: const Icon(Icons.search_rounded), fillColor: cs.surface,
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
          const SizedBox(height: 10),
          if (q.isEmpty) ...[
            if (lib.isEmpty)
              Text('No history yet for ${e.category}. Type a name above and tap +.', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant))
            else ...[
              Text('COMMON OPERATIONS · TAP TO ADD', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: hits.map((x) => ActionChip(label: Text(x.name), onPressed: () => _addLib(x), backgroundColor: cs.surface, side: BorderSide(color: cs.primary.withValues(alpha: 0.35)), labelStyle: TextStyle(color: cs.primary, fontWeight: FontWeight.w600))).toList(),
              ),
            ],
          ] else ...[
            for (final x in hits)
              _SugRow(
                title: x.name, added: have.contains(x.key),
                sub: '${x.manpower.isEmpty ? '?' : x.manpower}${x.machine.isNotEmpty ? ' · ${x.machine}' : ''} · ${x.op1pc} pc · ${x.time > 0 ? '${x.time}s' : '—'} · used ${x.count}×',
                onTap: () => _addLib(x),
              ),
            if (!exact)
              Builder(builder: (_) {
                final g = st.guess(q, e.category);
                return _SugRow(title: 'Add “$q” as new operation', sub: '${g.$1.isEmpty ? 'manpower?' : g.$1}${g.$2.isNotEmpty ? ' · ${g.$2}' : ''} · you enter the time', highlight: true, onTap: () => _addNew(q));
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
    var ops = 0;
    num time = 0, cost = 0;
    for (final o in e.ops) {
      if (o.timeNum <= 0) continue;
      ops++;
      time += o.timeNum;
      cost += o.cost(p);
    }
    final label = e.editing ? 'Save changes' : (e.mode == EntryMode.editRnd ? 'Update' : 'Submit');
    return Material(
      color: cs.surface, elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('$ops ops · ${(time / 60).toStringAsFixed(2)} min', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                Text('₹${cost.toStringAsFixed(2)} / pc', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Color(0xFF047857))),
              ]),
            ),
            if (e.editing) ...[
              OutlinedButton(onPressed: busy ? null : () => e.reset(p), child: const Text('Cancel')),
              const SizedBox(width: 8),
            ],
            FilledButton.icon(
              onPressed: busy ? null : onSubmit,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
              icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(e.editing ? Icons.save_rounded : Icons.cloud_upload_rounded, size: 20),
              label: Text(busy ? 'Saving…' : label),
            ),
          ]),
        ),
      ),
    );
  }
}
