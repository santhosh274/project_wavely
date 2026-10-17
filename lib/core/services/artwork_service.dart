import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../models/song_model.dart';

/// Loads album artwork for tracks, on demand, with a small in-memory cache.
///
/// Artwork is deliberately not fetched while scanning the library. The media
/// store on a real device holds thousands of tracks, and asking for an embedded
/// image for every one of them during the scan turns a fast query into a slow
/// one. Instead the artwork is resolved when a track is actually shown, and
/// cached so scrolling back over a list does not re-query.
///
/// A device that simply has no artwork for a track returns null. That is a real
/// answer, not an error, so callers fall back to their own placeholder rather
/// than being told the load failed.
class ArtworkService {
  ArtworkService({OnAudioQuery? audioQuery, Duration? queryTimeout})
    : _audioQuery = audioQuery ?? OnAudioQuery(),
      _queryTimeout = queryTimeout ?? _defaultTimeout;

  final OnAudioQuery _audioQuery;

  /// How long to wait for the media store before giving up on a cover.
  ///
  /// The query crosses a platform channel, and a channel that never answers --
  /// a missing plugin, a wedged media provider -- would otherwise leave every
  /// artwork widget stuck on its placeholder forever. Treating a timeout as "no
  /// artwork" matches what a device genuinely without a cover reports, so the
  /// UI lands in the same honest state either way.
  final Duration _queryTimeout;

  static const Duration _defaultTimeout = Duration(seconds: 5);

  /// Enough to cover the visible rows of a couple of screens; artwork is small
  /// but a few hundred decoded thumbnails is already tens of megabytes.
  static const int _maxEntries = 128;

  /// Dart's default map implementation preserves insertion order, so the first
  /// key is always the oldest. [ArtworkService._evictIfNeeded] depends on that to
  /// drop the entry that has been unused for the longest.
  final _cache = <int, Uint8List?>{};
  final _inFlight = <int, Future<Uint8List?>>{};

  /// Whether [songId]'s album has already been looked up, successfully or not.
  ///
  /// Lets callers skip the loading state for the negative results instead of
  /// flashing a spinner on every track that has no cover.
  bool isCached(WavelySong song) =>
      song.albumId != null && _cache.containsKey(song.albumId!);

  /// The bytes already held for [song]'s album, available without a future.
  ///
  /// A cache hit has to be readable on the very frame a widget first builds:
  /// changing track re-points the cover widgets at a new song, and going
  /// through [artworkFor] -- even when it resolves from the cache -- still
  /// costs a microtask, so the cover was replaced by the placeholder for a
  /// frame on every track change. Reading synchronously lets that frame paint
  /// the real cover instead.
  ///
  /// Null means "nothing cached", which [isCached] distinguishes from "cached
  /// and the device has no cover".
  Uint8List? cachedArtworkFor(WavelySong song) {
    final albumId = song.albumId;
    if (albumId == null) return null;
    return _cache[albumId];
  }

  /// The artwork for [song], or null when the device has none for it.
  ///
  /// Cached on the album rather than the track, because every song on an album
  /// resolves to the same image and a device-wide cache keyed per song would
  /// hold one copy of the same cover for every track on it.
  Future<Uint8List?> artworkFor(WavelySong song) {
    final albumId = song.albumId;
    if (albumId == null) return Future.value(null);

    if (_cache.containsKey(albumId)) return Future.value(_cache[albumId]);

    final existing = _inFlight[albumId];
    if (existing != null) return existing;

    // One query per album is shared between every caller that asks while it is
    // still running, and the entry is dropped once it settles.
    //
    // The bookkeeping closure deliberately returns nothing. Returning the stored
    // future instead -- `() => _inFlight.remove(albumId)` -- hands `whenComplete`
    // the very future it is waiting on, because the map holds the request rather
    // than the raw load, so the request can never complete and every caller waits
    // for cover that will never arrive.
    final request = _load(albumId);
    _inFlight[albumId] = request;
    request.whenComplete(() {
      _inFlight.remove(albumId);
    }).ignore();

    return request;
  }

  Future<Uint8List?> _load(int albumId) async {
    Uint8List? bytes;
    try {
      bytes = await _audioQuery
          .queryArtwork(
            albumId,
            ArtworkType.ALBUM,
            format: ArtworkFormat.JPEG,
            size: 512,
          )
          .timeout(_queryTimeout);
    } on Object {
      // Missing artwork surfaces as a platform error on some Android versions,
      // and a slow media provider surfaces as a TimeoutException. Both mean the
      // same thing to a caller: no cover to show.
      bytes = null;
    }

    _cache[albumId] = bytes;
    _evictIfNeeded();
    return bytes;
  }

  /// Drop the oldest entries once the cache is over its limit.
  void _evictIfNeeded() {
    while (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Forget everything, so the next request re-queries the media store.
  void clear() {
    _cache.clear();
    _inFlight.clear();
  }

  /// Warm the cache for the albums in [songs], front to back.
  ///
  /// The first paint of a list fires one media-store query per visible album,
  /// and each crossing costs a frame budget -- that serial stutter is the slow
  /// load. Walking the first [limit] unique albums sequentially in the
  /// background moves that cost off the scroll path: by the time rows build,
  /// their covers are already cached. Sequential, not parallel, so a burst of
  /// channel traffic never contends with playback or the active scroll.
  Future<void> prefetchAlbums(Iterable<WavelySong> songs, {int limit = 30}) async {
    final seen = <int>{};
    for (final song in songs) {
      final albumId = song.albumId;
      // Skip tracks with no album, already-cached albums, and repeats: only
      // the first sighting of an uncached album costs a query.
      if (albumId == null ||
          _cache.containsKey(albumId) ||
          !seen.add(albumId)) {
        continue;
      }
      if (seen.length > limit) break;
      await artworkFor(song);
    }
  }
}
