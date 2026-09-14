import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String q = '';
  String filter = 'all';

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = st.data!;
    final cs = Theme.of(context).colorScheme;
    final all = p.pending;
    final counts = <String, int>{'all': all.length, 'delayed': 0, 'today': 0, 'upcoming': 0, 'nodue': 0};
    for (final it in all) {
      counts[it.worstKey] = (counts[it.worstKey] ?? 0) + 1;
    }
    final list = all.where((it) => (filter == 'all' || it.worstKey == filter) && matches(q, '${it.srn} ${it.styleName}')).toList();

    const defs = [
      ('all', 'All', Color(0xFF334155)),
      ('delayed', 'Delayed', Color(0xFFB91C1C)),
      ('today', 'Due today', Color(0xFFB45309)),
      ('upcoming', 'Upcoming', Color(0xFF047857)),
      ('nodue', 'No due date', Color(0xFF64748B)),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Bulletins'),
        actions: [IconButton(tooltip: 'Refresh', onPressed: st.loading ? null : () => st.load(), icon: const Icon(Icons.refresh_rounded)), const UserMenu()],
      ),
      body: RefreshIndicator(
        onRefresh: () => st.load(silent: true),
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SearchField(hint: 'Search SRN or style', onChanged: (v) => setState(() => q = v)),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: defs.where((d) => d.$1 == 'all' || (counts[d.$1] ?? 0) > 0).map((d) {
                      final on = filter == d.$1;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('${d.$2}  ${counts[d.$1]}'),
                          selected: on,
                          onSelected: (_) => setState(() => filter = d.$1),
                          selectedColor: d.$3,
                          labelStyle: TextStyle(color: on ? Colors.white : d.$3, fontWeight: FontWeight.w700),
                          side: BorderSide(color: d.$3.withValues(alpha: on ? 1 : 0.35)),
                          backgroundColor: d.$3.withValues(alpha: 0.08),
                          showCheckmark: false,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ]),
            ),
          ),
          if (st.loading) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
          if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: all.isEmpty ? Icons.task_alt_rounded : Icons.filter_alt_off_rounded,
                title: all.isEmpty ? 'All caught up!' : 'Nothing here for this filter',
                subtitle: all.isEmpty ? 'No pending bulletins right now.' : 'Try another filter or search.',
                color: const Color(0xFF047857),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _PendingCard(item: list[i]),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Text('R&D due = Order date + 10 working days · Production due = First stitch + 5 working days · −2 MIS pts per day late', textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.item});
  final PendingItem item;

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SrnThumb(item.imageLink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(item.srn, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  if (item.status == 'Partial') const Pill('Partial', color: Color(0xFFB45309)),
                  if (item.status == 'Not Started') const Pill('Not started', color: Color(0xFF64748B)),
                ]),
                Text(item.styleName.isEmpty ? '-' : item.styleName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                Text(
                  'Qty ${item.shippingQty}${item.orderDate.isNotEmpty ? ' · Order ${item.orderDate}' : ''}${item.stitchDate.isNotEmpty ? ' · Stitch ${item.stitchDate}' : ''}',
                  style: TextStyle(fontSize: 11, color: cs.outline, fontWeight: FontWeight.w600),
                ),
              ]),
            ),
            IconButton.outlined(
              tooltip: 'Not required',
              visualDensity: VisualDensity.compact,
              onPressed: () => showNotRequired(context, item.srn),
              icon: const Icon(Icons.block_rounded, size: 18),
            ),
          ]),
          for (final t in item.tasks) ...[
            const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
            Row(children: [
              Icon(t.type == 'Production' ? Icons.factory_outlined : Icons.science_outlined, size: 16, color: t.type == 'Production' ? const Color(0xFF047857) : const Color(0xFF7E22CE)),
              const SizedBox(width: 6),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  Text('Due ${t.delay.hasDue ? t.delay.due : '—'}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                ]),
              ),
              FilledButton.icon(
                onPressed: () {
                  final preset = t.key == 'mkRnd' && item.missingRoles.length == 1 ? item.missingRoles.first : (t.type == 'Production' ? 'All' : '');
                  st.entry.start(item.srn, t.category, t.type, st.data, role: preset);
                  st.goToTab(Tabs.entry);
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Create'),
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
              ),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              StatusPill(t.delay),
              if (t.key == 'mkRnd') for (final r in item.missingRoles) Pill(r, color: const Color(0xFFBE123C)),
            ]),
          ],
        ]),
      ),
    );
  }
}
