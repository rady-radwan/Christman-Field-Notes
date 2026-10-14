import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import 'repo.dart';

const _uuid = Uuid();
const _bucket = 'photos';

/// Clicking the link in the sign-in email opens the app through this address.
/// The Windows installer registers it; it must also be listed under
/// Supabase > Authentication > URL Configuration > Redirect URLs.
const signInRedirect = 'christman-fieldnotes://login-callback';

/// Shared server: every project member sees the same observations.
/// Database tables and security rules are in supabase/schema.sql.
class SupabaseRepo extends Repo {
  SupabaseRepo._(this._url);

  final String _url;
  final _changes = StreamController<void>.broadcast();
  final _signedIn = StreamController<void>.broadcast();
  StreamSubscription<AuthState>? _authSub;
  final Map<String, (String, DateTime)> _signedUrls = {};
  RealtimeChannel? _channel;

  SupabaseClient get _db => Supabase.instance.client;

  static Future<SupabaseRepo> connect(String url, String anonKey) async {
    await Supabase.initialize(
      url: url,
      publishableKey: anonKey,
      // Implicit flow: the emailed link holds a token the app can check when pasted.
      authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
    final repo = SupabaseRepo._(url);
    // Sign-ins that happen outside the sign-in screen (clicking the emailed link).
    repo._authSub = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedIn) repo._signedIn.add(null);
    }, onError: (_) {});
    return repo;
  }

  @override
  bool get isServer => true;

  @override
  String get modeLabel => 'Shared server (${Uri.tryParse(_url)?.host ?? _url})';

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Stream<void> get signedIn => _signedIn.stream;

  void _listen() {
    _channel?.unsubscribe();
    _channel = _db
        .channel('field-observations-changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          callback: (_) => _changes.add(null),
        )
        .subscribe();
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on AuthException catch (e) {
      throw RepoException(_friendlyAuth(e.message));
    } on PostgrestException catch (e) {
      throw RepoException(_friendly(e.message));
    } on StorageException catch (e) {
      throw RepoException('Photo upload failed: ${e.message}');
    } on RepoException {
      rethrow;
    } catch (e) {
      throw RepoException('Could not reach the server. Check the internet connection and try again.');
    }
  }

  String _friendlyAuth(String m) {
    final l = m.toLowerCase();
    if (l.contains('not authorized')) {
      return "This email can't receive sign-in codes yet. The admin needs to finish the email setup on the server.";
    }
    if (l.contains('rate limit') || l.contains('security purposes')) {
      return 'Too many codes were requested. Please wait a few minutes and try again.';
    }
    if (l.contains('expired') || l.contains('invalid')) {
      return 'That code is wrong or has expired. Check the newest email, or send a new code.';
    }
    return m;
  }

  String _friendly(String m) {
    if (m.contains('row-level security')) return 'You do not have permission to do that.';
    if (m.contains('does not exist') || m.contains('schema cache')) {
      return 'The server database is not set up yet. The admin needs to run the setup script (schema.sql) in Supabase.';
    }
    return m;
  }

  String _myId() {
    final id = _db.auth.currentUser?.id;
    if (id == null) throw RepoException('Please sign in again.');
    return id;
  }

  Future<AppUser?> _profile(String id) async {
    final row = await _db.from('profiles').select().eq('id', id).maybeSingle();
    return row == null ? null : AppUser.fromJson(row);
  }

  @override
  Future<AppUser?> restoreSession() => _guard(() async {
        _listen(); // live updates for guests too
        final u = _db.auth.currentUser;
        if (u == null) return null;
        return _profile(u.id);
      });

  @override
  Future<AppUser> signIn({required String email, required String password}) => _guard(() async {
        final res = await _db.auth.signInWithPassword(email: email.trim(), password: password);
        final me = await _profile(res.user!.id);
        if (me == null) throw RepoException('Your profile was not found. Ask an admin for help.');
        if (me.status == MemberStatus.removed) {
          await _db.auth.signOut();
          throw RepoException('This account was removed by an admin.');
        }
        _listen();
        return me;
      });

  @override
  Future<AppUser> register({required String name, required String email, required String password}) =>
      _guard(() async {
        final res = await _db.auth.signUp(email: email.trim(), password: password, data: {'name': name.trim()});
        if (res.session == null) {
          throw RepoException('Account created. Check your email to confirm it, then sign in.');
        }
        final me = await _profile(res.user!.id);
        if (me == null) throw RepoException('Account created, but the profile is not ready yet. Try signing in.');
        _listen();
        return me;
      });

  @override
  bool get usesEmailCodes => true;

  @override
  Future<void> sendCode(String email) => _guard(() async {
        await _db.auth.signInWithOtp(
          email: email.trim().toLowerCase(),
          shouldCreateUser: true,
          emailRedirectTo: signInRedirect,
        );
      });

  @override
  Future<AppUser> verifyCode(String email, String code) => _guard(() async {
        final res = await _db.auth.verifyOTP(
          email: email.trim().toLowerCase(),
          token: code.replaceAll(RegExp(r'\s'), ''),
          type: OtpType.email,
        );
        final id = res.user?.id ?? _db.auth.currentUser?.id;
        if (id == null) throw RepoException('That code did not work. Please send a new one.');
        var me = await _profile(id);
        if (me == null) {
          // The profile is created by a database trigger; give it a moment.
          await Future<void>.delayed(const Duration(seconds: 1));
          me = await _profile(id);
        }
        if (me == null) {
          throw RepoException('Signed in, but your profile was not found. Ask the admin to check the server setup.');
        }
        if (me.status == MemberStatus.removed) {
          await _db.auth.signOut();
          throw RepoException('This account was removed by an admin.');
        }
        _listen();
        return me;
      });

  /// Signs in from the sign-in link copied out of the email (instead of clicking it).
  @override
  Future<AppUser> verifyLink(String pasted) => _guard(() async {
        final link = _unwrapLink(pasted.trim());
        final uri = Uri.tryParse(link);
        final hash = uri?.queryParameters['token'] ?? uri?.queryParameters['token_hash'];
        if (uri == null || hash == null || hash.isEmpty) {
          throw RepoException('That does not look like the sign-in link. Copy the whole link from the email.');
        }
        final type = switch (uri.queryParameters['type']) {
          'signup' => OtpType.signup,
          'invite' => OtpType.invite,
          'recovery' => OtpType.recovery,
          'email' => OtpType.email,
          _ => OtpType.magiclink,
        };
        final res = await _db.auth.verifyOTP(tokenHash: hash, type: type);
        final id = res.user?.id ?? _db.auth.currentUser?.id;
        if (id == null) throw RepoException('That link did not work. Please send a new code.');
        return _finishSignIn(id);
      });

  /// Outlook "Safe Links" wrap the real link; unwrap it.
  String _unwrapLink(String s) {
    var link = s;
    for (var i = 0; i < 3; i++) {
      final u = Uri.tryParse(link);
      final inner = u?.queryParameters['url'];
      if (u == null || inner == null || !u.host.contains('safelinks')) break;
      link = inner;
    }
    return link;
  }

  Future<AppUser> _finishSignIn(String id) async {
    var me = await _profile(id);
    if (me == null) {
      await Future<void>.delayed(const Duration(seconds: 1));
      me = await _profile(id);
    }
    if (me == null) {
      throw RepoException('Signed in, but your profile was not found. Ask the admin to check the server setup.');
    }
    if (me.status == MemberStatus.removed) {
      await _db.auth.signOut();
      throw RepoException('This account was removed by an admin.');
    }
    _listen();
    return me;
  }

  @override
  Future<AppUser> updateMyProfile({required String name, required String company}) => _guard(() async {
        final row = await _db
            .from('profiles')
            .update({'name': name.trim(), 'company': company.trim()})
            .eq('id', _myId())
            .select()
            .single();
        return AppUser.fromJson(row);
      });

  @override
  Future<void> signOut() => _guard(() async {
        await _db.auth.signOut();
        _listen(); // keep live updates as a guest
      });

  @override
  Future<AppUser?> refreshMe() => _guard(() async {
        final u = _db.auth.currentUser;
        return u == null ? null : _profile(u.id);
      });

  @override
  Future<List<AppUser>> users() => _guard(() async {
        // Guests may read names but not email addresses (see column grants in schema.sql).
        final cols = _db.auth.currentUser == null ? 'id,name,is_admin,status,company' : '*';
        final rows = await _db.from('profiles').select(cols).order('name');
        return rows.map(AppUser.fromJson).toList();
      });

  @override
  Future<void> updateUser(AppUser user) => _guard(() async {
        await _db.from('profiles').update({
          'name': user.name,
          'is_admin': user.isAdmin,
          'status': user.status.name,
          'company': user.company,
        }).eq('id', user.id);
      });

  @override
  Future<List<Project>> projects() => _guard(() async {
        final rows = await _db.from('projects').select().order('name');
        return rows.map(Project.fromJson).toList();
      });

  @override
  Future<Project> createProject(Project draft) => _guard(() async {
        final row = await _db
            .from('projects')
            .insert({
              'name': draft.name.trim(),
              'categories': draft.categories,
              'abbr': draft.abbr.trim().toUpperCase(),
              'category_abbrs': draft.categoryAbbrs,
              'guest_visible': draft.guestVisible,
            })
            .select()
            .single();
        final pr = Project.fromJson(row);
        await _db.from('project_members').insert({'project_id': pr.id, 'user_id': _myId()});
        return pr;
      });

  @override
  Future<void> updateProject(Project project) => _guard(() async {
        await _db
            .from('projects')
            .update({
              'name': project.name,
              'categories': project.categories,
              'abbr': project.abbr.trim().toUpperCase(),
              'category_abbrs': project.categoryAbbrs,
              'guest_visible': project.guestVisible,
            }).eq('id', project.id);
      });

  @override
  Future<Map<String, Set<String>>> projectMembers() => _guard(() async {
        final rows = await _db.from('project_members').select();
        final map = <String, Set<String>>{};
        for (final r in rows) {
          map.putIfAbsent(r['project_id'] as String, () => {}).add(r['user_id'] as String);
        }
        return map;
      });

  @override
  Future<void> setProjectMember(String projectId, String userId, bool member) => _guard(() async {
        if (member) {
          await _db.from('project_members').upsert({'project_id': projectId, 'user_id': userId});
        } else {
          await _db.from('project_members').delete().eq('project_id', projectId).eq('user_id', userId);
        }
      });

  @override
  Future<List<ProjectInvite>> invites() => _guard(() async {
        if (_db.auth.currentUser == null) return <ProjectInvite>[];
        final rows = await _db.from('project_invites').select().order('created_at', ascending: false);
        return rows.map(ProjectInvite.fromJson).toList();
      });

  @override
  Future<void> suggestMember(String projectId, {required String email, required String name, required String company}) =>
      _guard(() async {
        try {
          await _db.from('project_invites').insert({
            'project_id': projectId,
            'email': email.trim().toLowerCase(),
            'name': name.trim(),
            'company': company.trim(),
            'invited_by': _myId(),
          });
        } on PostgrestException catch (e) {
          if (e.code == '23505') throw RepoException('That person is already waiting for approval on this project.');
          rethrow;
        }
      });

  @override
  Future<void> approveInvite(ProjectInvite invite) => _guard(() async {
        await _db.rpc('approve_invite', params: {'invite_id': invite.id});
      });

  @override
  Future<void> declineInvite(ProjectInvite invite) => _guard(() async {
        await _db.from('project_invites').update({'status': 'declined'}).eq('id', invite.id);
      });

  @override
  Future<List<Note>> notes(String projectId) => _guard(() async {
        final rows = await _db.from('notes').select('*, replies(*)').eq('project_id', projectId);
        return rows.map(Note.fromJson).toList();
      });

  Future<String> _upload(String folder, List<int> bytes, {String ext = 'jpg'}) async {
    final path = '$folder/${_uuid.v4()}.$ext';
    final type = switch (ext) { 'm4a' => 'audio/mp4', 'wav' => 'audio/wav', _ => 'image/jpeg' };
    await _db.storage.from(_bucket).uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: type),
        );
    return 'sb:$path';
  }

  Future<List<String>> _uploadAudio(String folder, List<NewAudio> clips) async =>
      [for (final a in clips) await _upload(folder, a.bytes, ext: a.extension)];

  @override
  Future<Note> createNote(String projectId, NoteDraft draft) => _guard(() async {
        final id = _uuid.v4();
        final photos = <String>[];
        for (final b in draft.newPhotos) {
          photos.add(await _upload('$projectId/$id', b));
        }
        final audio = await _uploadAudio('$projectId/$id', draft.newAudio);
        final row = await _db
            .from('notes')
            .insert({
              'id': id,
              'project_id': projectId,
              'name': draft.name,
              'comment': draft.comment,
              'category': draft.category,
              'priority': draft.priority.name,
              'status': NoteStatus.open.dbName,
              'issuer_id': _myId(),
              'assigned_ids': draft.assignedIds,
              'photos': photos,
              'obs_type': draft.obsType.dbName,
              'location': draft.location.trim(),
              'due_at': draft.dueAt?.toUtc().toIso8601String(),
              'audio': audio,
            })
            .select('*, replies(*)')
            .single();
        return Note.fromJson(row);
      });

  @override
  Future<Note> updateNote(Note note, {List<List<int>> addPhotos = const [], List<NewAudio> addAudio = const []}) =>
      _guard(() async {
        final added = <String>[];
        for (final b in addPhotos) {
          added.add(await _upload('${note.projectId}/${note.id}', b));
        }
        final addedAudio = await _uploadAudio('${note.projectId}/${note.id}', addAudio);
        final row = await _db
            .from('notes')
            .update({
              'name': note.name,
              'comment': note.comment,
              'category': note.category,
              'priority': note.priority.name,
              'status': note.status.dbName,
              'assigned_ids': note.assignedIds,
              'photos': [...note.photos, ...added],
              'obs_type': note.obsType.dbName,
              'location': note.location.trim(),
              'due_at': note.dueAt?.toUtc().toIso8601String(),
              'audio': [...note.audio, ...addedAudio],
              'edited_at': note.editedAt?.toUtc().toIso8601String(),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', note.id)
            .select('*, replies(*)')
            .single();
        return Note.fromJson(row);
      });

  @override
  Future<void> deleteNote(Note note) => _guard(() async {
        await _db.from('notes').delete().eq('id', note.id);
      });

  @override
  Future<Reply> addReply(Note note, String text, List<List<int>> photos, {List<NewAudio> audio = const []}) =>
      _guard(() async {
        final refs = <String>[];
        for (final b in photos) {
          refs.add(await _upload('${note.projectId}/${note.id}', b));
        }
        final clips = await _uploadAudio('${note.projectId}/${note.id}', audio);
        final row = await _db
            .from('replies')
            .insert({'note_id': note.id, 'author_id': _myId(), 'text': text, 'photos': refs, 'audio': clips})
            .select()
            .single();
        return Reply.fromJson(row);
      });

  @override
  Future<void> deleteReply(Reply reply) => _guard(() async {
        await _db.from('replies').delete().eq('id', reply.id);
      });

  Future<String> _signedUrl(String ref) async {
    final path = ref.startsWith('sb:') ? ref.substring(3) : ref;
    final cached = _signedUrls[path];
    if (cached != null && cached.$2.isAfter(DateTime.now())) return cached.$1;
    final url = await _guard(() => _db.storage.from(_bucket).createSignedUrl(path, 60 * 60 * 24));
    _signedUrls[path] = (url, DateTime.now().add(const Duration(hours: 23)));
    return url;
  }

  @override
  Future<ImageProvider> image(String ref) async => NetworkImage(await _signedUrl(ref));

  @override
  Future<Uri> audioUri(String ref) async => Uri.parse(await _signedUrl(ref));

  @override
  void dispose() {
    _authSub?.cancel();
    _signedIn.close();
    _channel?.unsubscribe();
    _changes.close();
  }
}
