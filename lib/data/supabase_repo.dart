import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import 'repo.dart';

const _uuid = Uuid();
const _bucket = 'photos';

/// Shared server: every signed-in team member sees the same notes.
/// Database tables and security rules are in supabase/schema.sql.
class SupabaseRepo extends Repo {
  SupabaseRepo._(this._url);

  final String _url;
  final _changes = StreamController<void>.broadcast();
  final Map<String, (String, DateTime)> _signedUrls = {};
  RealtimeChannel? _channel;

  SupabaseClient get _db => Supabase.instance.client;

  static Future<SupabaseRepo> connect(String url, String anonKey) async {
    await Supabase.initialize(url: url, publishableKey: anonKey);
    return SupabaseRepo._(url);
  }

  @override
  bool get isServer => true;

  @override
  String get modeLabel => 'Shared server (${Uri.tryParse(_url)?.host ?? _url})';

  @override
  Stream<void> get changes => _changes.stream;

  void _listen() {
    _channel?.unsubscribe();
    _channel = _db
        .channel('field-notes-changes')
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
      throw RepoException(e.message);
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

  String _friendly(String m) {
    if (m.contains('row-level security')) return 'You do not have permission to do that.';
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
        final u = _db.auth.currentUser;
        if (u == null) return null;
        final me = await _profile(u.id);
        if (me != null) _listen();
        return me;
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
  Future<void> signOut() => _guard(() async {
        await _channel?.unsubscribe();
        _channel = null;
        await _db.auth.signOut();
      });

  @override
  Future<AppUser?> refreshMe() => _guard(() async {
        final u = _db.auth.currentUser;
        return u == null ? null : _profile(u.id);
      });

  @override
  Future<List<AppUser>> users() => _guard(() async {
        final rows = await _db.from('profiles').select().order('name');
        return rows.map(AppUser.fromJson).toList();
      });

  @override
  Future<void> updateUser(AppUser user) => _guard(() async {
        await _db.from('profiles').update({
          'name': user.name,
          'is_admin': user.isAdmin,
          'status': user.status.name,
        }).eq('id', user.id);
      });

  @override
  Future<List<Project>> projects() => _guard(() async {
        final rows = await _db.from('projects').select().order('name');
        return rows.map(Project.fromJson).toList();
      });

  @override
  Future<Project> createProject(String name) => _guard(() async {
        final row = await _db
            .from('projects')
            .insert({'name': name.trim(), 'categories': defaultCategories})
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
            .update({'name': project.name, 'categories': project.categories}).eq('id', project.id);
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
  Future<List<Note>> notes(String projectId) => _guard(() async {
        final rows = await _db.from('notes').select('*, replies(*)').eq('project_id', projectId);
        return rows.map(Note.fromJson).toList();
      });

  Future<String> _upload(String folder, List<int> bytes) async {
    final path = '$folder/${_uuid.v4()}.jpg';
    await _db.storage.from(_bucket).uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return 'sb:$path';
  }

  @override
  Future<Note> createNote(String projectId, NoteDraft draft) => _guard(() async {
        final id = _uuid.v4();
        final photos = <String>[];
        for (final b in draft.newPhotos) {
          photos.add(await _upload('$projectId/$id', b));
        }
        final row = await _db
            .from('notes')
            .insert({
              'id': id,
              'project_id': projectId,
              'name': draft.name,
              'comment': draft.comment,
              'category': draft.category,
              'priority': draft.priority.name,
              'status': NoteStatus.active.name,
              'issuer_id': _myId(),
              'assigned_ids': draft.assignedIds,
              'photos': photos,
            })
            .select('*, replies(*)')
            .single();
        return Note.fromJson(row);
      });

  @override
  Future<Note> updateNote(Note note, {List<List<int>> addPhotos = const []}) => _guard(() async {
        final added = <String>[];
        for (final b in addPhotos) {
          added.add(await _upload('${note.projectId}/${note.id}', b));
        }
        final row = await _db
            .from('notes')
            .update({
              'name': note.name,
              'comment': note.comment,
              'category': note.category,
              'priority': note.priority.name,
              'status': note.status.name,
              'assigned_ids': note.assignedIds,
              'photos': [...note.photos, ...added],
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
  Future<Reply> addReply(Note note, String text, List<List<int>> photos) => _guard(() async {
        final refs = <String>[];
        for (final b in photos) {
          refs.add(await _upload('${note.projectId}/${note.id}', b));
        }
        final row = await _db
            .from('replies')
            .insert({'note_id': note.id, 'author_id': _myId(), 'text': text, 'photos': refs})
            .select()
            .single();
        return Reply.fromJson(row);
      });

  @override
  Future<void> deleteReply(Reply reply) => _guard(() async {
        await _db.from('replies').delete().eq('id', reply.id);
      });

  @override
  Future<ImageProvider> image(String ref) async {
    final path = ref.startsWith('sb:') ? ref.substring(3) : ref;
    final cached = _signedUrls[path];
    if (cached != null && cached.$2.isAfter(DateTime.now())) return NetworkImage(cached.$1);
    final url = await _guard(() => _db.storage.from(_bucket).createSignedUrl(path, 60 * 60 * 24));
    _signedUrls[path] = (url, DateTime.now().add(const Duration(hours: 23)));
    return NetworkImage(url);
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _changes.close();
  }
}
