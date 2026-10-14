import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import '../widgets/photo_picker.dart';
import '../widgets/voice.dart';
import 'note_form_screen.dart';
import 'sign_in_screen.dart';

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
        title: Text(note?.displayCode ?? 'Observation'),
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
          final ok = await confirm(context, 'Delete this observation?',
              'This removes the observation, its photos, voice messages and discussion for everyone.\n\n'
              'To keep a record instead, set the status to Voided.',
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
        if (canEdit) const PopupMenuItem(value: 'edit', child: Text('Edit observation')),
        if (canDelete) const PopupMenuItem(value: 'delete', child: Text('Delete observation')),
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
  final List<RecordedClip> _replyVoice = [];
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
      _replyVoice.clear();
    }
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send(Note note) async {
    final text = _reply.text.trim();
    if (text.isEmpty && _replyPhotos.isEmpty && _replyVoice.isEmpty) return;
    setState(() => _sending = true);
    try {
      await context
          .read<AppState>()
          .addReply(note, text, List.of(_replyPhotos), audio: [for (final v in _replyVoice) v.audio]);
      _reply.clear();
      _replyPhotos.clear();
      _replyVoice.clear();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _setStatus(Note note, NoteStatus s) async {
    final state = context.read<AppState>();
    if (s == note.status) return;
    if (s == NoteStatus.voided) {
      final ok = await confirm(context, 'Void this observation?',
          'Use this when it was canceled or created by mistake. It stays visible to everyone, marked Voided and grayed out.',
          ok: 'Void');
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
      return Center(child: Text('This observation was deleted.', style: TextStyle(color: c.muted)));
    }
    if (_photo >= note.photos.length) _photo = 0;

    final content = ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        ClosedFade(
          closed: note.status.isClosed,
          child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            CodeTag(note, large: true),
            const SizedBox(width: 2),
            TypeTag(note.obsType, large: true),
            PriorityBadge(note.priority, large: true),
            StatusBadge(note.status, large: true),
            CategoryTag(note.category, large: true),
            OverdueBadge(note, large: true),
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
            const TextSpan(text: 'Reported by '),
            TextSpan(text: state.nameOf(note.issuerId), style: TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
            if (state.companyOf(note.issuerId).isNotEmpty) TextSpan(text: ' (${state.companyOf(note.issuerId)})'),
            TextSpan(text: ' · ${reportedText(note.createdAt)}'),
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
            const SectionLabel('Description'),
            const SizedBox(height: 6),
            SelectableText(note.comment.isEmpty ? 'No description.' : note.comment,
                style: const TextStyle(fontSize: 15, height: 1.45)),
            if (note.audio.isNotEmpty) ...[
              const SizedBox(height: 10),
              VoiceList(refs: note.audio),
            ],
          ]),
        ),
        const SizedBox(height: 14),
        _DetailsGrid(note: note),
        const SizedBox(height: 16),
        SectionLabel('Status',
            trailing: Text(
              state.canChangeStatus(note) ? (state.isAdmin ? 'You can change it (admin)' : 'You can change it (reporter)') : '',
              style: TextStyle(fontSize: 12, color: c.muted),
            )),
        const SizedBox(height: 8),
        if (state.canChangeStatus(note))
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in NoteStatus.values)
              Tooltip(
                message: s.meaning,
                child: FnChip(
                  label: '${s.emoji} ${s.label}',
                  square: true,
                  dense: true,
                  selected: note.status == s,
                  onTap: () => _setStatus(note, s),
                ),
              ),
          ])
        else
          Row(children: [
            StatusBadge(note.status, large: true),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${note.status.meaning}. Only the admin and the reporter (${state.nameOf(note.issuerId)}) can change the status'
                '${state.isAssignedToMe(note) ? ' — tell them in the Discussion when it is corrected.' : '.'}',
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
            ),
          ]),
        const SizedBox(height: 18),
        SectionLabel('Discussion (${note.replies.length})'),
        const SizedBox(height: 10),
        if (note.replies.isEmpty) Text('No messages yet.', style: TextStyle(color: c.muted)),
        for (final r in note.replies) _ReplyTile(reply: r),
      ],
    );

    return Column(children: [
      Expanded(child: content),
      if (!state.canContribute)
        _JoinBar(pending: state.isPending)
      else
        _Composer(
          controller: _reply,
          photos: _replyPhotos,
          voice: _replyVoice,
          sending: _sending,
          onAddPhotos: (camera) async {
            final shots = await pickAndMarkUp(context, camera: camera);
            if (shots.isNotEmpty) setState(() => _replyPhotos.addAll(shots));
          },
          onRemovePhoto: (i) => setState(() => _replyPhotos.removeAt(i)),
          onRecorded: (clip) => setState(() => _replyVoice.add(clip)),
          onRemoveVoice: (i) => setState(() => _replyVoice.removeAt(i)),
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
    Widget cell(String label, Widget value) => Padding(
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
              style: valueStyle.copyWith(color: c.ink, fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily),
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

    final Widget due;
    if (note.dueAt == null) {
      due = Text('No due date', style: valueStyle.copyWith(color: c.muted));
    } else if (note.isOverdue) {
      due = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(shortDate(note.dueAt!), style: valueStyle),
        const SizedBox(height: 4),
        OverdueBadge(note),
      ]);
    } else {
      due = Text(
        note.status.isClosed ? shortDate(note.dueAt!) : '${shortDate(note.dueAt!)} · ${dueText(note.dueAt!)}',
        style: valueStyle,
      );
    }

    final issuerCompany = state.companyOf(note.issuerId);
    final pairs = <(String, Widget)>[
      ('Reported By', Text(issuerCompany.isEmpty ? state.nameOf(note.issuerId) : '${state.nameOf(note.issuerId)} · $issuerCompany',
          style: valueStyle)),
      ('Reported On', Text(reportedText(note.createdAt), style: valueStyle)),
      ('Assigned To', Text(state.assignedText(note), style: valueStyle)),
      ('Category', Text(note.category, style: valueStyle)),
      ('Priority', priority),
      ('Observation Type', Text(note.obsType.label, style: valueStyle)),
      ('Location', Text(note.location.isEmpty ? '—' : note.location, style: valueStyle)),
      ('Due Date', due),
    ];

    return Container(
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(12)),
      child: Table(
        border: TableBorder.symmetric(inside: BorderSide(color: c.line)),
        children: [
          for (var i = 0; i < pairs.length; i += 2)
            TableRow(children: [cell(pairs[i].$1, pairs[i].$2), cell(pairs[i + 1].$1, pairs[i + 1].$2)]),
        ],
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
                    tooltip: 'Delete message',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    color: c.muted,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await confirm(context, 'Delete this message?', 'It will be removed for everyone.',
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
              if (reply.audio.isNotEmpty) ...[
                const SizedBox(height: 8),
                VoiceList(refs: reply.audio),
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
    required this.voice,
    required this.sending,
    required this.onAddPhotos,
    required this.onRemovePhoto,
    required this.onRecorded,
    required this.onRemoveVoice,
    required this.onSend,
  });

  final TextEditingController controller;
  final List<Uint8List> photos;
  final List<RecordedClip> voice;
  final bool sending;
  final void Function(bool camera) onAddPhotos;
  final void Function(int index) onRemovePhoto;
  final void Function(RecordedClip clip) onRecorded;
  final void Function(int index) onRemoveVoice;
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
          if (voice.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (var i = 0; i < voice.length; i++)
                    VoicePlayer(
                      key: ValueKey(voice[i].path),
                      filePath: voice[i].path,
                      label: 'Voice · ${clockText(voice[i].length)}',
                      onRemove: () => onRemoveVoice(i),
                    ),
                ]),
              ),
            ),
          Row(children: [
            RecordVoiceButton(compact: true, enabled: !sending, onRecorded: onRecorded),
            const SizedBox(width: 6),
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
                  hintText: 'Add to the discussion…',
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
              tooltip: 'Send',
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

/// Replaces the reply box for guests and people waiting for approval.
class _JoinBar extends StatelessWidget {
  const _JoinBar({required this.pending});
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    return Container(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
      child: SafeArea(
        top: false,
        child: Row(children: [
          Icon(pending ? Icons.hourglass_top_rounded : Icons.lock_outline, size: 18, color: c.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pending
                  ? 'You can join the discussion once an admin approves your account.'
                  : 'Sign in to join the discussion or add photos.',
              style: TextStyle(color: c.muted),
            ),
          ),
          if (!pending) const SignInButton(),
        ]),
      ),
    );
  }
}
