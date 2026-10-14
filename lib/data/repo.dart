import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models.dart';

/// Friendly error shown to the user as-is.
class RepoException implements Exception {
  RepoException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Everything the app needs from storage. Two implementations:
///  * [LocalRepo]    - observations and photos saved on this computer (no server yet).
///  * [SupabaseRepo] - shared server so the whole team sees the same observations.
abstract class Repo {
  /// True when connected to the shared server.
  bool get isServer;

  /// Short description shown in Settings ("This computer only" / server host).
  String get modeLabel;

  /// Fires when data may have changed somewhere else (another user).
  Stream<void> get changes;

  /// Fires when someone signs in without the sign-in screen (e.g. the emailed link).
  Stream<void> get signedIn => const Stream.empty();

  // ---- Accounts ----
  Future<AppUser?> restoreSession();
  Future<AppUser> signIn({required String email, required String password});
  Future<AppUser> register({required String name, required String email, required String password});
  Future<void> signOut();
  Future<AppUser?> refreshMe();

  /// True when people sign in with a one-time code sent to their email.
  bool get usesEmailCodes => false;

  /// Emails a one-time sign-in code. Creates the account on first use.
  Future<void> sendCode(String email) async => throw RepoException('Email codes need the shared server.');

  /// Checks the emailed code and signs in.
  Future<AppUser> verifyCode(String email, String code) async =>
      throw RepoException('Email codes need the shared server.');

  /// Signs in from the link in the sign-in email, pasted into the app.
  Future<AppUser> verifyLink(String link) async => throw RepoException('Email links need the shared server.');

  /// Lets people set their own display name and company.
  Future<AppUser> updateMyProfile({required String name, required String company});

  /// Everyone the current user may see. Admins also see pending requests.
  Future<List<AppUser>> users();

  /// Admin only: approve / remove / make admin / rename / company.
  Future<void> updateUser(AppUser user);

  // ---- Projects ----
  Future<List<Project>> projects();
  /// Admin only. [draft] carries the name and the abbreviations (its id is ignored).
  Future<Project> createProject(Project draft);
  Future<void> updateProject(Project project);

  /// projectId -> member user ids.
  Future<Map<String, Set<String>>> projectMembers();
  Future<void> setProjectMember(String projectId, String userId, bool member);

  /// Member suggestions waiting for (or decided by) an admin.
  Future<List<ProjectInvite>> invites();

  /// A project member suggests adding someone; an admin must approve.
  Future<void> suggestMember(String projectId, {required String email, required String name, required String company});

  /// Admin: approve (the person is added to the project) or decline a suggestion.
  Future<void> approveInvite(ProjectInvite invite);
  Future<void> declineInvite(ProjectInvite invite);

  // ---- Notes ----
  Future<List<Note>> notes(String projectId);
  Future<Note> createNote(String projectId, NoteDraft draft);

  /// Saves edited fields of [note]. [addPhotos] are new JPEG images and [addAudio]
  /// new voice messages to append.
  Future<Note> updateNote(Note note, {List<List<int>> addPhotos = const [], List<NewAudio> addAudio = const []});
  Future<void> deleteNote(Note note);
  Future<Reply> addReply(Note note, String text, List<List<int>> photos, {List<NewAudio> audio = const []});
  Future<void> deleteReply(Reply reply);

  /// Turns a stored photo reference into something Flutter can draw.
  Future<ImageProvider> image(String ref);

  /// Where a stored voice message can be played from (a file or a web address).
  Future<Uri> audioUri(String ref);

  void dispose() {}
}
