import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models.dart';
import '../state.dart';
import '../widgets/common.dart';
import '../widgets/tone.dart';

class MyPendingScreen extends StatelessWidget {
  const MyPendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final p = st.data!;
    // SRN order (SRN0644A, SRN0644B, SRN0645A...), then Making before Packing, R&D before Production
    final list = [...p.myPending]..sort(_byPendingOrder);
    return Scaffold(
      appBar: AppBar(title: const Text('My Pending'), actions: const [UserMenu()]),
      body: RefreshIndicator(
        onRefresh: () => st.load(silent: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
          children: [
            const OutboxList(),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _openWithdrawn(context),
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: const Text('Withdrawn requests'),
              ),
            ),
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
    final red = ink(const Color(0xFFBE123C));
    return Card(
      color: wash(const Color(0xFFFFF1F2)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: edge(const Color(0xFFFECDD3)))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.block_rounded, color: red, size: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(r.srn, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(width: 6),
                Pill('REJECTED', color: red),
              ]),
              Text('${r.category} ${r.type}${r.styleName.isNotEmpty ? ' · ${r.styleName}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: ink(const Color(0xFF64748B)))),
              const SizedBox(height: 4),
              Text(r.reason, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: red)),
              const SizedBox(height: 2),
              Text('By ${r.rejectedBy} · ${r.rejectedAt}', style: TextStyle(fontSize: 10.5, color: ink(const Color(0xFF94A3B8)), fontWeight: FontWeight.w600)),
            ]),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            if (r.operations.isNotEmpty && !r.isDeleteRequest)
              FilledButton.tonal(
                onPressed: () {
                  st.entry.loadRejected(r, st.data!);
                  st.dismissRejected(r.id);
                  st.goToTab(Tabs.entry);
                },
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, backgroundColor: wash(const Color(0xFFFFE4E6)), foregroundColor: red),
                child: const Text('Fix & resend'),
              ),
            TextButton(
              onPressed: () async {
                if (await confirm(context, 'Remove from list', 'Remove this rejected ${r.srn} request from the list? It cannot be fixed and resent after that.', yes: 'Remove', danger: true)) {
                  st.dismissRejected(r.id);
                }
              },
              child: const Text('Remove'),
            ),
          ]),
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
    final mine = a.submittedEmail.toLowerCase() == p.access.email.toLowerCase();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
      onTap: () => _showDetails(context, a),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.srn, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                if (a.isGroup) Text('Master SRN · ${a.groupSrns.join(', ')}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.purple.shade700)),
                Text(a.styleName.isEmpty ? '-' : a.styleName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  catPill(a.category),
                  if (a.type != 'R&D') typePill(a.type),
                  if (a.isDeleteRequest) const Pill('DELETE', color: Color(0xFFBE123C)) else if (a.isEditMode) const Pill('EDIT', color: Color(0xFF92400E)),
                  Pill(stageLabel(a.stage), color: stageColor(a.stage), filled: true),
                ]),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${a.operations.length} ops', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
              Text('${(a.totalTime / 60).toStringAsFixed(2)} min', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ink(const Color(0xFF7E22CE)))),
              Text('₹${cost.toStringAsFixed(2)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ink(const Color(0xFF047857)))),
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
            if ((mine || p.access.isManagement) && !a.isDeleteRequest && a.operations.isNotEmpty) ...[
              IconButton.outlined(
                tooltip: 'Add photos', visualDensity: VisualDensity.compact,
                onPressed: () => _openPhotos(context, a),
                icon: Badge(
                  isLabelVisible: a.operations.any((o) => o.image.isEmpty),
                  smallSize: 7,
                  child: const Icon(Icons.add_a_photo_outlined, size: 18),
                ),
              ),
              const SizedBox(width: 6),
            ],
            if (mine)
              IconButton.outlined(
                tooltip: 'Delete this request', visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(foregroundColor: cs.error, side: BorderSide(color: cs.error.withValues(alpha: 0.5))),
                onPressed: () async {
                  final what = a.isDeleteRequest ? 'delete request' : (a.isEditMode ? 'pending edit' : 'pending bulletin');
                  final ok = await confirm(context, 'Delete $what?',
                      'This $what of ${a.srn} (${a.operations.length} ops) will be removed and will not go for approval.${a.isEditMode && !a.isDeleteRequest ? ' The approved bulletin stays as it is.' : ''}', yes: 'Delete', danger: true);
                  if (!ok || !context.mounted) return;
                  try {
                    final msg = await st.withdraw(a.id);
                    if (context.mounted) toast(context, msg);
                  } catch (err) {
                    if (context.mounted) toast(context, err.toString(), error: true);
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
              ),
            const SizedBox(width: 6),
            if (!a.pmReviewed && !a.isDeleteRequest && mine)
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
      ),
    );
  }
}

/// Read-only list of the operations in a request (tap on a card).
void _showDetails(BuildContext context, MyPending a) {
  final cs = Theme.of(context).colorScheme;
  showModalBottomSheet<void>(
    context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false, initialChildSize: 0.75, minChildSize: 0.4, maxChildSize: 0.95,
      builder: (ctx, sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('${a.srn} · ${a.category}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            Pill(stageLabel(a.stage), color: stageColor(a.stage), filled: true),
            if (a.isDeleteRequest) const Pill('DELETE', color: Color(0xFFBE123C)) else if (a.isEditMode) const Pill('EDIT', color: Color(0xFF92400E)),
          ]),
          if (a.isDeleteRequest) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Reason: ${a.deleteReason}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink(const Color(0xFFBE123C))))),
          if (a.pmReviewed) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Reviewed by ${a.pmBy} · ${a.pmAt}${a.pmNote.isNotEmpty ? '\nNote: ${a.pmNote}' : ''}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
          const SizedBox(height: 10),
          for (var i = 0; i < a.operations.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)))),
              child: Row(children: [
                SizedBox(width: 24, child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.outline))),
                if (a.operations[i].image.isNotEmpty) ...[
                  SrnThumb(a.operations[i].image, size: 36, radius: 7, title: a.operations[i].operationName),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.operations[i].operationName, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, decoration: a.operations[i].pmRemove ? TextDecoration.lineThrough : null)),
                    Text([a.operations[i].manpowerType, if (a.operations[i].machineType.isNotEmpty) a.operations[i].machineType, '${a.operations[i].operation1pc.isEmpty ? '1' : a.operations[i].operation1pc} ops',
                          if (a.operations[i].pmAdded) 'added by PM', if (a.operations[i].pmRemove) 'PM: remove?'].join(' · '),
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${a.operations[i].time}s', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: ink(const Color(0xFF3730A3)))),
                  if (a.operations[i].pmTime.isNotEmpty) Text('PM ${a.operations[i].pmTime}s', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ink(const Color(0xFF6D28D9)))),
                ]),
              ]),
            ),
        ],
      ),
    ),
  );
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
    final orange = ink(const Color(0xFFC2410C));
    final idx = [for (var i = 0; i < a.operations.length; i++) if (a.operations[i].pmRemove) i];
    final done = idx.every(dec.containsKey);
    return Card(
      color: wash(const Color(0xFFFFF7ED)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: edge(const Color(0xFFFED7AA)))),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.help_outline_rounded, color: orange, size: 20),
            const SizedBox(width: 8),
            Text(a.srn, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(width: 6),
            catPill(a.category),
          ]),
          const SizedBox(height: 4),
          Text('Production Manager ${a.pmBy} wants to remove ${idx.length == 1 ? 'this operation' : 'these operations'}. Remove or keep?',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: orange)),
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


/// Withdrawn requests: Restore sends one back for approval (Production Manager review again).
void _openWithdrawn(BuildContext context) {
  showModalBottomSheet<void>(
    context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
    builder: (ctx) => const _WithdrawnSheet(),
  );
}

class _WithdrawnSheet extends StatefulWidget {
  const _WithdrawnSheet();
  @override
  State<_WithdrawnSheet> createState() => _WithdrawnSheetState();
}

class _WithdrawnSheetState extends State<_WithdrawnSheet> {
  List<Map<String, dynamic>>? _list;
  String _error = '';
  String _busy = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await context.read<AppState>().withdrawnList();
      if (mounted) setState(() { _list = l; _error = ''; });
    } catch (e) {
      if (mounted) setState(() { _list = const []; _error = e.toString(); });
    }
  }

  Future<void> _restore(Map<String, dynamic> w) async {
    final id = s(w['id']);
    final ok = await confirm(context, 'Restore ${s(w['srn'])}?',
        '${s(w['category'])} ${s(w['type'])} · ${n(w['ops']).toInt()} operations will go for approval again (Production Manager review).', yes: 'Restore');
    if (!ok || !mounted) return;
    setState(() => _busy = id);
    try {
      final msg = await context.read<AppState>().restoreWithdrawn(id);
      if (mounted) toast(context, msg);
      await _load();
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
    if (mounted) setState(() => _busy = '');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final orange = ink(const Color(0xFF9A3412));
    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.95,
      builder: (ctx, sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('Withdrawn requests', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: orange)),
          const SizedBox(height: 4),
          Text('Restore sends the request back for approval with the same operations and photos.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          if (_list == null)
            const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator()))
          else if (_error.isNotEmpty)
            Text(_error, style: TextStyle(color: cs.error))
          else if (_list!.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 40), child: EmptyState(icon: Icons.inbox_outlined, title: 'No withdrawn requests', subtitle: 'Requests you take back appear here.', color: Color(0xFF64748B)))
          else
            for (final w in _list!)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s(w['srn']), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                        Text('${s(w['category'])} ${s(w['type'])}${b(w['isEditMode']) ? ' · EDIT' : ''} · ${n(w['ops']).toInt()} ops · photos ${n(w['photos']).toInt()}/${n(w['ops']).toInt()}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                        Text('Withdrawn ${s(w['withdrawnAt'])}', style: TextStyle(fontSize: 11, color: cs.outline)),
                      ]),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _busy.isNotEmpty ? null : () => _restore(w),
                      icon: _busy == s(w['id']) ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.restore_rounded, size: 18),
                      label: const Text('Restore'),
                    ),
                  ]),
                ),
              ),
        ],
      ),
    );
  }
}

/// Add / change photos of the operations of a request that is still waiting for approval.
void _openPhotos(BuildContext context, MyPending a) {
  showModalBottomSheet<void>(
    context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
    builder: (ctx) => _PhotoSheet(a: a),
  );
}

class _PhotoSheet extends StatefulWidget {
  const _PhotoSheet({required this.a});
  final MyPending a;
  @override
  State<_PhotoSheet> createState() => _PhotoSheetState();
}

class _PhotoSheetState extends State<_PhotoSheet> {
  final Map<int, String> _img = {};
  int _uploading = -1;
  bool _saving = false;

  Future<void> _pick(int i) async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context, showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Take photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_rounded), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (src == null || !mounted) return;
    final x = await ImagePicker().pickImage(source: src, maxWidth: 1200, maxHeight: 1200, imageQuality: 85);
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() => _uploading = i);
    try {
      final op = widget.a.operations[i];
      final url = await context.read<AppState>().uploadImage(bytes, 'image/jpeg', x.name, widget.a.srn, op.operationName);
      if (url.startsWith('local:')) throw Exception('No internet. Connect and add the photo again.');
      if (mounted) setState(() => _img[i] = url);
    } catch (e) {
      if (mounted) toast(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _uploading = -1);
  }

  Future<void> _save() async {
    if (_img.isEmpty) { Navigator.pop(context); return; }
    setState(() => _saving = true);
    try {
      final ops = widget.a.operations;
      final changes = [for (final e in _img.entries) {'i': '${e.key}', 'name': ops[e.key].operationName, 'img': e.value}];
      final msg = await context.read<AppState>().updatePendingMedia(widget.a.id, changes);
      if (!mounted) return;
      toast(context, msg);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ops = widget.a.operations;
    final missing = [for (var i = 0; i < ops.length; i++) if (ops[i].image.isEmpty && !_img.containsKey(i)) i].length;
    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.8, minChildSize: 0.4, maxChildSize: 0.95,
      builder: (ctx, sc) => Column(children: [
        Expanded(
          child: ListView(
            controller: sc,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              Text('Photos · ${widget.a.srn}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('${widget.a.category} ${widget.a.type} · $missing without photo. The request stays where it is (no new approval).',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 10),
              for (var i = 0; i < ops.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    SizedBox(
                      width: 52, height: 52,
                      child: (_img[i] ?? ops[i].image).isNotEmpty
                          ? SrnThumb(_img[i] ?? ops[i].image, size: 52, radius: 10)
                          : Container(decoration: BoxDecoration(color: wash(const Color(0xFFFFFBEB)), borderRadius: BorderRadius.circular(10), border: Border.all(color: edge(const Color(0xFFFDE68A)))),
                              child: Icon(Icons.no_photography_outlined, size: 20, color: ink(const Color(0xFFB45309)))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${i + 1}. ${ops[i].operationName}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                        Text(ops[i].manpowerType, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                      ]),
                    ),
                    _uploading == i
                        ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                        : TextButton.icon(
                            onPressed: _uploading >= 0 || _saving ? null : () => _pick(i),
                            icon: Icon((_img[i] ?? ops[i].image).isEmpty ? Icons.add_a_photo_outlined : Icons.cameraswitch_outlined, size: 18),
                            label: Text((_img[i] ?? ops[i].image).isEmpty ? 'Add' : 'Change'),
                          ),
                  ]),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving || _uploading >= 0 ? null : _save,
                icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
                label: Text(_img.isEmpty ? 'Close' : 'Save ${_img.length} photo${_img.length == 1 ? '' : 's'}'),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}


int _srnNum(String srn) => int.tryParse(RegExp(r'\d+').firstMatch(srn)?.group(0) ?? '') ?? 0;

int _byPendingOrder(MyPending a, MyPending b) {
  final n = _srnNum(a.srn).compareTo(_srnNum(b.srn));
  if (n != 0) return n;
  final srn = a.srn.compareTo(b.srn);
  if (srn != 0) return srn;
  int rank(MyPending x) => (x.category == 'Packing' ? 2 : 0) + (x.type == 'Production' ? 1 : 0);
  final r = rank(a).compareTo(rank(b));
  if (r != 0) return r;
  return a.submittedAt.compareTo(b.submittedAt);
}
