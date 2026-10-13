import 'package:flutter/material.dart';

/// Note priority, most urgent first. The order of the values is the sort order.
enum Priority {
  urgent('Urgent', Color(0xFFB3261E)),
  critical('Critical', Color(0xFFC25400)),
  high('High', Color(0xFF8A6A00)),
  medium('Medium', Color(0xFF2F62A8)),
  low('Low', Color(0xFF646B72));

  const Priority(this.label, this.color);
  final String label;
  final Color color;

  static Priority fromName(String? s) =>
      Priority.values.firstWhere((p) => p.name == s, orElse: () => Priority.medium);
}

enum NoteStatus {
  active('Active'),
  suspended('Suspended'),
  solved('Solved'),
  deactivated('Deactivated');

  const NoteStatus(this.label);
  final String label;

  /// Solved and deactivated notes are "closed" and shown in gray.
  bool get isClosed => this == NoteStatus.solved || this == NoteStatus.deactivated;

  static NoteStatus fromName(String? s) =>
      NoteStatus.values.firstWhere((p) => p.name == s, orElse: () => NoteStatus.active);
}

enum MemberStatus {
  pending,
  approved,
  removed;

  static MemberStatus fromName(String? s) =>
      MemberStatus.values.firstWhere((p) => p.name == s, orElse: () => MemberStatus.pending);
}

const defaultCategories = ['Safety', 'MEP', 'Steel', 'Structure', 'Architecture'];

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.isAdmin = false,
    this.status = MemberStatus.pending,
  });

  final String id;
  final String name;
  final String email;
  final bool isAdmin;
  final MemberStatus status;

  bool get isApproved => status == MemberStatus.approved;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  AppUser copyWith({String? name, bool? isAdmin, MemberStatus? status}) => AppUser(
        id: id,
        name: name ?? this.name,
        email: email,
        isAdmin: isAdmin ?? this.isAdmin,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'is_admin': isAdmin,
        'status': status.name,
      };

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        isAdmin: (j['is_admin'] ?? false) as bool,
        status: MemberStatus.fromName(j['status'] as String?),
      );
}

class Project {
  const Project({required this.id, required this.name, required this.categories});
  final String id;
  final String name;
  final List<String> categories;

  Project copyWith({String? name, List<String>? categories}) =>
      Project(id: id, name: name ?? this.name, categories: categories ?? this.categories);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'categories': categories};

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        categories: ((j['categories'] as List?) ?? defaultCategories).map((e) => e.toString()).toList(),
      );
}

class Reply {
  const Reply({
    required this.id,
    required this.noteId,
    required this.authorId,
    required this.text,
    required this.photos,
    required this.createdAt,
    this.editedAt,
  });

  final String id;
  final String noteId;
  final String authorId;
  final String text;
  final List<String> photos;
  final DateTime createdAt;
  final DateTime? editedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'note_id': noteId,
        'author_id': authorId,
        'text': text,
        'photos': photos,
        'created_at': createdAt.toUtc().toIso8601String(),
        'edited_at': editedAt?.toUtc().toIso8601String(),
      };

  factory Reply.fromJson(Map<String, dynamic> j) => Reply(
        id: j['id'] as String,
        noteId: j['note_id'] as String,
        authorId: (j['author_id'] ?? '') as String,
        text: (j['text'] ?? '') as String,
        photos: ((j['photos'] as List?) ?? const []).map((e) => e.toString()).toList(),
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        editedAt: j['edited_at'] == null ? null : DateTime.parse(j['edited_at'] as String).toLocal(),
      );
}

class Note {
  const Note({
    required this.id,
    required this.projectId,
    required this.name,
    required this.comment,
    required this.category,
    required this.priority,
    required this.status,
    required this.issuerId,
    required this.assignedIds,
    required this.photos,
    required this.createdAt,
    required this.updatedAt,
    this.editedAt,
    this.replies = const [],
  });

  final String id;
  final String projectId;
  final String name;
  final String comment;
  final String category;
  final Priority priority;
  final NoteStatus status;
  final String issuerId;
  final List<String> assignedIds;
  final List<String> photos;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? editedAt;
  final List<Reply> replies;

  /// A note with nobody assigned is a general note for everyone.
  bool get isGeneral => assignedIds.isEmpty;

  DateTime get lastActivity {
    var last = createdAt;
    for (final r in replies) {
      if (r.createdAt.isAfter(last)) last = r.createdAt;
    }
    if (updatedAt.isAfter(last)) last = updatedAt;
    return last;
  }

  Note copyWith({
    String? name,
    String? comment,
    String? category,
    Priority? priority,
    NoteStatus? status,
    List<String>? assignedIds,
    List<String>? photos,
    DateTime? updatedAt,
    DateTime? editedAt,
    List<Reply>? replies,
  }) =>
      Note(
        id: id,
        projectId: projectId,
        name: name ?? this.name,
        comment: comment ?? this.comment,
        category: category ?? this.category,
        priority: priority ?? this.priority,
        status: status ?? this.status,
        issuerId: issuerId,
        assignedIds: assignedIds ?? this.assignedIds,
        photos: photos ?? this.photos,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        editedAt: editedAt ?? this.editedAt,
        replies: replies ?? this.replies,
      );

  /// Row shape shared by the local file and the server table (replies excluded).
  Map<String, dynamic> toRow() => {
        'id': id,
        'project_id': projectId,
        'name': name,
        'comment': comment,
        'category': category,
        'priority': priority.name,
        'status': status.name,
        'issuer_id': issuerId,
        'assigned_ids': assignedIds,
        'photos': photos,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'edited_at': editedAt?.toUtc().toIso8601String(),
      };

  Map<String, dynamic> toJson() => {...toRow(), 'replies': replies.map((r) => r.toJson()).toList()};

  factory Note.fromJson(Map<String, dynamic> j) {
    final replies = ((j['replies'] as List?) ?? const [])
        .map((e) => Reply.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return Note(
      id: j['id'] as String,
      projectId: j['project_id'] as String,
      name: (j['name'] ?? '') as String,
      comment: (j['comment'] ?? '') as String,
      category: (j['category'] ?? '') as String,
      priority: Priority.fromName(j['priority'] as String?),
      status: NoteStatus.fromName(j['status'] as String?),
      issuerId: (j['issuer_id'] ?? '') as String,
      assignedIds: ((j['assigned_ids'] as List?) ?? const []).map((e) => e.toString()).toList(),
      photos: ((j['photos'] as List?) ?? const []).map((e) => e.toString()).toList(),
      createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse((j['updated_at'] ?? j['created_at']) as String).toLocal(),
      editedAt: j['edited_at'] == null ? null : DateTime.parse(j['edited_at'] as String).toLocal(),
      replies: replies,
    );
  }
}

/// What the New note form produces. Photos are finished (marked-up) JPEG bytes.
class NoteDraft {
  NoteDraft({
    required this.name,
    required this.comment,
    required this.category,
    required this.priority,
    required this.assignedIds,
    required this.newPhotos,
  });

  final String name;
  final String comment;
  final String category;
  final Priority priority;
  final List<String> assignedIds;
  final List<List<int>> newPhotos;
}
