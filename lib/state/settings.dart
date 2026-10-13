import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Server details can be built into the installer (GitHub secrets) or typed in Settings.
const _builtInUrl = String.fromEnvironment('SUPABASE_URL');
const _builtInKey = String.fromEnvironment('SUPABASE_ANON_KEY');

class Settings {
  Settings._(this._prefs);
  final SharedPreferences _prefs;

  static Future<Settings> load() async => Settings._(await SharedPreferences.getInstance());

  ThemeMode get themeMode => switch (_prefs.getString('theme')) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
  Future<void> setThemeMode(ThemeMode m) => _prefs.setString('theme', m.name);

  String get serverUrl => _prefs.getString('server_url') ?? _builtInUrl;
  String get serverKey => _prefs.getString('server_key') ?? _builtInKey;
  bool get hasServer => serverUrl.trim().isNotEmpty && serverKey.trim().isNotEmpty;

  /// Empty values switch back to "this computer only".
  Future<void> setServer(String url, String key) async {
    await _prefs.setString('server_url', url.trim());
    await _prefs.setString('server_key', key.trim());
  }

  String? get lastProjectId => _prefs.getString('last_project');
  Future<void> setLastProjectId(String id) => _prefs.setString('last_project', id);

  /// noteId -> when the current user last opened it (used for the bell).
  Map<String, DateTime> seen(String userId) {
    final raw = _prefs.getString('seen_$userId');
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, DateTime.parse(v as String)));
    } catch (_) {
      return {};
    }
  }

  Future<void> setSeen(String userId, Map<String, DateTime> seen) => _prefs.setString(
        'seen_$userId',
        jsonEncode(seen.map((k, v) => MapEntry(k, v.toIso8601String()))),
      );
}
