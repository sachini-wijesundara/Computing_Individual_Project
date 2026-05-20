import 'dart:convert';

import 'package:flutter/services.dart';

import 'named_color_dictionary.dart';
import 'seed_products.dart';

/// Maps shade **names** or **hex codes** → hex (catalogue + 30k names + CSS).
class AdminShadeColorRegistry {
  AdminShadeColorRegistry._();

  static const String _extendedAsset = 'assets/data/color_name_list.json';

  static String _norm(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String _compact(String name) => _norm(name).replaceAll(' ', '');

  static List<String> _tokens(String query) =>
      _norm(query).split(' ').where((t) => t.length >= 2).toList();

  /// Lipstick / makeup names (not always in the 30k paint-colour list).
  static const Map<String, String> _makeupAliases = {
    'classic deep berry': '#5C1A3D',
    'deep berry': '#5C1A3D',
    'deep wine berry': '#5C1A3D',
    'berry bliss': '#8B2252',
    'berry': '#8B2252',
    'deep wine': '#722F37',
    'wine berry': '#722F37',
    'cool berry': '#9B4D6F',
    'warm coral': '#E8735A',
    'soft rose': '#D4617A',
    'rose pink': '#D4617A',
    'nude blush': '#EBB4A9',
    'nude': '#EBB4A9',
    'nude pink': '#EBB4A9',
    'classic red': '#C0392B',
    'true red': '#E32636',
    'ruby red': '#9B111E',
    'ruby': '#9B111E',
    'wine': '#722F37',
    'mauve': '#B89898',
    'plum': '#6A2C5E',
    'coral': '#FF7F50',
    'espresso': '#3D2314',
  };

  static Map<String, String>? _lookupCache;
  static List<Map<String, String>>? _extendedList;
  static bool _extendedLoaded = false;
  static Future<void>? _loadFuture;

  static Future<void> ensureLoaded() {
    _loadFuture ??= _loadExtended();
    return _loadFuture!;
  }

  static bool get isExtendedLoaded => _extendedLoaded;

  static Future<void> _loadExtended() async {
    if (_extendedLoaded) return;
    try {
      final raw = await rootBundle.loadString(_extendedAsset);
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _extendedList = decoded
            .whereType<Map>()
            .map(
              (m) => {
                'name': (m['name'] ?? '').toString().trim(),
                'hex': (m['hex'] ?? '').toString().trim(),
              },
            )
            .where((m) => m['name']!.isNotEmpty && m['hex']!.isNotEmpty)
            .toList();
      }
    } catch (_) {
      _extendedList = [];
    }
    _lookupCache = null;
    _extendedLoaded = true;
  }

  static Map<String, String> get _lookup {
    if (_lookupCache != null) return _lookupCache!;
    final map = <String, String>{};

    void put(String name, String hex) {
      final h = _normalizeHex(hex);
      if (h == null) return;
      final c = _compact(name);
      if (c.isNotEmpty) map[c] = h;
      final n = _norm(name);
      if (n.isNotEmpty) map[n] = h;
    }

    for (final e in kNamedColorDictionary.entries) {
      put(e.key, e.value);
    }
    for (final p in catalogShadePresets) {
      put(p['name'] ?? '', p['hex'] ?? '');
    }
    for (final e in _makeupAliases.entries) {
      put(e.key, e.value);
    }
    if (_extendedList != null) {
      for (final p in _extendedList!) {
        put(p['name'] ?? '', p['hex'] ?? '');
      }
    }

    _lookupCache = map;
    return map;
  }

  static String? _normalizeHex(String raw) {
    var s = raw.trim().toUpperCase();
    if (s.isEmpty) return null;
    if (!s.startsWith('#')) s = '#$s';
    if (!RegExp(r'^#[0-9A-F]{6}$').hasMatch(s)) return null;
    return s;
  }

  static String? parseHexInput(String input) {
    var s = input.trim();
    if (s.startsWith('0x') || s.startsWith('0X')) {
      s = s.substring(2);
    }
    return _normalizeHex(s);
  }

  static int get namedColorCount => _lookup.length;

  static List<Map<String, String>> get allPresets => catalogShadePresets;

  /// Match score (higher = better). `0` = no match.
  static int _matchScore(String name, String query) {
    final n = _norm(name);
    final c = _compact(name);
    final qn = _norm(query);
    final qc = _compact(query);
    if (qn.isEmpty) return 1;
    if (n == qn || c == qc) return 100;
    if (n.startsWith(qn) || c.startsWith(qc)) return 80;
    if (n.contains(qn) || c.contains(qc)) return 60;

    final tokens = _tokens(query);
    if (tokens.isEmpty) return 0;
    if (tokens.every((t) => n.contains(t))) return 50 + tokens.length;
    return 0;
  }

  /// Search: **product catalogue first**, then makeup aliases, then 30k library.
  static List<Map<String, String>> searchColors(
    String query, {
    int limit = 24,
  }) {
    final q = query.trim();
    final ranked = <({int score, String name, String hex})>[];
    final seenHex = <String>{};

    void addResult(String name, String hex, int score) {
      final h = _normalizeHex(hex);
      if (h == null || seenHex.contains(h) || score <= 0) return;
      seenHex.add(h);
      ranked.add((score: score, name: name, hex: h));
    }

    if (q.isEmpty) {
      for (final p in catalogShadePresets.take(limit)) {
        addResult(p['name'] ?? '', p['hex'] ?? '', 1);
      }
      return ranked
          .map((r) => {'name': r.name, 'hex': r.hex})
          .toList();
    }

    for (final p in catalogShadePresets) {
      final name = p['name'] ?? '';
      addResult(name, p['hex'] ?? '', _matchScore(name, q));
    }

    for (final e in _makeupAliases.entries) {
      addResult(e.key, e.value, _matchScore(e.key, q));
    }

    if (_extendedList != null) {
      for (final p in _extendedList!) {
        final name = p['name'] ?? '';
        addResult(name, p['hex'] ?? '', _matchScore(name, q));
      }
    }

    for (final e in kNamedColorDictionary.entries) {
      addResult(e.key, e.value, _matchScore(e.key, q));
    }

    ranked.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.name.length.compareTo(b.name.length);
    });
    return ranked
        .take(limit)
        .map((r) => {'name': r.name, 'hex': r.hex})
        .toList();
  }

  static String? hexForShadeName(String shadeName) {
    final trimmed = shadeName.trim();
    if (trimmed.isEmpty) return null;

    final asHex = parseHexInput(trimmed);
    if (asHex != null) return asHex;

    final key = _norm(trimmed);
    if (key.length < 2) return null;

    final compact = _compact(trimmed);
    final exact = _lookup[compact] ?? _lookup[key];
    if (exact != null) return exact;

    if (_makeupAliases.containsKey(key)) {
      return _makeupAliases[key]!.toUpperCase();
    }

    String? bestHex;
    var bestScore = 0;

    void consider(String name, String hex) {
      final score = _matchScore(name, trimmed);
      if (score >= 50 && score > bestScore) {
        final h = _normalizeHex(hex);
        if (h != null) {
          bestScore = score;
          bestHex = h;
        }
      }
    }

    for (final p in catalogShadePresets) {
      consider(p['name'] ?? '', p['hex'] ?? '');
    }
    for (final e in _makeupAliases.entries) {
      consider(e.key, e.value);
    }
    if (_extendedList != null) {
      for (final p in _extendedList!) {
        consider(p['name'] ?? '', p['hex'] ?? '');
      }
    }
    if (bestHex != null) return bestHex;

    if (compact.length >= 4) {
      for (final entry in _lookup.entries) {
        if (entry.key.startsWith(compact)) {
          return entry.value;
        }
      }
    }

    return null;
  }

  static List<String> get presetNames {
    final names = <String>{};
    for (final p in catalogShadePresets) {
      final n = (p['name'] ?? '').trim();
      if (n.isNotEmpty) names.add(n);
    }
    for (final k in _makeupAliases.keys) {
      names.add(k);
    }
    final list = names.toList()..sort();
    return list;
  }
}
