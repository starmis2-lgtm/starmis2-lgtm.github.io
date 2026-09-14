import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../state.dart';

String driveFileId(String link) {
  final u = link.trim();
  if (u.isEmpty) return '';
  for (final re in [RegExp(r'/file/d/([a-zA-Z0-9_-]{10,})'), RegExp(r'[?&]id=([a-zA-Z0-9_-]{10,})'), RegExp(r'/d/([a-zA-Z0-9_-]{10,})')]) {
    final mm = re.firstMatch(u);
    if (mm != null) return mm.group(1)!;
  }
  if (RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(u)) return u;
  return '';
}

String thumbUrl(String link, int px) {
  final id = driveFileId(link);
  return id.isEmpty ? link : 'https://drive.google.com/thumbnail?id=$id&sz=w$px';
}

String viewUrl(String link) {
  final id = driveFileId(link);
  return id.isEmpty ? link : 'https://drive.google.com/file/d/$id/view';
}

Future<void> openLink(String url) async {
  var u = url.trim();
  if (u.isEmpty) return;
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(u)) u = 'https://$u';
  final uri = Uri.tryParse(u);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class SrnThumb extends StatelessWidget {
  const SrnThumb(this.link, {super.key, this.size = 56, this.radius = 14});
  final String link;
  final double size, radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final box = BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(radius), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)));
    if (link.trim().isEmpty) {
      return Container(width: size, height: size, decoration: box, child: Icon(Icons.image_outlined, color: cs.outline, size: size * 0.42));
    }
    return GestureDetector(
      onTap: () => openLink(viewUrl(link)),
      child: Container(
        width: size, height: size, decoration: box, clipBehavior: Clip.antiAlias,
        child: CachedNetworkImage(
          imageUrl: thumbUrl(link, (size * 3).round()),
          fit: BoxFit.cover,
          placeholder: (_, __) => Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.outline))),
          errorWidget: (_, __, ___) => Icon(Icons.broken_image_outlined, color: cs.outline, size: size * 0.4),
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color, this.icon, this.filled = false});
  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: filled ? 1 : 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 11, color: filled ? Colors.white : color), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: filled ? Colors.white : color)),
      ]),
    );
  }
}

class StatusBits {
  StatusBits(this.label, this.color, this.sub);
  final String label, sub;
  final Color color;
}

StatusBits statusBits(TaskDelay? t, {bool waiting = false}) {
  if (waiting) return StatusBits('WAITING', const Color(0xFF94A3B8), 'stitching not started');
  if (t == null || !t.hasDue) return StatusBits('NO DUE DATE', const Color(0xFF94A3B8), '');
  if (t.status == 'delayed') return StatusBits('DELAYED', const Color(0xFFB91C1C), '+${t.late}d late${t.impact > 0 ? ' · MIS -${t.impact} pts' : ''}');
  if (t.status == 'today') return StatusBits('DUE TODAY', const Color(0xFFB45309), '');
  return StatusBits('UPCOMING', const Color(0xFF047857), '${t.daysLeft} day${t.daysLeft == 1 ? '' : 's'} left');
}

/// Short status text for compact lists: "5d left", "+3d late · -6", "Today", "No due".
String shortStatus(TaskDelay? t, {bool waiting = false}) {
  if (waiting) return 'Waiting';
  if (t == null || !t.hasDue) return 'No due';
  if (t.status == 'delayed') return '+${t.late}d late${t.impact > 0 ? ' · −${t.impact}' : ''}';
  if (t.status == 'today') return 'Due today';
  return '${t.daysLeft}d left';
}

class MiniStatus extends StatelessWidget {
  const MiniStatus(this.t, {super.key, this.waiting = false});
  final TaskDelay? t;
  final bool waiting;
  @override
  Widget build(BuildContext context) {
    final b = statusBits(t, waiting: waiting);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: b.color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(6)),
      child: Text(shortStatus(t, waiting: waiting), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: b.color)),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.t, {super.key, this.waiting = false});
  final TaskDelay? t;
  final bool waiting;
  @override
  Widget build(BuildContext context) {
    final bits = statusBits(t, waiting: waiting);
    return Pill(bits.sub.isEmpty ? bits.label : '${bits.label} · ${bits.sub}', color: bits.color);
  }
}

Color catColor(String category) => category == 'Packing' ? const Color(0xFF047857) : const Color(0xFF3730A3);
Pill catPill(String category) => Pill(category, color: catColor(category));
Pill typePill(String type) => type == 'R&D' ? const Pill('R&D', color: Color(0xFF6B21A8), icon: Icons.science_outlined) : const Pill('Production', color: Color(0xFF334155), icon: Icons.factory_outlined);

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.color});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 72, height: 72, decoration: BoxDecoration(color: c.withValues(alpha: 0.10), shape: BoxShape.circle), child: Icon(icon, color: c, size: 34)),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
          if (subtitle != null) ...[const SizedBox(height: 6), Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))],
        ]),
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.hint, required this.onChanged, this.controller});
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(hintText: hint, prefixIcon: const Icon(Icons.search_rounded), fillColor: Theme.of(context).colorScheme.surface),
    );
  }
}

bool matches(String q, String text) {
  final terms = q.toLowerCase().trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
  final t = text.toLowerCase();
  return terms.every(t.contains);
}

void toast(BuildContext context, String msg, {bool error = false}) {
  final cs = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: error ? cs.onErrorContainer : cs.onPrimaryContainer, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: TextStyle(color: error ? cs.onErrorContainer : cs.onPrimaryContainer, fontWeight: FontWeight.w600))),
      ]),
      backgroundColor: error ? cs.errorContainer : cs.primaryContainer,
      duration: Duration(seconds: error ? 6 : 3),
    ));
}

/// App bar action showing the user and a logout menu.
class UserMenu extends StatelessWidget {
  const UserMenu({super.key});
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final a = st.data?.access;
    final cs = Theme.of(context).colorScheme;
    final initial = (a?.displayName ?? '?').trim();
    final letter = initial.isEmpty ? '?' : initial.replaceFirst(RegExp(r'^SG\d+-'), '').substring(0, 1).toUpperCase();
    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (v) async {
        if (v == 'refresh') await st.load();
        if (v == 'update') {
          final u = st.update;
          if (u != null) {
            openLink(u.apkUrl);
          } else if (context.mounted) {
            toast(context, 'You have the latest version (${st.appVersion}).');
          }
        }
        if (v == 'logout') {
          if (!context.mounted) return;
          final ok = await confirm(context, 'Logout', 'Logout from this device?', yes: 'Logout');
          if (ok && context.mounted) await st.logout();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, child: ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text(a?.displayName ?? '', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('${a?.department ?? ''}${a?.email.isNotEmpty == true ? '\n${a!.email}' : ''}'))),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'refresh', child: ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: Icon(Icons.refresh_rounded), title: Text('Refresh data'))),
        PopupMenuItem(value: 'update', child: ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: Icon(st.update != null ? Icons.system_update_rounded : Icons.verified_rounded, color: st.update != null ? cs.error : null), title: Text(st.update != null ? 'Update to v${st.update!.versionName}' : 'Version ${st.appVersion}'))),
        const PopupMenuItem(value: 'logout', child: ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: Icon(Icons.logout_rounded), title: Text('Logout'))),
      ],
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Stack(clipBehavior: Clip.none, children: [
          CircleAvatar(radius: 16, backgroundColor: cs.primaryContainer, child: Text(letter, style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w800, fontSize: 13))),
          if (st.syncing)
            const Positioned(right: -3, bottom: -3, child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))
          else if (st.update != null)
            Positioned(right: -2, top: -2, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle, border: Border.all(color: cs.surface, width: 1.5)))),
        ]),
      ),
    );
  }
}

Future<bool> confirm(BuildContext context, String title, String message, {String yes = 'Confirm', bool danger = false}) async {
  final cs = Theme.of(context).colorScheme;
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(style: danger ? FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError) : null, onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
      ],
    ),
  );
  return r == true;
}

/// Bottom sheet: pick an SRN with search.
Future<String?> pickSrn(BuildContext context, {required List<SrnInfo> options, String title = 'Select SRN'}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _SrnPicker(options: options, title: title),
  );
}

class _SrnPicker extends StatefulWidget {
  const _SrnPicker({required this.options, required this.title});
  final List<SrnInfo> options;
  final String title;
  @override
  State<_SrnPicker> createState() => _SrnPickerState();
}

class _SrnPickerState extends State<_SrnPicker> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final list = widget.options.where((o) => matches(q, '${o.srn} ${o.styleName}')).toList();
    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95,
      builder: (ctx, sc) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(autofocus: true, onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(hintText: 'Search SRN or style name', prefixIcon: Icon(Icons.search_rounded))),
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(icon: Icons.search_off_rounded, title: 'No SRN found')
              : ListView.separated(
                  controller: sc,
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(indent: 76),
                  itemBuilder: (_, i) {
                    final o = list[i];
                    return ListTile(
                      leading: SrnThumb(o.imageLink, size: 44, radius: 10),
                      title: Text(o.srn, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${o.styleName}${o.shippingQty > 0 ? ' · Qty ${o.shippingQty}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, o.srn),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

/// Bottom sheet: mark tasks / roles not required for an SRN.
Future<void> showNotRequired(BuildContext context, String srn) async {
  final st = context.read<AppState>();
  final p = st.data;
  if (p == null) return;
  final info = p.srn(srn);
  final marked = <String>{for (final nr in p.notRequired.where((x) => x.srn == srn)) '${nr.task}|${nr.role}'};
  final tasks = {for (final k in taskLabels.keys) k: marked.contains('$k|')};
  final roles = {for (final r in coreMakingRoles) r: marked.contains('mkRnd|$r')};
  var busy = false;

  await showModalBottomSheet<void>(
    context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final cs = Theme.of(ctx).colorScheme;
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(Icons.block_rounded, color: cs.error), const SizedBox(width: 8),
              Expanded(child: Text('Not required — $srn', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            ]),
            if (info != null) Padding(padding: const EdgeInsets.only(top: 2, bottom: 10), child: Text(info.styleName, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))),
            Text('WHOLE BULLETIN NOT REQUIRED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant, letterSpacing: 0.6)),
            ...taskLabels.entries.map((e) => CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, value: tasks[e.key], onChanged: (v) => setS(() => tasks[e.key] = v == true), title: Text(e.value), controlAffinity: ListTileControlAffinity.leading)),
            const SizedBox(height: 8),
            Text('MAKING R&D — MANPOWER NOT REQUIRED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant, letterSpacing: 0.6)),
            Wrap(
              spacing: 8, runSpacing: 4,
              children: coreMakingRoles.map((r) => FilterChip(label: Text(r), selected: roles[r]!, onSelected: (v) => setS(() => roles[r] = v))).toList(),
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : () async {
                  setS(() => busy = true);
                  final items = <Map<String, String>>[
                    for (final e in tasks.entries) if (e.value) {'task': e.key, 'role': ''},
                    for (final e in roles.entries) if (e.value) {'task': 'mkRnd', 'role': e.key},
                  ];
                  try {
                    final msg = await st.setNotRequired(srn, items);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) toast(context, msg);
                  } catch (e) {
                    setS(() => busy = false);
                    if (ctx.mounted) toast(ctx, e.toString(), error: true);
                  }
                },
                child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
              ),
            ),
          ]),
        ),
      );
    }),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(children: [
        Expanded(child: Text(text.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: cs.onSurfaceVariant))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}
