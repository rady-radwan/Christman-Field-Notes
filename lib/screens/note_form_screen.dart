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

/// New Observation, or editing an existing one when [existing] is given.
class NoteFormScreen extends StatefulWidget {
  const NoteFormScreen({super.key, this.existing});
  final Note? existing;

  @override
  State<NoteFormScreen> createState() => _NoteFormScreenState();
}

class _NoteFormScreenState extends State<NoteFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _comment;
  late final TextEditingController _location;
  late String? _category;
  late Priority _priority;
  late ObsType _type;
  DateTime? _due;
  late Set<String> _assigned;
  final List<Uint8List> _photos = [];
  final List<RecordedClip> _voice = [];
  bool _saving = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final n = widget.existing;
    final cats = context.read<AppState>().project?.categories ?? defaultCategories;
    _name = TextEditingController(text: n?.name ?? '');
    _comment = TextEditingController(text: n?.comment ?? '');
    _location = TextEditingController(text: n?.location ?? '');
    _category = n?.category ?? (cats.isEmpty ? null : cats.first);
    _priority = n?.priority ?? Priority.medium;
    _type = n?.obsType ?? ObsType.fieldObservation;
    _due = n?.dueAt;
    _assigned = {...?n?.assignedIds};
  }

  @override
  void dispose() {
    _name.dispose();
    _comment.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _add(bool camera) async {
    final shots = await pickAndMarkUp(context, camera: camera);
    if (shots.isNotEmpty) setState(() => _photos.addAll(shots));
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'Due date',
    );
    if (picked != null) setState(() => _due = endOfDay(picked));
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Give the observation a title.');
    if (_category == null) return setState(() => _error = 'Choose a category.');
    setState(() {
      _saving = true;
      _error = null;
    });
    final audio = [for (final v in _voice) v.audio];
    try {
      if (_editing) {
        await state.saveEdits(
          widget.existing!.copyWith(
            name: _name.text.trim(),
            comment: _comment.text.trim(),
            category: _category,
            priority: _priority,
            obsType: _type,
            location: _location.text.trim(),
            dueAt: _due,
            clearDue: _due == null,
            assignedIds: _assigned.toList(),
          ),
          addPhotos: _photos,
          addAudio: audio,
        );
        if (mounted) Navigator.pop(context, widget.existing!.id);
      } else {
        final note = await state.createNote(NoteDraft(
          name: _name.text.trim(),
          comment: _comment.text.trim(),
          category: _category!,
          priority: _priority,
          obsType: _type,
          location: _location.text.trim(),
          dueAt: _due,
          assignedIds: _assigned.toList(),
          newPhotos: _photos,
          newAudio: audio,
        ));
        if (mounted) Navigator.pop(context, note.id);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The number this observation will most likely get (the server makes the final call).
  String? _numberPreview(AppState state) {
    final p = state.project;
    if (p == null || _category == null) return null;
    var max = 0;
    for (final n in state.notes) {
      if (n.category == _category && (n.number ?? 0) > max) max = n.number!;
    }
    return '${p.code}-${p.categoryCode(_category!)}-${(max + 1).toString().padLeft(3, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    final cats = {...?state.project?.categories, if (_category != null) _category!}.toList();
    final people = state.projectPeople;
    final canPriority = !_editing || state.canChangePriority(widget.existing!);
    final now = DateTime.now();

    Widget label(String t, {String? hint}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            if (hint != null) TextSpan(text: '  $hint', style: TextStyle(fontSize: 12, color: c.muted)),
          ])),
        );

    Widget addTile(IconData icon, String text, VoidCallback onTap) => Material(
          color: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: c.dashed, width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _saving ? null : onTap,
            child: SizedBox(
              width: 84,
              height: 84,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: c.accentText),
                const SizedBox(height: 4),
                Text(text, style: TextStyle(color: c.accentText, fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
            ),
          ),
        );

    final categoryBox = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      label('Category'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final cat in cats)
          FnChip(
            label: cat,
            dense: true,
            square: true,
            selected: cat == _category,
            onTap: () => setState(() => _category = cat),
          ),
      ]),
    ]);

    final priorityBox = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      label('Priority'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final p in Priority.values)
          FnChip(
            label: p.label,
            dense: true,
            square: true,
            selected: p == _priority,
            selectedColor: p.color,
            onTap: canPriority ? () => setState(() => _priority = p) : null,
          ),
      ]),
      if (!canPriority) ...[
        const SizedBox(height: 6),
        Text('Only the admin or the reporter can change the priority.', style: TextStyle(fontSize: 12, color: c.muted)),
      ],
    ]);

    Widget quickDue(String text, int days) => FnChip(
          label: text,
          dense: true,
          selected: _due != null && dueText(_due!, now) == dueText(endOfDay(now.add(Duration(days: days))), now),
          onTap: () => setState(() => _due = endOfDay(now.add(Duration(days: days)))),
        );

    final preview = _editing ? widget.existing!.displayCode : _numberPreview(state);

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit Observation' : 'New Observation'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size(90, 40), shape: const StadiumBorder()),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_editing ? 'Save' : 'Publish'),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
            if (preview != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(children: [
                  Icon(Icons.tag, size: 18, color: c.accentText),
                  const SizedBox(width: 6),
                  Text(_editing ? 'Observation $preview' : 'Observation number: $preview',
                      style: TextStyle(fontWeight: FontWeight.w700, color: c.accentText)),
                  if (!_editing) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('(confirmed when published)',
                          overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
                    ),
                  ],
                ]),
              ),
            label('Observation Title'),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'e.g. Missing fire damper, corridor 3B'),
            ),
            const SizedBox(height: 20),
            label('Observation Type'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in ObsType.values)
                FnChip(
                  label: t.label,
                  icon: t.icon,
                  dense: true,
                  selected: t == _type,
                  onTap: () => setState(() => _type = t),
                ),
            ]),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, box) {
              if (box.maxWidth < 600) {
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  categoryBox,
                  const SizedBox(height: 20),
                  priorityBox,
                ]);
              }
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: categoryBox),
                const SizedBox(width: 24),
                Expanded(child: priorityBox),
              ]);
            }),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, box) {
              final location = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                label('Location', hint: 'optional'),
                TextField(
                  controller: _location,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Level 3, corridor 3B, grid C/7',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
              ]);
              final due = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                label('Due Date', hint: 'optional'),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDue,
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50), alignment: Alignment.centerLeft),
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        _due == null ? 'No due date' : '${shortDate(_due!)} · ${dueText(_due!, now)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (_due != null)
                    IconButton(
                      tooltip: 'Remove due date',
                      onPressed: () => setState(() => _due = null),
                      icon: const Icon(Icons.close),
                    ),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  quickDue('Today', 0),
                  quickDue('3 days', 3),
                  quickDue('1 week', 7),
                  quickDue('2 weeks', 14),
                ]),
              ]);
              if (box.maxWidth < 600) {
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [location, const SizedBox(height: 20), due]);
              }
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: location),
                const SizedBox(width: 24),
                Expanded(child: due),
              ]);
            }),
            const SizedBox(height: 20),
            label('Photos'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (_editing)
                for (final ref in widget.existing!.photos)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(width: 84, height: 84, child: RefImage(ref)),
                  ),
              for (var i = 0; i < _photos.length; i++)
                PendingPhoto(bytes: _photos[i], onRemove: () => setState(() => _photos.removeAt(i))),
              if (cameraAvailable) addTile(Icons.photo_camera_outlined, 'Camera', () => _add(true)),
              addTile(Icons.photo_library_outlined, cameraAvailable ? 'Gallery' : 'Add photos', () => _add(false)),
            ]),
            const SizedBox(height: 6),
            Text('Each new photo opens in the markup editor first.', style: TextStyle(fontSize: 12, color: c.muted)),
            const SizedBox(height: 20),
            label('Description'),
            TextField(
              controller: _comment,
              minLines: 4,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'What did you observe, and what needs to be done?'),
            ),
            const SizedBox(height: 10),
            if (_editing && widget.existing!.audio.isNotEmpty) ...[
              VoiceList(refs: widget.existing!.audio),
              const SizedBox(height: 8),
            ],
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (var i = 0; i < _voice.length; i++)
                VoicePlayer(
                  key: ValueKey(_voice[i].path),
                  filePath: _voice[i].path,
                  label: 'New voice message · ${clockText(_voice[i].length)}',
                  onRemove: () => setState(() => _voice.removeAt(i)),
                ),
              RecordVoiceButton(
                enabled: !_saving,
                onRecorded: (clip) => setState(() => _voice.add(clip)),
              ),
            ]),
            const SizedBox(height: 20),
            label('Assigned To'),
            if (people.isEmpty)
              Text('No one is on this project yet.', style: TextStyle(color: c.muted))
            else
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final u in people)
                  FnChip(
                    label: u.company.isEmpty ? u.name : '${u.name} · ${u.company}',
                    dense: true,
                    selected: _assigned.contains(u.id),
                    onTap: () => setState(() => _assigned.contains(u.id) ? _assigned.remove(u.id) : _assigned.add(u.id)),
                  ),
              ]),
            const SizedBox(height: 8),
            Text(
              _assigned.isEmpty
                  ? 'Leave empty to make it a general observation. Everyone on the project is notified.'
                  : 'Notifies ${_assigned.map(state.nameOf).join(', ')}.',
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
            if (!_editing) ...[
              const SizedBox(height: 20),
              Text.rich(TextSpan(children: [
                TextSpan(text: 'New observations start as ', style: TextStyle(color: c.muted)),
                TextSpan(
                  text: '${NoteStatus.open.emoji} ${NoteStatus.open.label}',
                  style: TextStyle(color: c.statusFg(NoteStatus.open), fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: '. Reported by ${state.me?.name ?? 'you'} on ${reportedText(now)}.',
                  style: TextStyle(color: c.muted),
                ),
              ])),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: c.urgentText, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ),
    );
  }
}
