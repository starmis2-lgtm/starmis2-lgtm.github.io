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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('My Pending'), actions: [IconButton(onPressed: st.loading ? null : () => st.load(), icon: const Icon(Icons.refresh_rounded)), const UserMenu()]),
      body: RefreshIndicator(
        onRefresh: () => st.load(silent: true),
        child: list.isEmpty
            ? ListView(children: const [SizedBox(height: 120), EmptyState(icon: Icons.task_alt_rounded, title: 'No pending submissions', subtitle: 'Bulletins you submit for approval will show here until they are approved.', color: Color(0xFF047857))])
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: list.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  if (i == 0) return Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('Waiting for management approval. Edit any time before approval.', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)));
                  return _MyCard(a: list[i - 1]);
                },
              ),
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
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.srn, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text(a.styleName.isEmpty ? '-' : a.styleName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [catPill(a.category), typePill(a.type), if (a.isEditMode) const Pill('EDIT', color: Color(0xFF92400E))]),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${a.operations.length} ops', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
              Text('${(a.totalTime / 60).toStringAsFixed(2)} min', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF7E22CE))),
              Text('₹${cost.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF047857))),
            ]),
          ]),
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
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
