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
        actions: const [UserMenu()],
      ),
      body: RefreshIndicator(
        onRefresh: () => st.load(silent: true),
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
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
          if (st.loading && all.isEmpty) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
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
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              sliver: SliverList.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) => _PendingCard(item: list[i]),
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
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: cs.primary.withValues(alpha: 0.06),
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Row(children: [
            SrnThumb(item.imageLink, size: 40, radius: 10),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(item.srn, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(item.styleName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500))),
                ]),
                Text('Qty ${item.shippingQty}${item.orderDate.isNotEmpty ? ' · Order ${item.orderDate}' : ''}${item.stitchDate.isNotEmpty ? ' · Stitch ${item.stitchDate}' : ''}', style: TextStyle(fontSize: 10.5, color: cs.outline, fontWeight: FontWeight.w600)),
              ]),
            ),
            IconButton(visualDensity: VisualDensity.compact, tooltip: 'Not required', onPressed: () => showNotRequired(context, item.srn), icon: Icon(Icons.block_rounded, size: 18, color: cs.outline)),
          ]),
        ),
        for (var i = 0; i < item.tasks.length; i++) ...[
          if (i > 0) const Divider(indent: 10, endIndent: 10),
          _TaskLine(item: item, t: item.tasks[i], st: st),
        ],
      ]),
    );
  }
}

class _TaskLine extends StatelessWidget {
  const _TaskLine({required this.item, required this.t, required this.st});
  final PendingItem item;
  final PendingTask t;
  final AppState st;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isProd = t.type == 'Production';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Row(children: [
        Icon(isProd ? Icons.factory_outlined : Icons.science_outlined, size: 15, color: isProd ? const Color(0xFF047857) : const Color(0xFF7E22CE)),
        const SizedBox(width: 7),
        Expanded(
          child: Row(children: [
            Text(t.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(width: 8),
            if (t.delay.hasDue) Text(t.delay.due, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            MiniStatus(t.delay),
          ]),
        ),
        SizedBox(
          height: 30,
          child: FilledButton.tonal(
            onPressed: () {
              final preset = t.key == 'mkRnd' && item.missingRoles.length == 1 ? item.missingRoles.first : (isProd ? 'All' : '');
              st.entry.start(item.srn, t.category, t.type, st.data, role: preset);
              st.goToTab(Tabs.entry);
            },
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            child: const Text('Create'),
          ),
        ),
      ]),
    );
  }
}
