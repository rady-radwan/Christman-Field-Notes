import 'package:christman_field_notes/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 13, 9, 12);

  Note obs({NoteStatus status = NoteStatus.open, DateTime? due}) => Note(
        id: 'n1',
        projectId: 'p1',
        name: 'Fire damper missing',
        comment: 'Install before close-in.',
        category: 'MEP',
        priority: Priority.urgent,
        status: status,
        issuerId: 'u1',
        assignedIds: const ['u2'],
        photos: const ['file:a.jpg'],
        createdAt: now,
        updatedAt: now,
        obsType: ObsType.constructionIssue,
        location: 'Level 3, corridor 3B',
        dueAt: due,
        number: 7,
        code: 'NCMC-MEP-007',
        audio: const ['file:v.m4a'],
        replies: [
          Reply(id: 'r1', noteId: 'n1', authorId: 'u2', text: 'On it', photos: const [], audio: const ['file:r.m4a'], createdAt: now),
        ],
      );

  test('observation round-trips through JSON', () {
    final note = obs(due: DateTime(2026, 10, 20, 23, 59, 59));
    final back = Note.fromJson(note.toJson());
    expect(back.name, note.name);
    expect(back.priority, Priority.urgent);
    expect(back.obsType, ObsType.constructionIssue);
    expect(back.location, 'Level 3, corridor 3B');
    expect(back.dueAt, note.dueAt);
    expect(back.code, 'NCMC-MEP-007');
    expect(back.audio, ['file:v.m4a']);
    expect(back.replies.single.text, 'On it');
    expect(back.replies.single.audio, ['file:r.m4a']);
    expect(back.createdAt, now);
    expect(back.isGeneral, isFalse);
    expect(note.toRow()['status'], 'open');
  });

  test('statuses from the database, including names used before 0.7', () {
    expect(NoteStatus.fromName('in_progress'), NoteStatus.inProgress);
    expect(NoteStatus.fromName('pending_verification'), NoteStatus.pendingVerification);
    expect(NoteStatus.fromName('active'), NoteStatus.open);
    expect(NoteStatus.fromName('suspended'), NoteStatus.onHold);
    expect(NoteStatus.fromName('solved'), NoteStatus.resolved);
    expect(NoteStatus.fromName('deactivated'), NoteStatus.voided);
  });

  test('closed statuses', () {
    expect(NoteStatus.resolved.isClosed, isTrue);
    expect(NoteStatus.voided.isClosed, isTrue);
    expect(NoteStatus.onHold.isClosed, isFalse);
    expect(NoteStatus.pendingVerification.isClosed, isFalse);
  });

  test('overdue only while open and past the due moment', () {
    final due = DateTime(2026, 10, 14, 23, 59, 59);
    expect(obs(due: due).isOverdueAt(DateTime(2026, 10, 14, 12)), isFalse);
    expect(obs(due: due).isOverdueAt(DateTime(2026, 10, 15, 8)), isTrue);
    expect(obs(due: due, status: NoteStatus.resolved).isOverdueAt(DateTime(2026, 10, 15, 8)), isFalse);
    expect(obs().isOverdueAt(DateTime(2030)), isFalse);
  });

  test('abbreviations', () {
    expect(suggestProjectAbbr('New Castle Medical Center Project'), 'NCMC');
    expect(suggestCategoryAbbr('Safety'), 'SAF');
    expect(suggestCategoryAbbr('Fire protection'), 'FIR');
    final p = Project.fromJson({'id': 'p', 'name': 'Piney Branch Tunnel', 'categories': ['MEP', 'Electrical']});
    expect(p.code, 'PBT');
    expect(p.categoryCode('Electrical'), 'ELE');
  });

  test('initials', () {
    expect(const AppUser(id: '1', name: 'Rady Radwan', email: 'a@b.c').initials, 'RR');
  });
}
