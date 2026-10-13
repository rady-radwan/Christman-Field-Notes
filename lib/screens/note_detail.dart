import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import '../widgets/photo_picker.dart';
import 'note_form_screen.dart';

/// Full-screen page used on phones and narrow windows.
class NoteDetailScreen extends StatelessWidget {
  const NoteDetailScreen({super.key, required this.noteId});
  final String noteId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final note = state.noteById(noteId);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Note'),
        actions: [if (note != null) NoteMenu(note: note, popOnDelete: true)],
      ),
      body: NoteDetailView(noteId: noteId),
    );
  }
}

/// Edit / delete menu, shown only to people allowed to use it.
class NoteMenu extends StatelessWidget {
  const NoteMenu({super.key, required this.note, this.popOnDelete = false});
  final Note note;
  final bool popOnDelete;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final canEdit = state.canEdit(note);
    final canDelete = state.canDelete(note);
    if (!canEdit && !canDelete) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert),
      onSelected: (v) async {
        if (v == 'edit') {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => NoteFormScreen(existing: note)));
        } else if (v == 'delete') {
          final ok = await confirm(context, 'Delete this note?', 'This removes the note, its photos and replies for everyone.',
              ok: 'Delete', danger: true);
          if (!ok || !context.mounted) return;
          try {
            await state.deleteNote(note);
            if (popOnDelete && context.mounted) Navigator.of(context).pop();
          } catch (e) {
            if (context.mounted) showError(context, e);
          }
        }
      },
      itemBuilder: (_) => [
        if (canEdit) const PopupMenuItem(value: 'edit', child: Text('Edit note')),
        if (canDelete) const PopupMenuItem(value: 'delete', child: Text('Delete note')),
      ],
    );
  }
}

class NoteDetailView extends StatefulWidget {
  const NoteDetailView({super.key, required this.noteId, this.embedded = false});
  final String noteId;
  final bool embedded;

  @override
  State<NoteDetailView> createState() => _NoteDetailViewState();
}

class _NoteDetailViewState extends State<NoteDetailView> {
  int _photo = 0;
  final _reply = TextEditingController();
  final List<Uint8List> _replyPhotos = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().markSeen(widget.noteId);
  }

  @override
  void didUpdateWidget(covariant NoteDetailView old) {
    super.didUpdateWidget(old);
    if (old.noteId != widget.noteId) {
      _photo = 0;
      _reply.clear();
      _replyPhotos.clear();
    }
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send(Note note) async {
    final text = _reply.text.trim();
    if (text.isEmpty && _replyPhotos.isEmpty) return;
    setState(() => _sending = true);
    try {
      await context.read<AppState>().addReply(note, text, List.of(_replyPhotos));
      _reply.clear();
      _replyPhotos.clear();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _setStatus(Note note, NoteStatus s) async {
    final state = context.read<AppState>();
    if (s == note.status) return;
    if (s == NoteStatus.deactivated) {
      final ok = await confirm(context, 'Deactivate this note?',
          'It stays visible to everyone, marked as deactivated and grayed out.', ok: 'Deactivate');
      if (!ok) return;
    }
    try {
      await state.setStatus(note, s);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    final note = state.noteById(widget.noteId);
    if (note == null) {
      return Center(child: Text('This note was deleted.', style: TextStyle(color: c.muted)));
    }
    if (_photo >= note.photos.length) _photo = 0;

    final content = ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        ClosedFade(
          closed: note.status.isClosed,
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            PriorityBadge(note.priority, large: true),
            StatusBadge(note.status, large: true),
            CategoryTag(note.category, large: true),
          ]),
        ),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(note.name,
                style: TextStyle(fontSize: widget.embedded ? 26 : 24, fontWeight: FontWeight.w700, height: 1.15)),
          ),
          if (widget.embedded) NoteMenu(note: note),
        ]),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(style: TextStyle(fontSize: 14, color: c.muted), children: [
            const TextSpan(text: 'Issued by '),
            TextSpan(text: state.nameOf(note.issuerId), style: TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
            TextSpan(text: ' · ${dayTimeText(note.createdAt)}'),
            if (note.editedAt != null) const TextSpan(text: ' · edited'),
          ]),
        ),
        const SizedBox(height: 14),
        if (note.photos.isNotEmpty) ...[
          _MainPhoto(refs: note.photos, index: _photo),
          if (note.photos.length > 1) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: note.photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => Semantics(
                  button: true,
                  label: 'Photo ${i + 1}',
                  child: GestureDetector(
                    onTap: () => setState(() => _photo = i),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        border: Border.all(color: i == _photo ? c.accent : Colors.transparent, width: 3),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: ClipRRect(borderRadius: BorderRadius.circular(6), child: RefImage(note.photos[i])),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
        ],
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionLabel('Issuer comment'),
            const SizedBox(height: 6),
            SelectableText(note.comment.isEmpty ? 'No comment.' : note.comment,
                style: const TextStyle(fontSize: 15, height: 1.45)),
          ]),
        ),
        const SizedBox(height: 14),
        _DetailsGrid(note: note),
        if (state.canChangeStatus(note)) ...[
          const SizedBox(height: 16),
          SectionLabel('Status',
              trailing: Text(state.isAdmin ? 'Admin' : 'Issuer', style: TextStyle(fontSize: 12, color: c.muted))),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in NoteStatus.values)
              if (s != NoteStatus.deactivated || state.canDeactivate(note))
                FnChip(
                  label: s == NoteStatus.deactivated && note.status != s ? 'Deactivate' : s.label,
                  square: true,
                  selected: note.status == s,
                  onTap: () => _setStatus(note, s),
                ),
          ]),
        ],
        const SizedBox(height: 18),
        SectionLabel('Replies (${note.replies.length})'),
        const SizedBox(height: 10),
        if (note.replies.isEmpty) Text('No replies yet.', style: TextStyle(color: c.muted)),
        for (final r in note.replies) _ReplyTile(reply: r),
      ],
    );

    return Column(children: [
      Expanded(child: content),
      _Composer(
        controller: _reply,
        photos: _replyPhotos,
        sending: _sending,
        onAddPhotos: (camera) async {
          final shots = await pickAndMarkUp(context, camera: camera);
          if (shots.isNotEmpty) setState(() => _replyPhotos.addAll(shots));
        },
        onRemovePhoto: (i) => setState(() => _replyPhotos.removeAt(i)),
        onSend: () => _send(note),
      ),
    ]);
  }
}

class _MainPhoto extends StatelessWidget {
  const _MainPhoto({required this.refs, required this.index});
  final List<String> refs;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open photo full screen',
      child: GestureDetector(
        onTap: () => showPhotoViewer(context, refs, index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 280,
            color: Colors.black,
            child: Stack(fit: StackFit.expand, children: [
              RefImage(refs[index], fit: BoxFit.contain),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xE61A1A1A), borderRadius: BorderRadius.circular(6)),
                  child: Text('${index + 1} / ${refs.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Full-screen zoomable photo viewer.
void showPhotoViewer(BuildContext context, List<String> refs, int start) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _PhotoViewer(refs: refs, start: start),
  ));
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.refs, required this.start});
  final List<String> refs;
  final int start;
  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _pages = PageController(initialPage: widget.start);
  late int _i = widget.start;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: const Border(),
          title: Text('Photo ${_i + 1} of ${widget.refs.length}', style: const TextStyle(color: Colors.white)),
          actions: [
            if (widget.refs.length > 1) ...[
              IconButton(
                tooltip: 'Previous',
                onPressed: _i == 0 ? null : () => _pages.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Next',
                onPressed: _i == widget.refs.length - 1
                    ? null
                    : () => _pages.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ],
        ),
        body: PageView.builder(
          controller: _pages,
          itemCount: widget.refs.length,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (_, i) => InteractiveViewer(
            maxScale: 6,
            child: Center(child: RefImage(widget.refs[i], fit: BoxFit.contain)),
          ),
        ),
      );
}

class _DetailsGrid extends StatelessWidget {
  const _DetailsGrid({required this.note});
  final Note note;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    Widget cell(String label, Widget value) => Container(
          color: c.surface,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
            const SizedBox(height: 2),
            value,
          ]),
        );
    const valueStyle = TextStyle(fontWeight: FontWeight.w600, fontSize: 14);

    final priority = state.canChangePriority(note)
        ? DropdownButtonHideUnderline(
            child: DropdownButton<Priority>(
              value: note.priority,
              isDense: true,
              style: valueStyle.copyWith(color: c.ink, fontFamily: 'Barlow'),
              dropdownColor: c.surface,
              items: [
                for (final p in Priority.values)
                  DropdownMenuItem(
                    value: p,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: p.color, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(p.label),
                    ]),
                  ),
              ],
              onChanged: (p) async {
                if (p == null) return;
                try {
                  await state.setPriority(note, p);
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
            ),
          )
        : Text(note.priority.label, style: valueStyle);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(color: c.line, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Row(children: [
            Expanded(child: cell('Assigned to', Text(state.assignedText(note), style: valueStyle))),
            const SizedBox(width: 1),
            Expanded(child: cell('Category', Text(note.category, style: valueStyle))),
          ]),
          const SizedBox(height: 1),
          Row(children: [
            Expanded(child: cell('Priority', priority)),
            const SizedBox(width: 1),
            Expanded(child: cell('Created', Text(dayTimeText(note.createdAt), style: valueStyle))),
          ]),
        ]),
      ),
    );
  }
}

class _ReplyTile extends StatelessWidget {
  const _ReplyTile({required this.reply});
  final Reply reply;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    final name = state.nameOf(reply.authorId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Avatar(name: name),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                Text(dayTimeText(reply.createdAt), style: TextStyle(fontSize: 13, color: c.muted)),
                if (state.canDeleteReply(reply))
                  IconButton(
                    tooltip: 'Delete reply',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    color: c.muted,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await confirm(context, 'Delete this reply?', 'It will be removed for everyone.',
                          ok: 'Delete', danger: true);
                      if (!ok) return;
                      try {
                        await state.deleteReply(reply);
                      } catch (e) {
                        if (context.mounted) showError(context, e);
                      }
                    },
                  ),
              ]),
              if (reply.text.isNotEmpty) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: SelectableText(reply.text, style: const TextStyle(fontSize: 14, height: 1.4)),
                ),
              ],
              if (reply.photos.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (var i = 0; i < reply.photos.length; i++)
                    GestureDetector(
                      onTap: () => showPhotoViewer(context, reply.photos, i),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(width: 120, height: 80, child: RefImage(reply.photos[i])),
                      ),
                    ),
                ]),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.photos,
    required this.sending,
    required this.onAddPhotos,
    required this.onRemovePhoto,
    required this.onSend,
  });

  final TextEditingController controller;
  final List<Uint8List> photos;
  final bool sending;
  final void Function(bool camera) onAddPhotos;
  final void Function(int index) onRemovePhoto;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    return Container(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => PendingPhoto(bytes: photos[i], size: 64, onRemove: () => onRemovePhoto(i)),
                ),
              ),
            ),
          Row(children: [
            if (cameraAvailable)
              IconButton(
                tooltip: 'Take a photo',
                onPressed: sending ? null : () => onAddPhotos(true),
                icon: const Icon(Icons.photo_camera_outlined),
                color: c.accentText,
                style: IconButton.styleFrom(side: BorderSide(color: c.line2), minimumSize: const Size(44, 44)),
              ),
            if (cameraAvailable) const SizedBox(width: 6),
            IconButton(
              tooltip: 'Attach and mark up a photo',
              onPressed: sending ? null : () => onAddPhotos(false),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              color: c.accentText,
              style: IconButton.styleFrom(side: BorderSide(color: c.line2), minimumSize: const Size(44, 44)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Write a reply…',
                  fillColor: c.surface2,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: c.line2)),
                  enabledBorder:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: c.line2)),
                  focusedBorder:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: c.accent, width: 2)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Send reply',
              onPressed: sending ? null : onSend,
              style: IconButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.accentInk, minimumSize: const Size(44, 44)),
              icon: sending
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.accentInk))
                  : const Icon(Icons.send_rounded),
            ),
          ]),
        ]),
      ),
    );
  }
}
