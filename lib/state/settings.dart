import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The company's shared Field Observations server (Supabase). The publishable key is meant to be
/// shipped inside apps; the database's security rules (supabase/schema.sql) protect the data.
const companyServerUrl = 'https://lhffwvrebwcvwpjfhcll.supabase.co';
const companyServerKey = 'sb_publishable_NiDBo7xCIA5qNrnUEdZTbA_S_JJvVra';

/// A build can still point at another server with --dart-define (e.g. GitHub secrets).
const _envUrl = String.fromEnvironment('SUPABASE_URL');
const _envKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _builtInUrl = _envUrl == '' ? companyServerUrl : _envUrl;
const _builtInKey = _envKey == '' ? companyServerKey : _envKey;

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

  /// Font family chosen in Settings; empty means the built-in Barlow.
  String get fontChoice => _prefs.getString('font') ?? '';
  Future<void> setFontChoice(String family) => _prefs.setString('font', family);

  /// A value typed in Settings wins; otherwise the built-in company server is used.
  String get serverUrl => _nonEmpty(_prefs.getString('server_url')) ?? _builtInUrl;
  String get serverKey => _nonEmpty(_prefs.getString('server_key')) ?? _builtInKey;
  static String? _nonEmpty(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
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
