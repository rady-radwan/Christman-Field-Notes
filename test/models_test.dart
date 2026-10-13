import 'package:christman_field_notes/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('note round-trips through JSON', () {
    final now = DateTime(2026, 10, 13, 9, 12);
    final note = Note(
      id: 'n1',
      projectId: 'p1',
      name: 'Fire damper missing',
      comment: 'Install before close-in.',
      category: 'MEP',
      priority: Priority.urgent,
      status: NoteStatus.active,
      issuerId: 'u1',
      assignedIds: const ['u2'],
      photos: const ['file:a.jpg'],
      createdAt: now,
      updatedAt: now,
      replies: [
        Reply(id: 'r1', noteId: 'n1', authorId: 'u2', text: 'On it', photos: const [], createdAt: now),
      ],
    );
    final back = Note.fromJson(note.toJson());
    expect(back.name, note.name);
    expect(back.priority, Priority.urgent);
    expect(back.replies.single.text, 'On it');
    expect(back.createdAt, now);
    expect(back.isGeneral, isFalse);
  });

  test('closed statuses', () {
    expect(NoteStatus.solved.isClosed, isTrue);
    expect(NoteStatus.deactivated.isClosed, isTrue);
    expect(NoteStatus.suspended.isClosed, isFalse);
  });

  test('initials', () {
    expect(const AppUser(id: '1', name: 'Rady Radwan', email: 'a@b.c').initials, 'RR');
  });
}
