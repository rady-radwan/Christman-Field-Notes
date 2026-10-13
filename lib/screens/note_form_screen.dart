import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/photo_picker.dart';

/// New note, or editing an existing one when [existing] is given.
class NoteFormScreen extends StatefulWidget {
  const NoteFormScreen({super.key, this.existing});
  final Note? existing;

  @override
  State<NoteFormScreen> createState() => _NoteFormScreenState();
}

class _NoteFormScreenState extends State<NoteFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _comment;
  late String? _category;
  late Priority _priority;
  late Set<String> _assigned;
  final List<Uint8List> _photos = [];
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
    _category = n?.category ?? (cats.isEmpty ? null : cats.first);
    _priority = n?.priority ?? Priority.medium;
    _assigned = {...?n?.assignedIds};
  }

  @override
  void dispose() {
    _name.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _add(bool camera) async {
    final shots = await pickAndMarkUp(context, camera: camera);
    if (shots.isNotEmpty) setState(() => _photos.addAll(shots));
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Give the note a name.');
    if (_category == null) return setState(() => _error = 'Choose a category.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_editing) {
        await state.saveEdits(
          widget.existing!.copyWith(
            name: _name.text.trim(),
            comment: _comment.text.trim(),
            category: _category,
            priority: _priority,
            assignedIds: _assigned.toList(),
          ),
          addPhotos: _photos,
        );
        if (mounted) Navigator.pop(context, widget.existing!.id);
      } else {
        final note = await state.createNote(NoteDraft(
          name: _name.text.trim(),
          comment: _comment.text.trim(),
          category: _category!,
          priority: _priority,
          assignedIds: _assigned.toList(),
          newPhotos: _photos,
        ));
        if (mounted) Navigator.pop(context, note.id);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    final cats = {...?state.project?.categories, if (_category != null) _category!}.toList();
    final people = state.projectPeople.where((u) => u.id != state.me?.id).toList();
    final canPriority = !_editing || state.canChangePriority(widget.existing!);

    Widget label(String t) =>
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)));

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

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit note' : 'New note'),
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
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
            label('Note name'),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'e.g. Missing fire damper, corridor 3B'),
            ),
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
            label('Issuer comment'),
            TextField(
              controller: _comment,
              minLines: 4,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'What do you need the team to do?'),
            ),
            const SizedBox(height: 20),
            label('Category'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final cat in cats)
                FnChip(label: cat, selected: cat == _category, onTap: () => setState(() => _category = cat)),
            ]),
            const SizedBox(height: 20),
            label('Priority'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in Priority.values)
                FnChip(
                  label: p.label,
                  square: true,
                  selected: p == _priority,
                  selectedColor: p.color,
                  onTap: canPriority ? () => setState(() => _priority = p) : () {},
                ),
            ]),
            if (!canPriority) ...[
              const SizedBox(height: 6),
              Text('Only the admin or the issuer can change the priority.', style: TextStyle(fontSize: 12, color: c.muted)),
            ],
            const SizedBox(height: 20),
            label('Assign to'),
            if (people.isEmpty)
              Text('No one else is on this project yet.', style: TextStyle(color: c.muted))
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final u in people)
                  FnChip(
                    label: u.name,
                    selected: _assigned.contains(u.id),
                    onTap: () => setState(() => _assigned.contains(u.id) ? _assigned.remove(u.id) : _assigned.add(u.id)),
                  ),
              ]),
            const SizedBox(height: 8),
            Text(
              _assigned.isEmpty
                  ? 'Leave empty to make it a general note. Everyone gets notified.'
                  : 'Notifies ${_assigned.map(state.nameOf).join(', ')}.',
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
            if (!_editing) ...[
              const SizedBox(height: 20),
              Text.rich(TextSpan(children: [
                TextSpan(text: 'New notes start as ', style: TextStyle(color: c.muted)),
                TextSpan(
                  text: 'Active',
                  style: TextStyle(color: c.statusFg(NoteStatus.active), fontWeight: FontWeight.w700),
                ),
                TextSpan(text: '.', style: TextStyle(color: c.muted)),
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
