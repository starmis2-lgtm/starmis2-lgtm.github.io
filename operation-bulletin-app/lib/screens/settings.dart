import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = st.data!;
    final cs = Theme.of(context).colorScheme;
    final list = p.accessUsers.where((u) => matches(q, '${u.email} ${u.name} ${u.department} ${u.designation}')).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings · Access'), actions: [IconButton(onPressed: st.loading ? null : () => st.load(), icon: const Icon(Icons.refresh_rounded)), const UserMenu()]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => showUserSheet(context, null), icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Add user')),
      body: RefreshIndicator(
        onRefresh: () => st.load(silent: true),
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SearchField(hint: 'Search users', onChanged: (v) => setState(() => q = v)),
                const SizedBox(height: 8),
                Text('Access is read from the ACCESS sheet. Users with no tabs ticked see all normal tabs. Settings is It/Mis & Management only, Dashboard is Management only.', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ]),
            ),
          ),
          if (list.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: EmptyState(icon: Icons.people_outline_rounded, title: 'No users found'))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
              sliver: SliverList.separated(itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (_, i) => _UserCard(u: list[i])),
            ),
        ]),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.u});
  final AccessUser u;
  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final me = st.data!.access.email.toLowerCase() == u.email.toLowerCase();
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showUserSheet(context, u),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 20, backgroundColor: cs.primaryContainer, child: Text(u.name.replaceFirst(RegExp(r'^SG\d+-'), '').isEmpty ? '?' : u.name.replaceFirst(RegExp(r'^SG\d+-'), '')[0].toUpperCase(), style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w800))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(u.name.isEmpty ? '-' : u.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                  if (me) Padding(padding: const EdgeInsets.only(left: 6), child: Text('(you)', style: TextStyle(fontSize: 11, color: cs.outline))),
                ]),
                Text(u.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                Text('${u.designation.isEmpty ? '-' : u.designation} · ${u.department.isEmpty ? '-' : u.department}', style: TextStyle(fontSize: 11, color: cs.outline, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  u.pin.isNotEmpty ? const Pill('PIN set', color: Color(0xFF065F46), icon: Icons.key_rounded) : const Pill('No PIN', color: Color(0xFFBE123C), icon: Icons.key_off_rounded),
                  if (u.tabs.isEmpty) const Pill('All tabs', color: Color(0xFF64748B)) else ...u.tabs.map((t) => Pill(t, color: const Color(0xFF3730A3))),
                ]),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.outline),
          ]),
        ),
      ),
    );
  }
}

Future<void> showUserSheet(BuildContext context, AccessUser? u) async {
  final st = context.read<AppState>();
  final p = st.data!;
  final email = TextEditingController(text: u?.email ?? '');
  final name = TextEditingController(text: u?.name ?? '');
  final desig = TextEditingController(text: u?.designation ?? '');
  final dept = TextEditingController(text: u?.department ?? '');
  final pin = TextEditingController(text: u?.pin ?? '');
  final tabs = <String>{...(u?.tabs ?? const [])};
  final isMe = u != null && u.email.toLowerCase() == p.access.email.toLowerCase();
  var busy = false;
  const depts = ['Management', 'It/Mis', 'Production Admin', 'PPC'];

  await showModalBottomSheet<void>(
    context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final cs = Theme.of(ctx).colorScheme;
      Future<void> save() async {
        final em = email.text.trim().toLowerCase();
        if (em.isEmpty || !em.contains('@')) {
          toast(ctx, 'Enter a valid email.', error: true);
          return;
        }
        if (name.text.trim().isEmpty) {
          toast(ctx, 'Name is required.', error: true);
          return;
        }
        final pv = pin.text.trim();
        if (pv.isNotEmpty && !RegExp(r'^\d{4,8}$').hasMatch(pv)) {
          toast(ctx, 'PIN must be 4 to 8 digits.', error: true);
          return;
        }
        setS(() => busy = true);
        try {
          final msg = await st.saveUser({'originalEmail': u?.email ?? '', 'email': em, 'name': name.text.trim(), 'designation': desig.text.trim(), 'department': dept.text.trim(), 'tabs': tabs.toList(), 'pin': pv});
          if (ctx.mounted) Navigator.pop(ctx);
          if (context.mounted) toast(context, msg);
        } catch (e) {
          setS(() => busy = false);
          if (ctx.mounted) toast(ctx, e.toString(), error: true);
        }
      }

      Future<void> remove() async {
        if (u == null) return;
        final ok = await confirm(ctx, 'Remove user', 'Remove access for ${u.email}?', yes: 'Remove', danger: true);
        if (!ok) return;
        setS(() => busy = true);
        try {
          final msg = await st.deleteUser(u.email);
          if (ctx.mounted) Navigator.pop(ctx);
          if (context.mounted) toast(context, msg);
        } catch (e) {
          setS(() => busy = false);
          if (ctx.mounted) toast(ctx, e.toString(), error: true);
        }
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(u == null ? 'Add user' : 'Edit user', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, autocorrect: false, decoration: const InputDecoration(labelText: 'Email *', hintText: 'name@starglobal.in')),
            const SizedBox(height: 10),
            TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name *', hintText: 'SG00000-Name')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: desig, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Designation'))),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: pin, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                  decoration: const InputDecoration(labelText: 'Login PIN', hintText: '4-8 digits'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Autocomplete<String>(
              initialValue: TextEditingValue(text: dept.text),
              optionsBuilder: (v) => depts.where((d) => d.toLowerCase().contains(v.text.toLowerCase())),
              onSelected: (v) => dept.text = v,
              fieldViewBuilder: (ctx2, ctl, fn, onSubmit) {
                ctl.addListener(() => dept.text = ctl.text);
                return TextField(controller: ctl, focusNode: fn, decoration: const InputDecoration(labelText: 'Department', hintText: 'Management / It/Mis / Production Admin / PPC'));
              },
            ),
            const SizedBox(height: 14),
            Text('TABS ALLOWED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: cs.onSurfaceVariant)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: p.allTabs.map((t) => FilterChip(label: Text(t), selected: tabs.contains(t), onSelected: (v) => setS(() => v ? tabs.add(t) : tabs.remove(t)))).toList()),
            const SizedBox(height: 6),
            Text('Leave all unticked to allow every normal tab. Dashboard needs Department = Management. Settings needs It/Mis or Management. PIN is for mobile login and must be unique per user.', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            Row(children: [
              if (u != null && !isMe) ...[
                OutlinedButton.icon(onPressed: busy ? null : remove, icon: const Icon(Icons.delete_outline_rounded, size: 18), label: const Text('Remove'), style: OutlinedButton.styleFrom(foregroundColor: cs.error)),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : save,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
                ),
              ),
            ]),
          ]),
        ),
      );
    }),
  );
}
