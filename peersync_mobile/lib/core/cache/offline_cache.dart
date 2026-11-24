import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A cached API response plus the moment it was stored.
class CacheEntry {
  final dynamic data;
  final DateTime storedAt;

  const CacheEntry({required this.data, required this.storedAt});

  /// Age of the entry at [now] (defaults to the current time).
  Duration age({DateTime? now}) => (now ?? DateTime.now()).difference(storedAt);

  /// Whether the entry is older than the configured time-to-live.
  bool isExpired({DateTime? now, Duration ttl = OfflineCache.ttl}) =>
      age(now: now) > ttl;

  Map<String, dynamic> toJson() => {
        'storedAt': storedAt.toUtc().toIso8601String(),
        'data': data,
      };

  static CacheEntry? fromJson(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! Map<String, dynamic>) return null;

      final storedAt = DateTime.tryParse(
        decoded['storedAt']?.toString() ?? '',
      );

      if (storedAt == null) return null;

      return CacheEntry(data: decoded['data'], storedAt: storedAt.toLocal());
    } catch (_) {
      // A corrupt entry must never break the app - treat it as a miss.
      return null;
    }
  }
}

/// Persists read-only API responses so PeerSync keeps working without a
/// connection.
///
/// Entries live in [SharedPreferences], which is backed by `localStorage` on
/// web and by platform preferences on mobile, so the cache survives a full
/// browser refresh or an app restart. Every entry is scoped to the signed-in
/// user's UID and expires after [ttl] (72 hours), which keeps stale academic
/// data from being shown indefinitely and stops one account's data from being
/// read by another account on a shared device.
class OfflineCache {
  const OfflineCache._();

  /// How long a cached response stays usable: three days.
  static const Duration ttl = Duration(days: 3);

  /// Bumped whenever the stored shape changes, so old entries are ignored
  /// instead of being mis-parsed.
  static const String _version = 'v1';
  static const String _prefix = 'peersync.cache.$_version';

  static SharedPreferences? _preferences;

  static Future<SharedPreferences> _prefs() async =>
      _preferences ??= await SharedPreferences.getInstance();

  /// Namespaces a cache key by user so accounts never share cached data.
  static String keyFor(String cacheKey, {String? userId}) =>
      '$_prefix.${userId ?? 'anonymous'}.$cacheKey';

  /// Stores [data] under [cacheKey]. Failures are swallowed: a full or
  /// unavailable store must not break a successful network request.
  static Future<void> write(
    String cacheKey,
    dynamic data, {
    String? userId,
  }) async {
    try {
      final entry = CacheEntry(data: data, storedAt: DateTime.now());
      final preferences = await _prefs();
      await preferences.setString(
        keyFor(cacheKey, userId: userId),
        jsonEncode(entry.toJson()),
      );
    } catch (_) {
      // Best-effort only.
    }
  }

  /// Reads [cacheKey] if it exists and has not exceeded [ttl].
  ///
  /// Expired entries are deleted on read so the store does not grow forever.
  static Future<CacheEntry?> read(
    String cacheKey, {
    String? userId,
    Duration? maxAge,
  }) async {
    final key = keyFor(cacheKey, userId: userId);

    try {
      final preferences = await _prefs();
      final entry = CacheEntry.fromJson(preferences.getString(key));

      if (entry == null) return null;

      if (entry.isExpired(ttl: maxAge ?? ttl)) {
        await preferences.remove(key);
        return null;
      }

      return entry;
    } catch (_) {
      return null;
    }
  }

  /// Removes every cached response for one user. Called on sign-out so a
  /// shared device does not keep another student's projects on disk.
  static Future<void> clearForUser(String? userId) async {
    try {
      final preferences = await _prefs();
      final marker = keyFor('', userId: userId);

      for (final key in preferences.getKeys().toList()) {
        if (key.startsWith(marker)) {
          await preferences.remove(key);
        }
      }
    } catch (_) {
      // Best-effort only.
    }
  }

  /// Removes every PeerSync cache entry, regardless of user.
  static Future<void> clearAll() async {
    try {
      final preferences = await _prefs();

      for (final key in preferences.getKeys().toList()) {
        if (key.startsWith(_prefix)) {
          await preferences.remove(key);
        }
      }
    } catch (_) {
      // Best-effort only.
    }
  }

  /// Drops entries that have passed [ttl]. Safe to call on app start.
  static Future<int> pruneExpired({Duration? maxAge}) async {
    var removed = 0;

    try {
      final preferences = await _prefs();
      final limit = maxAge ?? ttl;

      for (final key in preferences.getKeys().toList()) {
        if (!key.startsWith(_prefix)) continue;

        final entry = CacheEntry.fromJson(preferences.getString(key));

        if (entry == null || entry.isExpired(ttl: limit)) {
          await preferences.remove(key);
          removed++;
        }
      }
    } catch (_) {
      // Best-effort only.
    }

    return removed;
  }
}
