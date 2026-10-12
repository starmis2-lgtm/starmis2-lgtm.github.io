import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';

class MyPendingScreen extends StatelessWidget {
  const MyPendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = st.data!;
    final list = p.myPending;
    return Scaffold(
      appBar: AppBar(title: const Text('My Pending'), actions: const [UserMenu()]),
      body: RefreshIndicator(
        onRefresh: () => st.load(silent: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
          children: [
            const OutboxList(),
            for (final r in st.visibleRejected) ...[_RejectedCard(r: r), const SizedBox(height: 8)],
            for (final a in st.toConfirm) ...[_ConfirmCard(key: ValueKey('c${a.id}'), a: a), const SizedBox(height: 8)],
            if (list.isEmpty && st.outbox.items.isEmpty && st.visibleRejected.isEmpty)
              const Padding(padding: EdgeInsets.only(top: 90), child: EmptyState(icon: Icons.task_alt_rounded, title: 'No pending submissions', subtitle: 'Submitted bulletins wait here until approved.', color: Color(0xFF047857)))
            else
              for (final a in list.where((x) => !st.toConfirm.contains(x))) ...[_MyCard(a: a), const SizedBox(height: 8)],
          ],
        ),
      ),
    );
  }
}

class _RejectedCard extends StatelessWidget {
  const _RejectedCard({required this.r});
  final Rejected r;
  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    const red = Color(0xFFBE123C);
    return Card(
      color: const Color(0xFFFFF1F2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFFECDD3))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.block_rounded, color: red, size: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(r.srn, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(width: 6),
                const Pill('REJECTED', color: red),
              ]),
              Text('${r.category} ${r.type}${r.styleName.isNotEmpty ? ' · ${r.styleName}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
              const SizedBox(height: 4),
              Text(r.reason, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: red)),
              const SizedBox(height: 2),
              Text('By ${r.rejectedBy} · ${r.rejectedAt}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
            ]),
          ),
          TextButton(onPressed: () => st.dismissRejected(r.id), child: const Text('OK')),
        ]),
      ),
    );
  }
}

class _MyCard extends StatelessWidget {
  const _MyCard({required this.a});
  final MyPending a;

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final p = st.data!;
    final cs = Theme.of(context).colorScheme;
    num cost = 0;
    for (final o in a.operations) {
      final t = n(o.time);
      if (t <= 0) continue;
      final c = n(o.cost);
      cost += c > 0 ? c : p.cost(o.manpowerType, t);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.srn, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text(a.styleName.isEmpty ? '-' : a.styleName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  catPill(a.category),
                  if (a.type != 'R&D') typePill(a.type),
                  if (a.isEditMode) const Pill('EDIT', color: Color(0xFF92400E)),
                  Pill(stageLabel(a.stage), color: stageColor(a.stage), filled: true),
                ]),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${a.operations.length} ops', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
              Text('${(a.totalTime / 60).toStringAsFixed(2)} min', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF7E22CE))),
              Text('₹${cost.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF047857))),
            ]),
          ]),
          const Padding(padding: EdgeInsets.symmetric(vertical: 7), child: Divider()),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Submitted ${a.submittedAt}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                if (a.mis != null && a.mis!.hasDue) ...[
                  Text('Due ${a.mis!.due}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  StatusPill(a.mis),
                ],
              ]),
            ),
            IconButton.outlined(tooltip: 'Not required', visualDensity: VisualDensity.compact, onPressed: () => showNotRequired(context, a.srn), icon: const Icon(Icons.block_rounded, size: 18)),
            const SizedBox(width: 6),
            if (!a.pmReviewed)
              FilledButton.tonalIcon(
                onPressed: () {
                  st.entry.loadPending(a, p);
                  st.goToTab(Tabs.entry);
                },
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// The Production Manager asked to remove operations: the DEO removes or keeps each one.
class _ConfirmCard extends StatefulWidget {
  const _ConfirmCard({super.key, required this.a});
  final MyPending a;
  @override
  State<_ConfirmCard> createState() => _ConfirmCardState();
}

class _ConfirmCardState extends State<_ConfirmCard> {
  final Map<int, bool> dec = {};
  bool busy = false;

  Future<void> _send() async {
    final st = context.read<AppState>();
    setState(() => busy = true);
    try {
      final msg = await st.deoConfirm(widget.a.id, {for (final e in dec.entries) '${e.key}': e.value});
      if (mounted) toast(context, msg);
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
    const orange = Color(0xFFC2410C);
    final idx = [for (var i = 0; i < a.operations.length; i++) if (a.operations[i].pmRemove) i];
    final done = idx.every(dec.containsKey);
    return Card(
      color: const Color(0xFFFFF7ED),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFFED7AA))),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.help_outline_rounded, color: orange, size: 20),
            const SizedBox(width: 8),
            Text(a.srn, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(width: 6),
            catPill(a.category),
          ]),
          const SizedBox(height: 4),
          Text('Production Manager ${a.pmBy} wants to remove ${idx.length == 1 ? 'this operation' : 'these operations'}. Remove or keep?',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: orange)),
          if (a.pmNote.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text('Note: ${a.pmNote}', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant))),
          const SizedBox(height: 8),
          for (final i in idx)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.operations[i].operationName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text('${a.operations[i].manpowerType} · ${a.operations[i].time}s', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                  ]),
                ),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  emptySelectionAllowed: true,
                  segments: const [ButtonSegment(value: true, label: Text('Remove')), ButtonSegment(value: false, label: Text('Keep'))],
                  selected: dec.containsKey(i) ? {dec[i]!} : <bool>{},
                  onSelectionChanged: busy ? null : (v) => setState(() => v.isEmpty ? dec.remove(i) : dec[i] = v.first),
                ),
              ]),
            ),
          const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy || !done ? null : _send,
              style: FilledButton.styleFrom(backgroundColor: orange),
              child: Text(busy ? 'Sending…' : (done ? 'Confirm & send to GM' : 'Choose Remove or Keep for each')),
            ),
          ),
        ]),
      ),
    );
  }
}
