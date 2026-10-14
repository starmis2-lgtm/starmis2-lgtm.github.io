import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../models.dart';
import '../state.dart';
import 'tone.dart';

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

/// Drive photo of [px] width: through the Cloudflare Worker when the app uses it (adds CORS for the web app), else from Drive.
String thumbUrl(String link, int px) {
  final id = driveFileId(link);
  if (id.isEmpty) return link;
  if (imageProxyBase.isNotEmpty) {
    final u = Uri.parse(imageProxyBase);
    return u.replace(queryParameters: {'img': id, 'w': '$px'}).toString();
  }
  return 'https://drive.google.com/thumbnail?id=$id&sz=w$px';
}

/// A network photo; on the web it falls back to a plain <img> element if the image cannot be read directly.
Widget netImage(String url, {BoxFit fit = BoxFit.cover, Widget? loading, Widget? error}) {
  if (kIsWeb) {
    return Image.network(
      url, fit: fit,
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      loadingBuilder: loading == null ? null : (_, child, p) => p == null ? child : loading,
      errorBuilder: (_, __, ___) => error ?? const SizedBox.shrink(),
    );
  }
  return CachedNetworkImage(imageUrl: url, fit: fit, placeholder: (_, __) => loading ?? const SizedBox.shrink(), errorWidget: (_, __, ___) => error ?? const SizedBox.shrink());
}

/// Shows a photo full screen inside the app (pinch to zoom). [bytes] is a photo just taken, not uploaded yet.
Future<void> showPhoto(BuildContext context, String link, {String title = '', Uint8List? bytes}) {
  final local = link.startsWith('local:');
  Widget img;
  if (bytes != null) {
    img = Image.memory(bytes, fit: BoxFit.contain);
  } else if (local) {
    img = kIsWeb ? const SizedBox.shrink() : Image.file(File(link.substring(6)), fit: BoxFit.contain);
  } else {
    img = netImage(
      thumbUrl(link, 1600), fit: BoxFit.contain,
      loading: const Center(child: CircularProgressIndicator(color: Colors.white)),
      error: const Center(child: Text('Photo could not be loaded', style: TextStyle(color: Colors.white70))),
    );
  }
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Photo',
    barrierColor: Colors.black.withValues(alpha: 0.92),
    pageBuilder: (ctx, _, __) => SafeArea(
      child: Material(
        color: Colors.transparent,
        child: Stack(children: [
          Positioned.fill(child: InteractiveViewer(minScale: 1, maxScale: 5, child: Center(child: img))),
          Positioned(
            left: 4, right: 4, top: 4,
            child: Row(children: [
              Expanded(child: Padding(padding: const EdgeInsets.only(left: 12), child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)))),
              IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28), tooltip: 'Close'),
            ]),
          ),
          if (bytes == null && !local && driveFileId(link).isNotEmpty)
            Positioned(
              bottom: 8, left: 0, right: 0,
              child: Center(
                child: TextButton.icon(
                  onPressed: () => openLink(viewUrl(link)),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16, color: Colors.white70),
                  label: const Text('Open in Google Drive', style: TextStyle(color: Colors.white70)),
                ),
              ),
            ),
        ]),
      ),
    ),
  );
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
  const SrnThumb(this.link, {super.key, this.size = 56, this.radius = 14, this.title = '', this.tappable = true});
  final String link;
  final double size, radius;
  /// Shown on top of the full-screen photo.
  final String title;
  /// Tap opens the photo full screen.
  final bool tappable;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final box = BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(radius), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)));
    if (link.trim().isEmpty) {
      return Container(width: size, height: size, decoration: box, child: Icon(Icons.image_outlined, color: cs.outline, size: size * 0.42));
    }
    if (link.startsWith('local:')) {
      final local = Container(
        width: size, height: size, decoration: box, clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (kIsWeb)
            Icon(Icons.image_outlined, color: cs.outline, size: size * 0.4)
          else
            Image.file(File(link.substring(6)), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: cs.outline, size: size * 0.4)),
          Positioned(right: 2, bottom: 2, child: Icon(Icons.cloud_upload_outlined, size: size * 0.3, color: Colors.white, shadows: const [Shadow(blurRadius: 4, color: Colors.black54)])),
        ]),
      );
      return tappable ? GestureDetector(onTap: () => showPhoto(context, link, title: title), child: local) : local;
    }
    final img = Container(
      width: size, height: size, decoration: box, clipBehavior: Clip.antiAlias,
      child: netImage(
        thumbUrl(link, (size * 3).round().clamp(120, 600)),
        loading: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.outline))),
        error: Icon(Icons.broken_image_outlined, color: cs.outline, size: size * 0.4),
      ),
    );
    return tappable ? GestureDetector(onTap: () => showPhoto(context, link, title: title), child: img) : img;
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
    final c = filled ? color : ink(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? c : c.withValues(alpha: darkUi ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: filled ? 1 : 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 11, color: filled ? Colors.white : c), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: filled ? Colors.white : c)),
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
    final c = ink(color ?? cs.primary);
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
String _themeName(ThemeMode m) => m == ThemeMode.light ? 'Light' : (m == ThemeMode.dark ? 'Dark' : 'Phone');

/// Light, dark or the phone's own setting.
Future<void> _pickTheme(BuildContext context, AppState st) async {
  final picked = await showDialog<ThemeMode>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Theme'),
      children: [
        for (final x in const [
          (ThemeMode.system, 'Same as phone', Icons.phone_android_rounded),
          (ThemeMode.light, 'Light', Icons.light_mode_rounded),
          (ThemeMode.dark, 'Dark', Icons.dark_mode_rounded),
        ])
          ListTile(
            leading: Icon(x.$3),
            title: Text(x.$2),
            trailing: st.themeMode == x.$1 ? Icon(Icons.check_rounded, color: Theme.of(ctx).colorScheme.primary) : null,
            onTap: () => Navigator.pop(ctx, x.$1),
          ),
      ],
    ),
  );
  if (picked != null) await st.setThemeMode(picked);
}

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
        if (v == 'theme' && context.mounted) await _pickTheme(context, st);
        if (v == 'update') {
          if (st.update == null) await st.checkUpdate(force: true);
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
        PopupMenuItem(
          value: 'theme',
          child: ListTile(
            contentPadding: EdgeInsets.zero, dense: true, leading: const Icon(Icons.contrast_rounded), title: const Text('Theme'),
            trailing: Text(_themeName(st.themeMode), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
          ),
        ),
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

/// Queued offline writes, shown on My Pending (and a summary line on Home).
class OutboxList extends StatelessWidget {
  const OutboxList({super.key});
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final ob = st.outbox;
    if (ob.items.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
        child: Row(children: [
          Icon(st.offline ? Icons.cloud_off_rounded : Icons.cloud_sync_rounded, size: 16, color: st.offline ? cs.error : cs.primary),
          const SizedBox(width: 6),
          Expanded(child: Text(st.offline ? 'Waiting for internet · ${ob.items.length} to sync' : (ob.processing ? 'Syncing…' : '${ob.items.length} waiting to sync'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))),
          if (!st.offline && !ob.processing) TextButton(onPressed: () => st.syncOutbox(), style: TextButton.styleFrom(visualDensity: VisualDensity.compact), child: const Text('Sync now')),
        ]),
      ),
      for (final it in ob.items) ...[
        Card(
          color: it.status == 'failed' ? cs.errorContainer.withValues(alpha: 0.35) : cs.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            child: Row(children: [
              SizedBox(
                width: 26,
                child: it.status == 'syncing'
                    ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                    : Icon(it.status == 'failed' ? Icons.error_outline_rounded : Icons.schedule_rounded, size: 20, color: it.status == 'failed' ? cs.error : cs.outline),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${it.srn} · ${it.label}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  Text(
                    it.status == 'failed' ? it.lastError : (it.status == 'syncing' ? 'Sending…' : 'Saved on phone · ${l(it.data['operations']).isNotEmpty ? l(it.data['operations']).length : l(it.data['ops']).length} ops'),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: it.status == 'failed' ? cs.error : cs.onSurfaceVariant),
                  ),
                ]),
              ),
              if (it.status == 'failed') IconButton(tooltip: 'Retry', visualDensity: VisualDensity.compact, onPressed: () => ob.retry(it.id), icon: const Icon(Icons.refresh_rounded, size: 20)),
              if (it.status != 'syncing')
                IconButton(
                  tooltip: 'Discard', visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    if (await confirm(context, 'Discard', 'Delete this unsent bulletin from the phone?', yes: 'Delete', danger: true)) ob.remove(it.id);
                  },
                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: cs.outline),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 6),
      ],
      const SizedBox(height: 6),
    ]);
  }
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
