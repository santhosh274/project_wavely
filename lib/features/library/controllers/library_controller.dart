import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/song_model.dart';
import '../../../core/models/album_model.dart';
import '../../../core/models/artist_model.dart';
import '../../../core/models/playlist_model.dart';
import '../../../core/services/library_filter_store.dart';
import '../../../core/services/local_media_service.dart';

enum LibraryTab { songs, albums, artists, playlists }

/// Called with the full song list every time a scan finishes.
///
/// The player needs this to rebuild the previous session's queue: a stored queue
/// is only a list of ids, and the songs behind those ids do not exist until the
/// media store has been read.
typedef LibraryLoadedCallback = Future<void> Function(List<WavelySong> songs);

/// Controller managing Local Library Data & Search/Filter state
class LibraryController extends ChangeNotifier {
  final LocalMediaService _mediaService;

  /// Where the user's folder / duration exclusions are read from and written to.
  final LibraryFilterStore _filterStore;

  /// [mediaService] and [filterStore] are injectable so tests can supply stubs
  /// instead of hitting the platform media channels or the filesystem.
  LibraryController({
    LocalMediaService? mediaService,
    LibraryFilterStore? filterStore,
  }) : _mediaService = mediaService ?? LocalMediaService(),
       _filterStore = filterStore ?? FileLibraryFilterStore() {
    // Showing a runtime permission dialog requires a foreground Activity, which
    // does not exist yet while main() is still assembling the provider tree.
    // Requesting this early makes permission_handler throw
    // PlatformException("Unable to detect current Android Activity"), which the
    // old catch-all silently turned into a demo library. Deferring to the first
    // frame gives the plugin an Activity to attach to.
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  /// Scan, then apply the saved exclusions.
  ///
  /// The scan runs first on purpose: reading preferences can be slow, or on a
  /// platform with no store at all it can never answer, and a library that waits
  /// on it would sit empty behind its own loading state. The exclusions land a
  /// moment later and rebuild the (already shown) library.
  Future<void> _init() async {
    await loadLibrary();
    await _loadFilterSettings();
  }

  /// Set once [dispose] has run, so a preference read that answers after the
  /// controller is gone cannot notify a dead notifier.
  bool _disposed = false;

  /// Every song the media store returned, before the user's exclusions.
  ///
  /// Kept so the exclusion rules can be re-applied -- and the folder picker can
  /// list folders whose songs are hidden -- without a fresh scan.
  List<WavelySong> _scannedSongs = [];

  List<WavelySong> _allSongs = [];
  List<WavelySong> _filteredSongs = [];
  List<WavelyAlbum> _albums = [];
  List<WavelyArtist> _artists = [];
  List<WavelyPlaylist> _playlists = [];

  /// Distinct genres in the library, rebuilt only when [_allSongs] changes.
  ///
  /// The getter runs in the search screen's build, and walking thousands of
  /// tracks per keystroke to produce a list that only a rescan can change was
  /// wasted work on every rebuild.
  List<String>? _genresCache;

  /// [_allSongs] keyed by id, for the lookups that resolve ids to songs
  /// (playlists, play history). Rebuilt only when [_allSongs] changes.
  Map<String, WavelySong> _songsById = const {};

  /// Read-only view of [_allSongs].
  ///
  /// Held rather than minted per read: `allSongs` is read on every build of
  /// several screens, and wrapping the list each time allocated a new object per
  /// read -- which also defeated [totalDurationOf]'s cache, since the list it was
  /// handed was never the same instance twice.
  List<WavelySong> _allSongsView = const [];

  /// One pre-lowercased haystack per song, aligned with [_allSongs].
  ///
  /// Search used to lowercase four fields per song on every keystroke. On a
  /// library of thousands of tracks that is the whole cost of typing, so the
  /// lowercasing is paid once per scan and each keystroke only runs `contains`
  /// over strings that are already folded.
  List<String> _searchHaystacks = const [];

  /// Folder paths whose songs the user has chosen to hide.
  final Set<String> _excludedFolders = {};

  /// Tracks shorter than this are hidden. [Duration.zero] keeps everything.
  Duration _minimumDuration = Duration.zero;

  /// Distinct folders across the scan, with their song counts. Rebuilt only
  /// when [_scannedSongs] changes.
  Map<String, int>? _folderCountsCache;

  /// Playlists the user created, kept across reloads.
  ///
  /// [loadLibrary] rebuilds the genre-derived playlists from scratch, so they
  /// cannot live in [_playlists] directly or a rescan would silently delete
  /// every playlist the user had made.
  final List<WavelyPlaylist> _userPlaylists = [];

  /// Song ids in the order they were last played, newest first.
  final List<String> _playHistory = [];

  /// Notified after every completed scan, so the player can restore the queue
  /// the last session was playing.
  ///
  /// Injected the same way [PlayerController.onTrackStarted] is, and re-pointed
  /// on every provider rebuild, because the library is created before the
  /// player that consumes it.
  LibraryLoadedCallback? _onLoaded;

  set onLoaded(LibraryLoadedCallback? callback) => _onLoaded = callback;

  LibraryTab _activeTab = LibraryTab.songs;
  String _searchQuery = '';
  String? _selectedGenre;
  bool _isLoading = true;
  LibraryLoadStatus _status = LibraryLoadStatus.empty;
  String? _statusMessage;

  List<WavelySong> get songs => _filteredSongs;
  List<WavelyAlbum> get albums => _albums;
  List<WavelyArtist> get artists => _artists;
  List<WavelyPlaylist> get playlists => _playlists;

  /// Only the playlists the user created, newest first.
  List<WavelyPlaylist> get userPlaylists {
    final owned = _playlists.where((p) => !p.isAutoGenerated).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return owned;
  }

  LibraryTab get activeTab => _activeTab;
  String get searchQuery => _searchQuery;

  /// The genre currently narrowing the results, if any.
  String? get selectedGenre => _selectedGenre;

  /// Whether any filter is active, so the UI can tell "nothing found" apart from
  /// "nothing searched for yet".
  bool get hasActiveFilter =>
      _searchQuery.trim().isNotEmpty || _selectedGenre != null;
  bool get isLoading => _isLoading;

  /// Outcome of the most recent [loadLibrary], used to tell "no permission",
  /// "no music" and "query failed" apart instead of showing demo tracks.
  LibraryLoadStatus get status => _status;
  String? get statusMessage => _statusMessage;
  bool get needsPermission => _status == LibraryLoadStatus.permissionDenied;

  /// Distinct genres present in the library, for the search filter chips.
  List<String> get genres =>
      _genresCache ??= _computeGenres();

  List<String> _computeGenres() {
    final seen = <String>{};
    for (final song in _allSongs) {
      final genre = song.genre;
      if (genre != null && genre.isNotEmpty) seen.add(genre);
    }
    final sorted = seen.toList()..sort();
    return sorted;
  }

  /// Drop the derived caches; the next getter call rebuilds them.
  ///
  /// Called whenever [_allSongs] is written, which is rare (a scan, a
  /// favourite toggle), so the caches never go stale for long and the common
  /// read path never rebuilds them.
  void _invalidateSongDerivedCaches() {
    _genresCache = null;
    _allSongsView = List.unmodifiable(_allSongs);
    // The cached runtime belongs to the previous list, which no longer exists.
    _runtimeFor = null;
    _songsById = {for (final song in _allSongs) song.id: song};
    _searchHaystacks = [
      for (final song in _allSongs)
        // A NUL joins the fields: it cannot be typed, so a query can never be
        // matched across two fields the way a space or a comma could.
        '${song.title}\u0000${song.artist}\u0000${song.album}\u0000'
            '${song.genre ?? ''}'
            .toLowerCase(),
    ];
  }

  Future<void> loadLibrary() => _loadLibrary(attempt: 1);

  /// A cold launch can start the Dart entrypoint before the host Activity is
  /// attached, and permission_handler then throws
  /// PlatformException("Unable to detect current Android Activity") on the
  /// first attempt. That is a startup race, not a real failure, so it is
  /// retried a couple of times before being surfaced.
  static const int _maxLoadAttempts = 3;

  Future<void> _loadLibrary({required int attempt}) async {
    _isLoading = true;
    notifyListeners();

    var result = await _mediaService.fetchLocalSongs();

    while (result.status == LibraryLoadStatus.error &&
        attempt < _maxLoadAttempts) {
      await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      result = await _mediaService.fetchLocalSongs();
      attempt++;
    }

    _status = result.status;
    _statusMessage = result.message;
    // Copied rather than adopted: favourite toggles write back into this list,
    // and a const or otherwise unmodifiable list from the service would make
    // every heart throw.
    _scannedSongs = List.of(result.songs);
    // The folder list is derived from the scan, so it is rebuilt with it.
    _folderCountsCache = null;

    // Everything the UI reads hangs off the exclusion-filtered list, so this is
    // the one place a folder/duration rule is applied.
    _rebuildFromScan();

    _isLoading = false;
    notifyListeners();

    // Fired with the unfiltered list: the queue being restored may well contain
    // songs the active search or genre chip is hiding. Not awaited, because a
    // slow restore should not hold the library in its loading state.
    final loaded = _onLoaded;
    if (loaded != null) unawaited(loaded(List.of(_allSongs)));
  }

  /// Open the OS settings page so a blocked permission can be granted.
  Future<void> openSystemSettings() async {
    await _mediaService.openSettings();
  }

  void setActiveTab(LibraryTab tab) {
    _activeTab = tab;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    // Typing is an explicit search, so it takes over from any genre chip. Left
    // in place, a leftover chip would keep narrowing results the user could not
    // see the reason for.
    _selectedGenre = null;
    _applyFilter();
    notifyListeners();
  }

  /// Filter by an exact genre match.
  ///
  /// Separate from [setSearchQuery] because a genre chip means "that genre", not
  /// "any track whose text happens to contain this word" -- a search for
  /// "ambient" also matches songs merely titled "Ambient Glow".
  void setGenreFilter(String? genre) {
    _selectedGenre = genre;
    _searchQuery = '';
    _applyFilter();
    notifyListeners();
  }

  void clearSearchQuery() {
    _searchQuery = '';
    _selectedGenre = null;
    _applyFilter();
    notifyListeners();
  }

  void _applyFilter() {
    final query = _searchQuery.trim().toLowerCase();
    final genre = _selectedGenre;

    if (query.isEmpty && genre == null) {
      _filteredSongs = List.of(_allSongs);
      return;
    }

    // Indexed rather than `where`: the haystacks are aligned with [_allSongs],
    // so this reads one already-folded string per song instead of folding four
    // fields per song on every keystroke.
    final result = <WavelySong>[];
    for (var i = 0; i < _allSongs.length; i++) {
      final song = _allSongs[i];
      if (genre != null && song.genre != genre) continue;
      if (query.isNotEmpty && !_searchHaystacks[i].contains(query)) continue;
      result.add(song);
    }
    _filteredSongs = result;
  }

  // ---------------------------------------------------------------------
  // Library exclusions (Settings)
  // ---------------------------------------------------------------------

  /// Whether any folder or duration rule is currently hiding tracks.
  bool get hasLibraryFilters =>
      _excludedFolders.isNotEmpty || _minimumDuration > Duration.zero;

  /// The shortest a track may be before it is hidden.
  Duration get minimumDuration => _minimumDuration;

  /// Folder paths the user has chosen to hide.
  Set<String> get excludedFolders => Set.unmodifiable(_excludedFolders);

  /// Whether [folder] is currently excluded.
  bool isFolderExcluded(String folder) => _excludedFolders.contains(folder);

  /// How many scanned tracks are hidden by the current rules.
  int get excludedSongCount =>
      _scannedSongs.length - _allSongs.length;

  /// The folders the scan found, each with its track count.
  ///
  /// Computed from the *scanned* list, so a folder whose songs are all hidden
  /// still appears here and can be switched back on.
  Map<String, int> get folderSongCounts =>
      _folderCountsCache ??= _computeFolderCounts();

  Map<String, int> _computeFolderCounts() {
    final counts = <String, int>{};
    for (final song in _scannedSongs) {
      final folder = folderOfSong(song);
      if (folder == null) continue;
      counts[folder] = (counts[folder] ?? 0) + 1;
    }
    return counts;
  }

  /// The folder paths the scan found, sorted for a stable settings list.
  List<String> get folderOptions {
    final folders = folderSongCounts.keys.toList()..sort();
    return folders;
  }

  /// Hide [duration]'s worth of short tracks (or nothing at [Duration.zero]).
  void setMinimumDuration(Duration duration) {
    final next = duration < Duration.zero ? Duration.zero : duration;
    if (next == _minimumDuration) return;
    _minimumDuration = next;
    _rebuildFromScan();
    notifyListeners();
    unawaited(_persistFilters());
  }

  /// Hide or restore every track in [folder].
  void setFolderExcluded(String folder, {required bool excluded}) {
    final changed = excluded
        ? _excludedFolders.add(folder)
        : _excludedFolders.remove(folder);
    if (!changed) return;
    _rebuildFromScan();
    notifyListeners();
    unawaited(_persistFilters());
  }

  /// Drop every exclusion, restoring the full scanned library.
  void clearLibraryFilters() {
    if (!hasLibraryFilters) return;
    _excludedFolders.clear();
    _minimumDuration = Duration.zero;
    _rebuildFromScan();
    notifyListeners();
    unawaited(_persistFilters());
  }

  /// Load the saved exclusions, if any, and apply them to the scanned library.
  Future<void> _loadFilterSettings() async {
    final settings = await _filterStore.read();
    if (settings == null || _disposed) return;

    _excludedFolders
      ..clear()
      ..addAll(settings.excludedFolders);
    _minimumDuration = settings.minimumDuration;

    if (!hasLibraryFilters || _scannedSongs.isEmpty) return;
    _rebuildFromScan();
    notifyListeners();
  }

  Future<void> _persistFilters() => _filterStore.write(
    LibraryFilterSettings(
      excludedFolders: Set.of(_excludedFolders),
      minimumDuration: _minimumDuration,
    ),
  );

  /// Re-apply the exclusions to the scan and rebuild everything derived from it.
  ///
  /// Everything hangs off [_allSongs], so one pass here is what makes an
  /// excluded track disappear from albums, artists, genre playlists, search,
  /// favourites and playlists at once.
  void _rebuildFromScan() {
    _allSongs = _applyExclusions(_scannedSongs);
    _invalidateSongDerivedCaches();
    _albums = _mediaService.extractAlbums(_allSongs);
    _artists = _mediaService.extractArtists(_allSongs);
    _playlists = [
      ..._mediaService.extractGenrePlaylists(_allSongs),
      ..._userPlaylists,
    ];
    _applyFilter();
  }

  /// Drop the tracks the user has chosen to keep out.
  List<WavelySong> _applyExclusions(List<WavelySong> songs) {
    if (!hasLibraryFilters) return List.of(songs);
    return [
      for (final song in songs)
        if (!_excludedFolders.contains(folderOfSong(song)) &&
            song.duration >= _minimumDuration)
          song,
    ];
  }

  void toggleFavorite(String songId) {
    final index = _allSongs.indexWhere((s) => s.id == songId);
    if (index >= 0) {
      final song = _allSongs[index];
      _allSongs[index] = song.copyWith(isFavorite: !song.isFavorite);
      _invalidateSongDerivedCaches();
      _applyFilter();
      notifyListeners();
    }
  }

  /// Create an empty playlist.
  ///
  /// Returns it so a caller can open or seed it straight away rather than
  /// hunting for it in the list again.
  WavelyPlaylist createPlaylist(String name) =>
      createPlaylistWithSong(name, null);

  /// Create a playlist, optionally seeded with [songId].
  ///
  /// The playlist is stored in [_userPlaylists] as well as [_playlists] so it
  /// survives the next library scan.
  WavelyPlaylist createPlaylistWithSong(String name, String? songId) {
    final newPlaylist = WavelyPlaylist(
      id: 'playlist-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      songIds: songId == null ? const [] : [songId],
      createdAt: DateTime.now(),
      source: PlaylistSource.user,
    );
    _userPlaylists.add(newPlaylist);
    _playlists = [..._playlists, newPlaylist];
    notifyListeners();
    return newPlaylist;
  }

  /// Add [songId] to the playlist with [playlistId].
  ///
  /// Returns false when the playlist is unknown, and does nothing when the song
  /// is already in it, so a caller can report the outcome instead of guessing.
  bool addToPlaylist({required String playlistId, required String songId}) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index < 0) return false;

    final playlist = _playlists[index];
    if (playlist.songIds.contains(songId)) return true;

    final updated = playlist.copyWith(songIds: [...playlist.songIds, songId]);
    _replacePlaylist(updated);
    notifyListeners();
    return true;
  }

  /// Remove [songId] from the playlist with [playlistId].
  ///
  /// Returns false when the playlist or the song is not there, so callers can
  /// report the outcome instead of assuming the removal happened.
  bool removeFromPlaylist({
    required String playlistId,
    required String songId,
  }) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index < 0) return false;

    final playlist = _playlists[index];
    if (!playlist.songIds.contains(songId)) return false;

    _replacePlaylist(
      playlist.copyWith(
        songIds: playlist.songIds.where((id) => id != songId).toList(),
      ),
    );
    notifyListeners();
    return true;
  }

  /// Delete the playlist with [playlistId].
  ///
  /// Returns false when there is no such playlist. Genre playlists are rebuilt on
  /// every scan, so deleting one is pointless: they are removed for this session
  /// and reappear on the next scan.
  bool deletePlaylist(String playlistId) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index < 0) return false;

    final playlist = _playlists[index];
    _playlists.removeAt(index);
    _userPlaylists.removeWhere((p) => p.id == playlistId);
    // Only bother the user about it if it was actually theirs to delete.
    if (!playlist.isAutoGenerated) {
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  /// Write [playlist] over the old entry with the same id in both lists.
  void _replacePlaylist(WavelyPlaylist playlist) {
    _playlists = [
      for (final existing in _playlists)
        if (existing.id == playlist.id) playlist else existing,
    ];
    _userPlaylists.removeWhere((p) => p.id == playlist.id);
    if (!playlist.isAutoGenerated) _userPlaylists.add(playlist);
  }

  /// Whether [songId] is already in the playlist with [playlistId].
  bool playlistContains(String playlistId, String songId) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    return index >= 0 && _playlists[index].songIds.contains(songId);
  }

  /// Songs in [playlistId], resolved against the library.
  ///
  /// Returns an empty list for an unknown playlist rather than inventing tracks,
  /// and skips ids that no longer exist on the device.
  List<WavelySong> songsInPlaylist(String playlistId) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index < 0) return const [];

    return [
      for (final id in _playlists[index].songIds)
        if (_songsById[id] != null) _songsById[id]!,
    ];
  }

  /// All tracks, ignoring the active search query.
  ///
  /// The filtered [songs] list is what the browse and search tabs render, but
  /// "All Songs" has to keep meaning all of them even while a search is active.
  List<WavelySong> get allSongs => _allSongsView;

  /// Songs added to the device most recently.
  ///
  /// The media query already sorts by DATE_ADDED descending, so _allSongs is in
  /// that order and this is just a prefix of it.
  List<WavelySong> recentlyAdded({int limit = 50}) =>
      _allSongs.take(limit).toList();

  /// Songs marked as favourites.
  List<WavelySong> get favorites =>
      _allSongs.where((s) => s.isFavorite).toList();

  /// Songs on the album with [albumId].
  ///
  /// Album ids are the album name (see `extractAlbums`), so this resolves
  /// straight back to the songs that carry that album.
  List<WavelySong> songsInAlbum(String albumId) =>
      _allSongs.where((s) => s.album == albumId).toList();

  /// Songs credited to the artist with [artistId].
  ///
  /// Artist ids are the artist name (see `extractArtists`).
  List<WavelySong> songsByArtist(String artistId) =>
      _allSongs.where((s) => s.artist == artistId).toList();

  /// The list the cached runtime in [_runtimeTotal] belongs to.
  List<WavelySong>? _runtimeFor;
  Duration _runtimeTotal = Duration.zero;

  /// Total runtime of [songs], for the headers on the collection tabs.
  ///
  /// A single-entry cache, because the same list is asked for its runtime by a
  /// header that rebuilds every time the player announces anything: play, pause,
  /// next, and the queue list itself. On a library of a few thousand tracks that
  /// fold is the most expensive thing on the screen, and its answer cannot change
  /// while the list it was computed from is the same object. Keyed on identity
  /// rather than equality: any new list -- a rescan, a favourite toggle, a
  /// search -- is a different object and recomputes.
  Duration totalDurationOf(List<WavelySong> songs) {
    if (identical(_runtimeFor, songs)) return _runtimeTotal;

    var total = Duration.zero;
    for (final song in songs) {
      total += song.duration;
    }
    _runtimeFor = songs;
    _runtimeTotal = total;
    return total;
  }

  /// Record that [songId] was played, most recent first.
  ///
  /// Playback history lives here rather than in [PlayerController] because it is
  /// a property of the library, and because a track can be played without it
  /// appearing in the library list the player was given as a queue context.
  void recordPlayed(String songId) {
    // Re-playing a track should move it to the top rather than duplicate it.
    _playHistory.remove(songId);
    _playHistory.insert(0, songId);

    // Keep the history bounded so it cannot grow for the life of the process.
    const maxHistory = 100;
    if (_playHistory.length > maxHistory) {
      _playHistory.removeRange(maxHistory, _playHistory.length);
    }
    notifyListeners();
  }

  /// Most recently played songs, resolved against the library.
  ///
  /// Empty until something has actually been played -- it is not backfilled with
  /// library songs, because showing songs as "recently played" that were never
  /// played is exactly the sort of placeholder this app is meant to avoid.
  List<WavelySong> get recentlyPlayed {
    final resolved = <WavelySong>[];
    for (final id in _playHistory) {
      final song = _songsById[id];
      if (song != null) resolved.add(song);
    }
    return resolved;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The folder a song's file sits in, or null when the path is not known.
///
/// Derived from the file path rather than the media store's own folder field,
/// which is not exposed by every query. A `content://` URI carries no real path,
/// so those tracks cannot be attached to a folder and are never excluded by one.
String? folderOfSong(WavelySong song) {
  final path = song.uri;
  if (path.isEmpty || path.contains('://')) return null;

  final separator = path.lastIndexOf('/');
  if (separator <= 0) return null;
  return path.substring(0, separator);
}
