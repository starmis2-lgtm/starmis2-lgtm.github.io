import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';
import '../widgets/tone.dart';

String _fmtT(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
String _min(num sec) => '${(sec / 60).toStringAsFixed(2)} min';

/// Production Manager: bulletins sent by DEOs that wait for his time.
class PmReviewScreen extends StatelessWidget {
  const PmReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final list = st.data?.pmQueue ?? const <MyPending>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Review'), actions: const [UserMenu()]),
      body: RefreshIndicator(
        onRefresh: () => st.load(silent: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
          children: [
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 90),
                child: EmptyState(icon: Icons.task_alt_rounded, title: 'Nothing to review', subtitle: 'Bulletins sent by DEOs will show here.', color: Color(0xFF047857)),
              )
            else ...[
              SectionLabel('${list.length} bulletin${list.length == 1 ? '' : 's'} waiting for your time'),
              for (final a in list) ...[_QueueCard(a: a), const SizedBox(height: 8)],
            ],
          ],
        ),
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.a});
  final MyPending a;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = context.read<AppState>().data?.srn(a.srn);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PmReviewPage(a: a))),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(children: [
            SrnThumb(info?.imageLink ?? '', size: 48, radius: 10),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.srn, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text(a.styleName.isEmpty ? '-' : a.styleName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                const SizedBox(height: 5),
                Wrap(spacing: 6, runSpacing: 4, children: [catPill(a.category), if (a.isEditMode) const Pill('EDIT', color: Color(0xFF92400E))]),
                const SizedBox(height: 4),
                Text('By ${a.submittedBy} · ${a.submittedAt}', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: cs.outline)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${a.operations.length} ops', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
              Text(_min(a.totalTime), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ink(const Color(0xFF3730A3)))),
              const SizedBox(height: 6),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PmReviewPage(a: a))),
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text('Review'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Row {
  _Row(this.op) : pm = TextEditingController(text: op.pmTime);
  final PendingOp op;
  final TextEditingController pm;
  bool remove = false;
  num get deo => n(op.time);
  num get pmNum => num.tryParse(pm.text.trim()) ?? 0;
}

class _Added {
  _Added({required this.name, required this.mp, this.mc = '', this.pc = '1', String time = ''}) : pm = TextEditingController(text: time);
  String name, mp, mc, pc;
  final TextEditingController pm;
  num get pmNum => num.tryParse(pm.text.trim()) ?? 0;
}

/// One bulletin: DEO time is fixed, the Production Manager writes his time next to it.
class PmReviewPage extends StatefulWidget {
  const PmReviewPage({super.key, required this.a});
  final MyPending a;
  @override
  State<PmReviewPage> createState() => _PmReviewPageState();
}

class _PmReviewPageState extends State<PmReviewPage> {
  late final List<_Row> rows = widget.a.operations.map(_Row.new).toList();
  final List<_Added> added = [];
  final note = TextEditingController();
  final List<TextEditingController> _trash = [];
  bool busy = false;

  @override
  void dispose() {
    for (final r in rows) {
      r.pm.dispose();
    }
    for (final x in added) {
      x.pm.dispose();
    }
    for (final c in _trash) {
      c.dispose();
    }
    note.dispose();
    super.dispose();
  }

  int get removeCount => rows.where((r) => r.remove).length;
  int get blankCount => rows.where((r) => !r.remove && r.pmNum <= 0).length;

  Future<void> _addOp() async {
    final st = context.read<AppState>();
    final p = st.data!;
    final isPacking = widget.a.category == 'Packing';
    final name = TextEditingController();
    final time = TextEditingController();
    final pc = TextEditingController(text: '1');
    final cat = widget.a.category;
    var sec = '';
    var mp = '';
    var mc = '';
    final ok = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, showDragHandle: true, useSafeArea: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final mps = sec.isEmpty ? <String>[] : p.sectionManpower(cat, sec);
        final needMc = !isPacking && (sectionByKey(cat, sec)?.machine ?? false);
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Add operation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('It is added directly with your time.', style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            TextField(
              controller: name, autofocus: true, textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Operation name'),
              onChanged: (v) {
                if (sec.isEmpty && v.trim().length >= 3) {
                  final g = st.guess(v, cat);
                  final k = sectionOf(cat, g.$1, mpKeyOf(g.$1) == 'operator' ? g.$2 : '');
                  if (sectionByKey(cat, k) == null) return;
                  setS(() {
                    sec = k;
                    final allowed = p.sectionManpower(cat, k);
                    mp = allowed.contains(g.$1) ? g.$1 : allowed.first;
                    mc = (sectionByKey(cat, k)!.machine && !isPacking) ? g.$2 : '';
                  });
                }
              },
            ),
            const SizedBox(height: 10),
            Text('Operation type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final x in sectionsFor(cat))
                ChoiceChip(
                  label: Text(x.label), selected: sec == x.key, showCheckmark: false, visualDensity: VisualDensity.compact,
                  onSelected: (_) => setS(() {
                    sec = x.key;
                    final allowed = p.sectionManpower(cat, x.key);
                    if (!allowed.contains(mp)) mp = allowed.isEmpty ? '' : allowed.first;
                    if (!x.machine || isPacking) mc = '';
                  }),
                ),
            ]),
            if (mps.isNotEmpty) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('mp$sec'),
                initialValue: mp.isEmpty || !mps.contains(mp) ? null : mp, isExpanded: true,
                decoration: const InputDecoration(labelText: 'Manpower'),
                items: mps.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
                onChanged: (v) => setS(() => mp = v ?? ''),
              ),
            ],
            if (needMc) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: mc.isEmpty || !p.machineTypes.contains(mc) ? null : mc, isExpanded: true,
                decoration: const InputDecoration(labelText: 'Machine'),
                items: p.machineTypes.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
                onChanged: (v) => setS(() => mc = v ?? ''),
              ),
            ],
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: pc, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Ops / pc'))),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: time, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: const InputDecoration(labelText: 'Your total time (sec)', suffixText: 's'),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () {
                if (name.text.trim().isEmpty || mp.isEmpty || (num.tryParse(time.text.trim()) ?? 0) <= 0) {
                  toast(ctx, 'Enter name, operation type and total time.', error: true);
                  return;
                }
                if (needMc && mc.isEmpty) {
                  toast(ctx, 'Select the machine for stitching.', error: true);
                  return;
                }
                Navigator.pop(ctx, true);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
            ),
          ]),
        );
      }),
    );
    if (ok == true) {
      setState(() => added.add(_Added(name: name.text.trim(), mp: mp, mc: mc, pc: pc.text.trim().isEmpty ? '1' : pc.text.trim(), time: time.text.trim())));
    }
    name.dispose();
    time.dispose();
    pc.dispose();
  }

  Future<void> _reject() async {
    final ctl = TextEditingController();
    final why = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject bulletin'),
        content: TextField(controller: ctl, autofocus: true, maxLines: 3, decoration: const InputDecoration(hintText: 'Reason (the DEO will see this)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (why == null) return;
    if (why.isEmpty) {
      if (mounted) toast(context, 'Please write a reason.', error: true);
      return;
    }
    await _run(() => context.read<AppState>().rejectRequest(widget.a.id, why));
  }

  Future<void> _send() async {
    if (rows.every((r) => r.remove) && added.isEmpty) {
      toast(context, 'All operations are marked for removal. Reject the bulletin instead.', error: true);
      return;
    }
    if (blankCount > 0) {
      final ok = await confirm(context, 'Some times are empty', '$blankCount operation(s) have no time from you. GM will only see the DEO time for them. Send anyway?', yes: 'Send');
      if (!ok) return;
    }
    if (!mounted) return;
    final review = {
      'ops': [for (var i = 0; i < rows.length; i++) {'i': i, 'pmTime': rows[i].pm.text.trim(), 'remove': rows[i].remove}],
      'added': [for (final x in added) {'operationName': x.name, 'manpowerType': x.mp, 'machineType': x.mc, 'operation1pc': x.pc, 'pmTime': x.pm.text.trim()}],
      'note': note.text.trim(),
    };
    await _run(() => context.read<AppState>().pmReview(widget.a.id, review));
  }

  Future<void> _run(Future<String> Function() fn) async {
    setState(() => busy = true);
    HapticFeedback.mediumImpact();
    try {
      final msg = await fn();
      if (!mounted) return;
      toast(context, msg);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    final cs = Theme.of(context).colorScheme;
    num deoT = 0, pmT = 0;
    for (final r in rows) {
      if (r.remove) continue;
      deoT += r.deo;
      pmT += r.pmNum > 0 ? r.pmNum : r.deo;
    }
    for (final x in added) {
      pmT += x.pmNum;
    }
    final toDeo = removeCount > 0;
    return Scaffold(
      appBar: AppBar(title: Text(a.srn)),
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.styleName.isEmpty ? a.srn : a.styleName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    const SizedBox(height: 5),
                    Wrap(spacing: 6, runSpacing: 4, children: [catPill(a.category), if (a.isEditMode) const Pill('EDIT', color: Color(0xFF92400E)), Pill('DEO: ${a.submittedBy}', color: cs.secondary)]),
                    const SizedBox(height: 8),
                    Text('Write your time next to each DEO time. Tap the DEO time to copy it. Tap the bin to ask the DEO to remove an operation.',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              SectionLabel('Operations · ${rows.length}'),
              for (var i = 0; i < rows.length; i++) ...[_opCard(i, rows[i], cs), const SizedBox(height: 6)],
              if (added.isNotEmpty) ...[
                const SizedBox(height: 6),
                SectionLabel('Added by you · ${added.length}'),
                for (final x in added) ...[_addedCard(x, cs), const SizedBox(height: 6)],
              ],
              const SizedBox(height: 4),
              OutlinedButton.icon(onPressed: busy ? null : _addOp, icon: const Icon(Icons.add_rounded), label: const Text('Add operation')),
              const SizedBox(height: 10),
              TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Note for GM (optional)')),
            ],
          ),
        ),
        Material(
          color: cs.surface, elevation: 8,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(child: Text('DEO ${_min(deoT)}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: ink(const Color(0xFF3730A3))))),
                  Text('Yours ${_min(pmT)}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: ink(const Color(0xFF6D28D9)))),
                ]),
                if (toDeo || blankCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [if (blankCount > 0) '$blankCount without your time', if (toDeo) '$removeCount to remove (DEO confirms)'].join(' · '),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ink(const Color(0xFFB45309))),
                    ),
                  ),
                const SizedBox(height: 6),
                Row(children: [
                  OutlinedButton(
                    onPressed: busy ? null : _reject,
                    style: OutlinedButton.styleFrom(foregroundColor: cs.error, side: BorderSide(color: cs.error.withValues(alpha: 0.5))),
                    child: const Text('Reject'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : _send,
                      icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded, size: 19),
                      label: Text(busy ? 'Sending…' : (toDeo ? 'Send to DEO' : 'Send to GM')),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _opCard(int i, _Row r, ColorScheme cs) {
    final o = r.op;
    final strike = r.remove ? TextStyle(decoration: TextDecoration.lineThrough, color: ink(const Color(0xFF94A3B8))) : const TextStyle();
    return Card(
      color: r.remove ? wash(const Color(0xFFFFF1F2)) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        child: Row(children: [
          Container(
            width: 22, height: 22, alignment: Alignment.center,
            decoration: BoxDecoration(color: cs.surfaceContainerHigh, shape: BoxShape.circle),
            child: Text('${i + 1}', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
          ),
          const SizedBox(width: 8),
          if (o.image.isNotEmpty) ...[
            SrnThumb(o.image, size: 38, radius: 7, title: o.operationName),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.operationName, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700).merge(strike)),
              Text([o.manpowerType, if (o.machineType.isNotEmpty) o.machineType, '${o.operation1pc.isEmpty ? '1' : o.operation1pc} pc'].join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
              if (r.remove) Text('DEO will confirm the removal', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: ink(const Color(0xFFBE123C)))),
            ]),
          ),
          if (!r.remove) ...[
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => r.pm.text = _fmtT(r.deo)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(color: wash(const Color(0xFFEEF2FF)), borderRadius: BorderRadius.circular(8)),
                child: Column(children: [
                  Text('DEO', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: ink(const Color(0xFF6366F1)))),
                  Text('${_fmtT(r.deo)}s', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ink(const Color(0xFF3730A3)))),
                ]),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 72,
              child: TextField(
                controller: r.pm,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                textAlign: TextAlign.center,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ink(const Color(0xFF6D28D9))),
                decoration: InputDecoration(
                  labelText: 'Yours', isDense: true, suffixText: 's',
                  labelStyle: const TextStyle(fontSize: 11),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  fillColor: r.pmNum > 0 ? wash(const Color(0xFFF5F3FF)) : wash(const Color(0xFFFFFBEB)),
                ),
              ),
            ),
          ],
          IconButton(
            tooltip: r.remove ? 'Undo' : 'Ask DEO to remove',
            onPressed: () => setState(() => r.remove = !r.remove),
            icon: Icon(r.remove ? Icons.undo_rounded : Icons.delete_outline_rounded, size: 20, color: r.remove ? cs.primary : cs.outline),
          ),
        ]),
      ),
    );
  }

  Widget _addedCard(_Added x, ColorScheme cs) {
    return Card(
      color: wash(const Color(0xFFF5F3FF)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        child: Row(children: [
          Icon(Icons.add_circle_outline_rounded, size: 20, color: ink(const Color(0xFF6D28D9))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              Text([x.mp, if (x.mc.isNotEmpty) x.mc, '${x.pc} pc'].join(' · '), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
            ]),
          ),
          SizedBox(
            width: 72,
            child: TextField(
              controller: x.pm,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              textAlign: TextAlign.center,
              onChanged: (_) => setState(() {}),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ink(const Color(0xFF6D28D9))),
              decoration: const InputDecoration(labelText: 'Yours', isDense: true, suffixText: 's', labelStyle: TextStyle(fontSize: 11), contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4)),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: () async {
              if (!await confirm(context, 'Remove operation', 'Remove "${x.name}" that you added?', yes: 'Remove', danger: true)) return;
              setState(() {
                added.remove(x);
                _trash.add(x.pm);
              });
            },
            icon: Icon(Icons.close_rounded, size: 20, color: cs.outline),
          ),
        ]),
      ),
    );
  }
}
