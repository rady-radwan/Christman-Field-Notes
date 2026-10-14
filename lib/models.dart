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

/// Observation status workflow. Only the admin and the reporter can change it.
enum NoteStatus {
  open('open', 'Open', '🔵', 'Created and awaiting action'),
  inProgress('in_progress', 'In Progress', '🟡', 'The assigned person is addressing it'),
  pendingVerification('pending_verification', 'Pending Verification', '🟠',
      'Reported as corrected; waiting for verification'),
  resolved('resolved', 'Resolved', '🟢', 'The correction was verified'),
  onHold('on_hold', 'On Hold', '⚪', 'Work temporarily suspended'),
  voided('voided', 'Voided', '⚫', 'Canceled or created by mistake');

  const NoteStatus(this.dbName, this.label, this.emoji, this.meaning);
  final String dbName;
  final String label;
  final String emoji;
  final String meaning;

  /// Resolved and voided observations are "closed" and shown in gray.
  bool get isClosed => this == NoteStatus.resolved || this == NoteStatus.voided;

  static NoteStatus fromName(String? s) => switch (s) {
        // Names used before version 0.7.
        'active' => NoteStatus.open,
        'suspended' => NoteStatus.onHold,
        'solved' => NoteStatus.resolved,
        'deactivated' => NoteStatus.voided,
        _ => NoteStatus.values.firstWhere((v) => v.dbName == s || v.name == s, orElse: () => NoteStatus.open),
      };
}

/// What kind of observation it is (chosen when it is created).
enum ObsType {
  fieldObservation('field_observation', 'Field Observation', Icons.visibility_outlined),
  constructionIssue('construction_issue', 'Construction Issue', Icons.construction),
  safetyConcern('safety_concern', 'Safety Concern', Icons.health_and_safety_outlined),
  coordinationRequest('coordination_request', 'Coordination Request', Icons.hub_outlined),
  instruction('instruction', 'Instruction', Icons.assignment_outlined),
  followUp('follow_up', 'Follow-up Task', Icons.task_alt),
  general('general', 'General', Icons.notes);

  const ObsType(this.dbName, this.label, this.icon);
  final String dbName;
  final String label;
  final IconData icon;

  static ObsType fromName(String? s) =>
      ObsType.values.firstWhere((v) => v.dbName == s || v.name == s, orElse: () => ObsType.general);
}

enum MemberStatus {
  pending,
  approved,
  removed;

  static MemberStatus fromName(String? s) =>
      MemberStatus.values.firstWhere((p) => p.name == s, orElse: () => MemberStatus.pending);
}

const defaultCategories = ['Safety', 'MEP', 'Steel', 'Structure', 'Architecture'];

/// Suggested short codes for the standard categories.
const _knownAbbrs = {'Safety': 'SAF', 'MEP': 'MEP', 'Steel': 'STL', 'Structure': 'STR', 'Architecture': 'ARC'};

/// "SAF" for Safety, otherwise the first three letters in capitals.
String suggestCategoryAbbr(String category) {
  final known = _knownAbbrs[category];
  if (known != null) return known;
  final letters = category.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  return letters.length <= 3 ? letters : letters.substring(0, 3);
}

/// "NCMC" for "New Castle Medical Center Project".
String suggestProjectAbbr(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && RegExp(r'^[A-Za-z0-9]').hasMatch(w) && w.toLowerCase() != 'project');
  final s = words.map((w) => w[0]).join().toUpperCase();
  return s.isEmpty ? 'PRJ' : s;
}

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
List<String> _strings(Object? v) => ((v as List?) ?? const []).map((e) => e.toString()).toList();

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.isAdmin = false,
    this.status = MemberStatus.pending,
    this.company = '',
  });

  final String id;
  final String name;
  final String email;
  final bool isAdmin;
  final MemberStatus status;

  /// Company or trade, e.g. "Mechanical Contractor".
  final String company;

  bool get isApproved => status == MemberStatus.approved;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  AppUser copyWith({String? name, bool? isAdmin, MemberStatus? status, String? company}) => AppUser(
        id: id,
        name: name ?? this.name,
        email: email,
        isAdmin: isAdmin ?? this.isAdmin,
        status: status ?? this.status,
        company: company ?? this.company,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'is_admin': isAdmin,
        'status': status.name,
        'company': company,
      };

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        isAdmin: (j['is_admin'] ?? false) as bool,
        status: MemberStatus.fromName(j['status'] as String?),
        company: (j['company'] ?? '') as String,
      );
}

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.categories,
    this.abbr = '',
    this.categoryAbbrs = const {},
    this.guestVisible = false,
  });

  final String id;
  final String name;
  final List<String> categories;

  /// Short code at the start of every observation number, e.g. "NCMC".
  final String abbr;

  /// Category -> short code, e.g. "Safety" -> "SAF".
  final Map<String, String> categoryAbbrs;

  /// People who are not signed in may look at this project (read-only).
  final bool guestVisible;

  String get code => abbr.isEmpty ? suggestProjectAbbr(name) : abbr;
  String categoryCode(String category) {
    final a = categoryAbbrs[category];
    return (a == null || a.isEmpty) ? suggestCategoryAbbr(category) : a;
  }

  Project copyWith({
    String? name,
    List<String>? categories,
    String? abbr,
    Map<String, String>? categoryAbbrs,
    bool? guestVisible,
  }) =>
      Project(
        id: id,
        name: name ?? this.name,
        categories: categories ?? this.categories,
        abbr: abbr ?? this.abbr,
        categoryAbbrs: categoryAbbrs ?? this.categoryAbbrs,
        guestVisible: guestVisible ?? this.guestVisible,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'categories': categories,
        'abbr': abbr,
        'category_abbrs': categoryAbbrs,
        'guest_visible': guestVisible,
      };

  factory Project.fromJson(Map<String, dynamic> j) {
    final name = (j['name'] ?? '') as String;
    final cats = ((j['categories'] as List?) ?? defaultCategories).map((e) => e.toString()).toList();
    final raw = (j['category_abbrs'] as Map?) ?? const {};
    return Project(
      id: j['id'] as String,
      name: name,
      categories: cats,
      abbr: ((j['abbr'] ?? '') as String).isEmpty ? suggestProjectAbbr(name) : j['abbr'] as String,
      categoryAbbrs: {
        for (final c in cats) c: (raw[c]?.toString() ?? '').isEmpty ? suggestCategoryAbbr(c) : raw[c].toString(),
      },
      guestVisible: (j['guest_visible'] ?? false) as bool,
    );
  }
}

/// Someone a project member suggested adding. An admin approves or declines.
class ProjectInvite {
  const ProjectInvite({
    required this.id,
    required this.projectId,
    required this.email,
    required this.name,
    required this.company,
    required this.invitedBy,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String projectId;
  final String email;
  final String name;
  final String company;
  final String? invitedBy;
  final String status; // pending, approved, declined
  final DateTime createdAt;

  bool get isPending => status == 'pending';

  ProjectInvite copyWith({String? status}) => ProjectInvite(
        id: id,
        projectId: projectId,
        email: email,
        name: name,
        company: company,
        invitedBy: invitedBy,
        status: status ?? this.status,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'project_id': projectId,
        'email': email,
        'name': name,
        'company': company,
        'invited_by': invitedBy,
        'status': status,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory ProjectInvite.fromJson(Map<String, dynamic> j) => ProjectInvite(
        id: j['id'] as String,
        projectId: j['project_id'] as String,
        email: (j['email'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        company: (j['company'] ?? '') as String,
        invitedBy: j['invited_by'] as String?,
        status: (j['status'] ?? 'pending') as String,
        createdAt: _date(j['created_at']) ?? DateTime.now(),
      );
}

/// A finished voice recording waiting to be uploaded.
class NewAudio {
  const NewAudio(this.bytes, this.extension);
  final List<int> bytes;

  /// "m4a" or "wav".
  final String extension;
}

/// A message in an observation's Discussion.
class Reply {
  const Reply({
    required this.id,
    required this.noteId,
    required this.authorId,
    required this.text,
    required this.photos,
    required this.createdAt,
    this.audio = const [],
    this.editedAt,
  });

  final String id;
  final String noteId;
  final String authorId;
  final String text;
  final List<String> photos;
  final List<String> audio;
  final DateTime createdAt;
  final DateTime? editedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'note_id': noteId,
        'author_id': authorId,
        'text': text,
        'photos': photos,
        'audio': audio,
        'created_at': createdAt.toUtc().toIso8601String(),
        'edited_at': editedAt?.toUtc().toIso8601String(),
      };

  factory Reply.fromJson(Map<String, dynamic> j) => Reply(
        id: j['id'] as String,
        noteId: j['note_id'] as String,
        authorId: (j['author_id'] ?? '') as String,
        text: (j['text'] ?? '') as String,
        photos: _strings(j['photos']),
        audio: _strings(j['audio']),
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        editedAt: _date(j['edited_at']),
      );
}

/// An observation. (Called a "note" in the code and database for history's sake.)
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
    this.obsType = ObsType.general,
    this.location = '',
    this.dueAt,
    this.number,
    this.code = '',
    this.audio = const [],
    this.editedAt,
    this.replies = const [],
  });

  final String id;
  final String projectId;

  /// Observation Title.
  final String name;

  /// Description.
  final String comment;
  final String category;
  final Priority priority;
  final NoteStatus status;

  /// Reported By.
  final String issuerId;
  final List<String> assignedIds;
  final List<String> photos;

  /// Reported on.
  final DateTime createdAt;
  final DateTime updatedAt;
  final ObsType obsType;
  final String location;

  /// End of the due day. Null means no due date.
  final DateTime? dueAt;

  /// Serial number within the project and category.
  final int? number;

  /// Observation number, e.g. "NCMC-MEP-001".
  final String code;

  /// Voice messages attached to the description.
  final List<String> audio;
  final DateTime? editedAt;

  /// Discussion.
  final List<Reply> replies;

  /// An observation with nobody assigned is for everyone.
  bool get isGeneral => assignedIds.isEmpty;

  bool isOverdueAt(DateTime now) => dueAt != null && !status.isClosed && now.isAfter(dueAt!);
  bool get isOverdue => isOverdueAt(DateTime.now());

  DateTime get lastActivity {
    var last = createdAt;
    for (final r in replies) {
      if (r.createdAt.isAfter(last)) last = r.createdAt;
    }
    if (updatedAt.isAfter(last)) last = updatedAt;
    return last;
  }

  /// Number shown to people; falls back to a short id for observations made offline.
  String get displayCode => code.isNotEmpty ? code : '#${id.substring(0, 6).toUpperCase()}';

  Note copyWith({
    String? name,
    String? comment,
    String? category,
    Priority? priority,
    NoteStatus? status,
    List<String>? assignedIds,
    List<String>? photos,
    ObsType? obsType,
    String? location,
    DateTime? dueAt,
    bool clearDue = false,
    List<String>? audio,
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
        obsType: obsType ?? this.obsType,
        location: location ?? this.location,
        dueAt: clearDue ? null : (dueAt ?? this.dueAt),
        number: number,
        code: code,
        audio: audio ?? this.audio,
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
        'status': status.dbName,
        'issuer_id': issuerId,
        'assigned_ids': assignedIds,
        'photos': photos,
        'obs_type': obsType.dbName,
        'location': location,
        'due_at': dueAt?.toUtc().toIso8601String(),
        'number': number,
        'code': code,
        'audio': audio,
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
      assignedIds: _strings(j['assigned_ids']),
      photos: _strings(j['photos']),
      obsType: ObsType.fromName(j['obs_type'] as String?),
      location: (j['location'] ?? '') as String,
      dueAt: _date(j['due_at']),
      number: (j['number'] as num?)?.toInt(),
      code: (j['code'] ?? '') as String,
      audio: _strings(j['audio']),
      createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse((j['updated_at'] ?? j['created_at']) as String).toLocal(),
      editedAt: _date(j['edited_at']),
      replies: replies,
    );
  }
}

/// What the New Observation form produces. Photos are finished (marked-up) JPEG bytes.
class NoteDraft {
  NoteDraft({
    required this.name,
    required this.comment,
    required this.category,
    required this.priority,
    required this.assignedIds,
    required this.newPhotos,
    this.obsType = ObsType.general,
    this.location = '',
    this.dueAt,
    this.newAudio = const [],
  });

  final String name;
  final String comment;
  final String category;
  final Priority priority;
  final List<String> assignedIds;
  final List<List<int>> newPhotos;
  final ObsType obsType;
  final String location;
  final DateTime? dueAt;
  final List<NewAudio> newAudio;
}

/// The due moment for a picked day: the end of that day.
DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);
