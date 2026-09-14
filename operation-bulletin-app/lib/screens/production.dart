import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';

class ProductionScreen extends StatefulWidget {
  const ProductionScreen({super.key});
  @override
  State<ProductionScreen> createState() => _ProductionScreenState();
}

class _ProductionScreenState extends State<ProductionScreen> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = st.data!;
    final list = p.prodPending.where((r) => matches(q, '${r.srn} ${r.styleName} ${r.category}')).toList();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Production Pending'), actions: [IconButton(onPressed: st.loading ? null : () => st.load(), icon: const Icon(Icons.refresh_rounded)), const UserMenu()]),
      body: RefreshIndicator(
        onRefresh: () => st.load(silent: true),
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SearchField(hint: 'Search SRN or style', onChanged: (v) => setState(() => q = v)),
                const SizedBox(height: 8),
                Text('R&D bulletin is done, production bulletin is pending. Due = First stitch + 5 working days.', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ]),
            ),
          ),
          if (list.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: EmptyState(icon: Icons.task_alt_rounded, title: 'No production bulletin pending', color: Color(0xFF047857)))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
              sliver: SliverList.separated(itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (_, i) => _ProdCard(r: list[i])),
            ),
        ]),
      ),
    );
  }
}

class _ProdCard extends StatelessWidget {
  const _ProdCard({required this.r});
  final ProdPending r;

  Widget _kv(BuildContext context, String k, String v) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
        Text(v.isEmpty ? '—' : v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SrnThumb(r.imageLink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.srn, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text(r.styleName.isEmpty ? '-' : r.styleName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                const SizedBox(height: 4),
                Row(children: [catPill(r.category), const SizedBox(width: 6), Text('Qty ${r.shippingQty}', style: TextStyle(fontSize: 11, color: cs.outline, fontWeight: FontWeight.w600))]),
              ]),
            ),
            IconButton.outlined(tooltip: 'Not required', visualDensity: VisualDensity.compact, onPressed: () => showNotRequired(context, r.srn), icon: const Icon(Icons.block_rounded, size: 18)),
          ]),
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
          Row(children: [_kv(context, 'R&D DONE', r.rndDate), _kv(context, 'FIRST STITCH', r.stitchDate), _kv(context, 'DUE', r.delay.due)]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Align(alignment: Alignment.centerLeft, child: StatusPill(r.delay, waiting: r.waiting))),
            FilledButton.tonalIcon(
              onPressed: () {
                st.entry.start(r.srn, r.category, 'Production', st.data, role: 'All');
                st.goToTab(Tabs.entry);
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Create'),
            ),
          ]),
        ]),
      ),
    );
  }
}
