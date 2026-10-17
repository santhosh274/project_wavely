import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/models/song_model.dart';
import '../../player/controllers/player_controller.dart';
import '../models/room_member.dart';
import '../models/room_message.dart';
import '../models/track_ref.dart';
import '../services/clock_sync.dart';
import '../services/local_network_permission.dart';
import '../services/local_room_transport.dart';
import '../services/room_audio_cache.dart';
import '../services/room_transport.dart';
import '../services/track_matcher.dart';

/// What this device is in the room it is in, if any.
enum RoomRole { none, host, guest }

/// The name to show for this device in a room's member list.
///
/// The device's own hostname is the only name available without inventing one,
/// and on both platforms it is usually the name the owner gave the device --
/// "Priya's iPhone" on iOS, the model on most Android builds. A room of five
/// rows all reading "Listener" would be worse than any of those. Falls back to a
/// plain label when the platform will not say, or says something useless like
/// `localhost`.
String defaultRoomDisplayName() {
  try {
    final hostname = Platform.localHostname.trim();
    if (hostname.isNotEmpty && hostname.toLowerCase() != 'localhost') {
      return hostname;
    }
  } on Object {
    // Not every platform exposes one, and a name is not worth failing a room
    // over.
  }
  return 'Listener';
}

/// A listening room: one host, up to five guests, one song playing on all of
/// them.
///
/// The shape of the whole feature is decided by one fact: a guest plays its own
/// copy of the track rather than receiving audio. Nothing else is possible
/// without streaming the host's sound, which iOS will not let an app do and
/// Android only with a screen-capture consent dialog. So the room synchronises
/// the *control plane* -- what to play, from where, and when -- and every device
/// makes its own sound. That is also what makes it cheap: the messages are tiny
/// and rare, so the link can be a plain WebSocket between the phones, with no
/// server, no STUN, no TURN and no internet at all.
///
/// Synchronisation is two mechanisms working together:
///
///  * **A shared clock.** [ClockSync] measures the offset between this device's
///    clock and the host's by exchanging four timestamps, so a moment named by
///    the host means the same thing here.
///  * **Scheduled starts plus a drift loop.** A start names the instant it should
///    take effect, which removes the network delay from the equation; after that
///    each guest corrects itself locally, nudging the playback rate for a
///    correction small enough to be inaudible and seeking only when it has really
///    fallen behind.
class RoomController extends ChangeNotifier {
  RoomController({
    required this.player,
    List<WavelySong> Function()? library,
    RoomTransportFactory? transportFactory,
    RoomAudioCache? audioCache,
    LocalNetworkPermission? localNetwork,
    this.displayName = 'Listener',
    this.clockInterval = const Duration(seconds: 2),
    this.beatInterval = const Duration(seconds: 4),
    this.driftInterval = const Duration(seconds: 1),
  }) : _library = library ?? (() => const []),
       _audioCache = audioCache ?? RoomAudioCache(),
       _localNetwork = localNetwork ?? const PlatformLocalNetworkPermission() {
    _factory =
        transportFactory ??
        LocalRoomTransportFactory(
          fileSource: _shareTrack,
          // The room's own cap, handed to the transport so the host refuses a
          // sixth guest instead of the member list quietly outgrowing the room.
          maxGuests: maxMembers - 1,
        );
    player.addListener(_onPlayerChanged);
  }

  /// The player this room drives. The room is the only thing that writes to it
  /// while it is up, which is what keeps every device on the same playhead.
  final PlayerController player;

  /// The name shown for this device in the member list.
  final String displayName;

  /// How often a guest re-measures the host's clock.
  final Duration clockInterval;

  /// How often the host re-anchors the room while playing.
  final Duration beatInterval;

  /// How often a guest checks its own playhead against the room.
  final Duration driftInterval;

  /// The songs available to match a host's track against. A function, not a
  /// list, because the library is replaced wholesale by every scan.
  List<WavelySong> Function() _library;

  /// Point the room at the live library.
  ///
  /// Set by the provider tree on every rebuild, because a scan replaces the song
  /// list rather than updating it -- a matcher holding the old list would stop
  /// finding tracks the user has just added.
  set librarySource(List<WavelySong> Function() source) => _library = source;

  final RoomAudioCache _audioCache;

  /// Asked before any room socket is opened. See [LocalNetworkPermission].
  final LocalNetworkPermission _localNetwork;

  late final RoomTransportFactory _factory;
  final ClockSync _clock = ClockSync();

  /// How much notice a scheduled start carries.
  ///
  /// The frame has to be read, the track loaded and the decoder primed before the
  /// moment arrives, and clocks disagree by a few milliseconds even after the
  /// offset is known. A quarter of a second covers both without making the room
  /// feel slow.
  static const int leadMs = 250;

  /// How much of the queue is sent with a start. A queue can be thousands of
  /// tracks; a guest only needs enough to fill its own queue list and to move
  /// forward a few times without another frame.
  static const int queueCap = 50;

  /// Drift beyond which a guest seeks instead of nudging. Above this the nudge
  /// would take so long to converge that the correction is better done at once.
  static const int seekThresholdMs = 300;

  /// Drift below which nothing is done at all. Chasing a few tens of
  /// milliseconds would mean constantly changing the rate for no audible gain.
  static const int nudgeThresholdMs = 40;

  /// How many milliseconds of drift one whole unit of rate change corrects.
  static const double _nudgeScale = 2000;

  /// The rate window a correction is allowed to use. Three percent is around the
  /// point where a rate change starts to be audible as a waver.
  static const double _minRate = 0.97;
  static const double _maxRate = 1.03;

  RoomTransport? _transport;

  /// The address this guest dialled, kept for the audio fetch.
  Uri? _roomUri;

  RoomRole _role = RoomRole.none;
  String? _status;
  String? _hostName;

  final Map<String, RoomMember> _members = {};

  /// The host's view of which guests are missing the current track.
  final Set<String> _guestsMissing = {};

  /// The position and clock instant the room is being measured from.
  int _anchorPositionMs = 0;
  int _anchorLocalMs = 0;
  bool _anchorPlaying = false;

  /// The last drift this guest measured, for the status line.
  int? _lastDriftMs;

  StreamSubscription<String>? _joinedSub;
  StreamSubscription<String>? _leftSub;
  StreamSubscription<RoomEnvelope>? _incomingSub;

  Timer? _clockTimer;
  Timer? _beatTimer;
  Timer? _driftTimer;

  var _clockSeq = 0;
  final Map<int, int> _clockSentAt = {};

  /// Guards against a correction still running when the next tick arrives: the
  /// seeks inside it are asynchronous, and two overlapping corrections would
  /// fight each other.
  bool _correcting = false;

  /// Host bookkeeping: the last player state a broadcast was made for.
  String? _lastSongId;
  bool _lastPlaying = false;

  // ---------------------------------------------------------------------------
  // What the UI reads
  // ---------------------------------------------------------------------------

  RoomRole get role => _role;
  bool get isHost => _role == RoomRole.host;
  bool get isGuest => _role == RoomRole.guest;
  bool get isActive => _role != RoomRole.none && _transport != null;

  /// The most people one room holds: a host and five guests.
  ///
  /// A limit rather than a judgement: the host is one socket and one broadcast
  /// per guest, and the sync only works while every device is a hop from the
  /// host on the same network.
  static const int maxMembers = 6;

  /// The code a guest has to present. Empty for a guest.
  String get roomCode => _transport?.roomCode ?? '';

  /// Whether a guest has told the host it does not have the current track.
  bool get guestsMissingTrack => _guestsMissing.isNotEmpty;

  /// The link to hand to a guest. Null for a guest.
  Uri? get joinUri => _transport?.joinUri;

  /// What the room is doing, or how it failed. Null when there is nothing to
  /// say.
  String? get statusMessage => _status;

  String? get hostName => _hostName;

  /// True on a guest, where the transport controls belong to the host.
  bool get controlsLocked => isGuest && isActive;

  /// The round trip of the best clock sample, once one has landed. Shown as the
  /// room's own confidence in itself.
  int? get roundTripMs => _clock.roundTripMs;

  /// How far behind or ahead this guest last measured itself, in milliseconds.
  int? get lastDriftMs => _lastDriftMs;

  /// The host first, then the guests in the order they joined.
  List<RoomMember> get members {
    final list = _members.values.toList()
      ..sort((a, b) {
        if (a.isHost != b.isHost) return a.isHost ? -1 : 1;
        return a.id.compareTo(b.id);
      });
    return list;
  }

  // ---------------------------------------------------------------------------
  // Starting and joining
  // ---------------------------------------------------------------------------

  /// Open a room on the local network and become its host.
  Future<void> startRoom() async {
    if (isActive) return;
    if (!await _ensureLocalNetwork()) return;

    _set('Opening a room…');
    notifyListeners();

    try {
      final transport = await _factory.host();
      await _attach(transport);
      _role = RoomRole.host;
      _members[transport.selfId] = RoomMember(
        id: transport.selfId,
        name: displayName,
        isHost: true,
      );
      // A seek the host makes is room news; a track change and a play/pause are
      // picked up by diffing the player instead, so they are announced once
      // whatever caused them.
      player.onSeeked = _onHostSeeked;
      _lastSongId = player.currentSong?.id;
      _lastPlaying = player.isPlaying;
      _beatTimer = Timer.periodic(beatInterval, (_) => _broadcastBeat());
      _set(null);
      notifyListeners();
    } on Object catch (error) {
      await _teardown();
      _set('Could not open a room: $error');
      notifyListeners();
    }
  }

  /// Join a room from the link its host shared, or from the address and code a
  /// guest has read off the host's screen.
  ///
  /// [code] is the second half of a hand-typed room: the address cannot be
  /// guessed from the code without a directory to look it up in, which is the
  /// server this feature deliberately does without, so the two are typed
  /// together -- or the whole link is pasted, and then it is already in there.
  Future<void> joinRoom(String link, {String? code}) async {
    if (isActive) return;

    final uri = _parseLink(link, code: code);
    if (uri == null) {
      _set('That does not look like a room link.');
      notifyListeners();
      return;
    }
    if (_cleanCode(uri.queryParameters['code']) == null) {
      // Said here rather than left to the host, which turns away a guest that
      // cannot present the code: a sentence the user can act on beats a socket
      // error they cannot.
      _set('That link needs the room code as well.');
      notifyListeners();
      return;
    }

    if (!await _ensureLocalNetwork()) return;

    _set('Joining…');
    notifyListeners();

    try {
      final transport = await _factory.join(uri);
      await _attach(transport);
      _roomUri = uri;
      _role = RoomRole.guest;
      _members[transport.selfId] = RoomMember(
        id: transport.selfId,
        name: displayName,
        isHost: false,
      );
      // Seeded rather than waited for: the host's join happened the moment the
      // socket opened, before this controller could subscribe, so the event is
      // gone. Its real name arrives with its hello a moment later.
      _members['host'] = const RoomMember(
        id: 'host',
        name: 'Host',
        isHost: true,
      );
      // The host owns playback while the room is up, so a local tap would only
      // be undone a moment later. Intercepting is what makes the controls read
      // as "the host is driving" rather than as broken.
      player.intentInterceptor = (_) => true;
      _clockTimer = Timer.periodic(clockInterval, (_) => _sendTimeRequest());
      _driftTimer = Timer.periodic(driftInterval, (_) => _correctDrift());
      _sendTimeRequest();
      transport.send(HelloMessage(name: displayName, isHost: false));
      _set('Waiting for the host to play something…');
      notifyListeners();
    } on WebSocketException catch (error) {
      // The host refuses a guest it will not take with a status rather than a
      // sentence, so the two cases worth naming are named here.
      await _teardown();
      _set(
        error.httpStatusCode == HttpStatus.serviceUnavailable
            ? 'That room is full.'
            : 'Could not join that room: $error',
      );
      notifyListeners();
    } on Object catch (error) {
      await _teardown();
      _set('Could not join that room: $error');
      notifyListeners();
    }
  }

  /// Leave the room, whoever we were in it.
  Future<void> leave() => _end(null);

  /// Clear a status line the user has read.
  void clearStatus() {
    if (_status == null) return;
    _status = null;
    notifyListeners();
  }

  @override
  void dispose() {
    player.removeListener(_onPlayerChanged);
    unawaited(_teardown());
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Plumbing
  // ---------------------------------------------------------------------------

  Future<void> _attach(RoomTransport transport) async {
    _transport = transport;
    _joinedSub = transport.peerJoined.listen(_onPeerJoined);
    _leftSub = transport.peerLeft.listen(_onPeerLeft);
    _incomingSub = transport.incoming.listen(_onMessage);
  }

  Future<void> _end(String? status) async {
    await _teardown();
    _status = status;
    notifyListeners();
  }

  /// Shut everything down, whichever role this device was in.
  ///
  /// Nothing here is waited on, and that is deliberate. Cancelling a stream
  /// subscription, closing a stream and closing the link all acknowledge on a
  /// later turn of the event loop, so a teardown that awaited them could sit
  /// half-finished with the room still reading as live -- which is exactly the
  /// state the UI is driven by, and in a widget test, whose clock only turns
  /// when the test pumps, it never finishes at all. The room is over the moment
  /// it stops listening; releasing the link is not something anyone is waiting
  /// on.
  Future<void> _teardown() async {
    _clockTimer?.cancel();
    _beatTimer?.cancel();
    _driftTimer?.cancel();
    _clockTimer = null;
    _beatTimer = null;
    _driftTimer = null;

    // Detached before the link is closed, because the departure that close
    // reports reads on a guest as *the host* leaving, and would otherwise end a
    // room the user has just left on its own terms -- with "the host left" as
    // the parting message.
    final subscriptions = [_incomingSub, _joinedSub, _leftSub];
    _incomingSub = null;
    _joinedSub = null;
    _leftSub = null;
    for (final subscription in subscriptions) {
      if (subscription != null) unawaited(subscription.cancel());
    }

    final transport = _transport;
    _transport = null;
    _roomUri = null;
    if (transport != null) unawaited(transport.close());

    if (_role == RoomRole.guest) {
      player.intentInterceptor = null;
      // Left at an altered rate, the next song the user plays themselves would
      // run at it.
      unawaited(player.audioService.setSpeed(1.0));
    }
    if (_role == RoomRole.host) player.onSeeked = null;

    _role = RoomRole.none;
    _members.clear();
    _guestsMissing.clear();
    _hostName = null;
    _status = null;
    _lastDriftMs = null;
    _clockSentAt.clear();
    _clock.reset();
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  /// Ask the OS for local-network access, returning false when it is refused for
  /// good.
  ///
  /// Run before a room opens any socket: on Android 17 the platform will not let
  /// the host bind, nor a guest dial the host, without it. The explaining
  /// message is set here so the sheet the user is already looking at tells them
  /// about the one room failure they can fix themselves.
  Future<bool> _ensureLocalNetwork() async {
    if (await _localNetwork.request()) return true;
    _set(
      'Wavely needs local network access to open a room. '
      'Turn it on in Settings, then try again.',
    );
    notifyListeners();
    return false;
  }

  void _set(String? status) => _status = status;

  void _send(RoomMessage message, {String? to}) =>
      _transport?.send(message, to: to);

  /// A guest dialled with no scheme in front of it ("192.168.1.4:51234") is a
  /// link too: people retype a room rather than paste it.
  ///
  /// The pieces a hand-typed room is missing are filled in here rather than
  /// required of the user. An address has no path, and the host answers on one
  /// route -- dialled as typed, it would ask for `/` and be turned away. A code
  /// typed beside the address is folded in, while a code that arrived inside a
  /// pasted link wins over it: the link is authoritative about its own room, and
  /// anything else is left over from the last one.
  Uri? _parseLink(String raw, {String? code}) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    final lower = text.toLowerCase();
    final hasRoomScheme =
        lower.startsWith('ws://') || lower.startsWith('wss://');

    // A link the app handed out, or an address a guest has read off the host's
    // screen and typed. Anything else -- a URL from somewhere else altogether --
    // is turned down rather than dialled.
    if (!hasRoomScheme && text.contains('://')) return null;

    // The scheme is put in front rather than looked for, because Dart's own
    // parser is no help with a typed address: it reads "192.168.1.24:51234" as a
    // scheme it does not recognise and gives up on the whole string, and reads
    // "localhost:8080" as a scheme called localhost.
    final parsed = Uri.tryParse(hasRoomScheme ? text : 'ws://$text');
    if (parsed == null || parsed.host.isEmpty) return null;

    // An address has no path, and the host answers on one route: dialled as
    // typed, this would ask for `/` and be turned away.
    final uri = parsed.path.isEmpty || parsed.path == '/'
        ? parsed.replace(path: LocalRoomRoutes.socket)
        : parsed;

    final roomCode =
        _cleanCode(uri.queryParameters['code']) ?? _cleanCode(code);
    if (roomCode == null) return uri;
    return uri.replace(
      queryParameters: {...uri.queryParameters, 'code': roomCode},
    );
  }

  /// A room code as the user means it, or null when they have not given one.
  ///
  /// Upper-cased and stripped to letters and digits: the code is read off one
  /// screen and typed into another, and a phone's keyboard will happily punctuate
  /// or capitalise it on the way.
  static String? _cleanCode(String? raw) {
    final text = (raw ?? '').toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    return text.isEmpty ? null : text;
  }

  // ---------------------------------------------------------------------------
  // Messages in
  // ---------------------------------------------------------------------------

  void _onPeerJoined(String peerId) {
    if (isHost) {
      // A placeholder only until the guest says its name. Written with
      // `putIfAbsent` because the two events race by nature: the host's join
      // callback and the guest's hello are one network hop apart, and on a fast
      // link the hello can win -- clobbering it would leave the member list
      // showing "Guest 2" for the whole session.
      _members.putIfAbsent(
        peerId,
        () => RoomMember(
          id: peerId,
          name: 'Guest ${_members.length}',
          isHost: false,
        ),
      );
      // Its real name, since only a guest announces itself.
      _send(HelloMessage(name: displayName, isHost: true), to: peerId);
      // And a guest that arrives mid-song has to be told where the song is, or
      // it sits silent until the host touches something.
      final song = player.currentSong;
      if (song != null) _send(_startFrame(), to: peerId);
      notifyListeners();
    }
  }

  void _onPeerLeft(String peerId) {
    _members.remove(peerId);
    _guestsMissing.remove(peerId);
    if (isGuest && peerId == 'host') {
      // The room is over. The player is handed back to the user rather than
      // left locked by a host that is no longer there.
      unawaited(_end('The host left the room.'));
      return;
    }
    notifyListeners();
  }

  void _onMessage(RoomEnvelope envelope) {
    switch (envelope.message) {
      case final HelloMessage message:
        _members[envelope.from] = RoomMember(
          id: envelope.from,
          name: message.name,
          isHost: message.isHost,
          missingCurrentTrack:
              _members[envelope.from]?.missingCurrentTrack ?? false,
        );
        if (message.isHost) _hostName = message.name;
        notifyListeners();

      case final TimeRequestMessage message:
        if (!isHost) return;
        // Stamped as late as possible so the host's own processing time does not
        // land in the guest's round trip.
        final now = _now();
        _send(
          TimeReplyMessage(
            seq: message.seq,
            clientEpochMs: message.clientEpochMs,
            hostEpochMs: now,
            hostReplyMs: _now(),
          ),
          to: envelope.from,
        );

      case final TimeReplyMessage message:
        _applyTimeReply(message);

      case final StartMessage message:
        if (isGuest) unawaited(_applyStart(message));

      case final TransportMessage message:
        if (isGuest) unawaited(_applyTransport(message));

      case final SyncMessage message:
        if (isGuest) unawaited(_applySync(message));

      case final MissingTrackMessage message:
        if (!isHost) return;
        _guestsMissing.add(envelope.from);
        _members[envelope.from] =
            _members[envelope.from]?.copyWith(missingCurrentTrack: true) ??
            RoomMember(
              id: envelope.from,
              name: 'Guest',
              isHost: false,
              missingCurrentTrack: true,
            );
        _set('A guest does not have “${message.fingerprint}”.');
        notifyListeners();

      case final NoticeMessage message:
        _set(message.text);
        notifyListeners();
    }
  }

  void _applyTimeReply(TimeReplyMessage reply) {
    final sent = _clockSentAt.remove(reply.seq);
    if (sent == null) return;

    _clock.addRoundTrip(
      clientSentMs: sent,
      hostReceivedMs: reply.hostEpochMs,
      hostSentMs: reply.hostReplyMs,
      clientReceivedMs: _now(),
    );
    notifyListeners();
  }

  void _sendTimeRequest() {
    final transport = _transport;
    if (transport == null || !isGuest) return;

    final seq = ++_clockSeq;
    final sent = _now();
    _clockSentAt[seq] = sent;
    // A reply that never arrives must not accumulate for the whole session.
    if (_clockSentAt.length > 32) _clockSentAt.remove(_clockSentAt.keys.first);
    transport.send(TimeRequestMessage(seq: seq, clientEpochMs: sent));
  }

  // ---------------------------------------------------------------------------
  // Host: turning player events into room events
  // ---------------------------------------------------------------------------

  void _onPlayerChanged() {
    if (!isHost) return;

    final songId = player.currentSong?.id;
    final playing = player.isPlaying;

    if (songId != _lastSongId) {
      _lastSongId = songId;
      _lastPlaying = playing;
      // A new track is sent as a start rather than a play, because the guests
      // need to know *what* to play and from where, not just that they should be
      // playing.
      if (songId != null) _send(_startFrame());
      return;
    }

    if (playing != _lastPlaying) {
      _lastPlaying = playing;
      _broadcastTransport(
        playing ? TransportAction.play : TransportAction.pause,
      );
    }
  }

  StartMessage _startFrame() {
    final song = player.currentSong!;
    final now = _now();

    _anchorPositionMs = player.position.inMilliseconds;
    _anchorLocalMs = now;
    _anchorPlaying = player.isPlaying;

    return StartMessage(
      track: TrackRef.of(song),
      positionMs: _anchorPositionMs,
      hostAtMs: now + leadMs,
      playing: player.isPlaying,
      queue: _queueWindow(song),
    );
  }

  /// The slice of the queue sent with a start: the playing track and the ones
  /// after it.
  ///
  /// The window has to contain the track being played. A queue can be thousands
  /// of tracks long and the host may be anywhere in it, and a window taken from
  /// the head of the queue therefore omits the current track entirely once the
  /// host is past [queueCap] tracks in -- leaving the guest to resolve a track
  /// that is not in the list it was handed, and to play whatever the first entry
  /// happened to match instead. Starting at the current track costs nothing and
  /// gives the guest exactly the queue it needs to move forward a few times
  /// without another frame; the guest guarantees the current track is present
  /// even if this window could not resolve it.
  List<TrackRef> _queueWindow(WavelySong song) {
    final queue = player.queue;
    final index = queue.indexWhere((entry) => entry.id == song.id);
    final start = index < 0 ? 0 : index;

    final window = <TrackRef>[];
    for (var i = start; i < queue.length && window.length < queueCap; i++) {
      window.add(TrackRef.of(queue[i]));
    }
    // The tail ran out before the window was full: continue from the head, the
    // same way the queue wraps under repeat, so there are still tracks to move
    // onto rather than a window that ends on the playing track.
    for (var i = 0; i < start && window.length < queueCap; i++) {
      window.add(TrackRef.of(queue[i]));
    }
    return window;
  }

  void _onHostSeeked(Duration position) =>
      _broadcastTransport(TransportAction.seek, position: position);

  void _broadcastTransport(TransportAction action, {Duration? position}) {
    if (!isHost || _transport == null) return;

    final now = _now();
    final positionMs = (position ?? player.position).inMilliseconds;
    _anchorPositionMs = positionMs;
    _anchorLocalMs = now;
    _anchorPlaying = action != TransportAction.pause;

    _send(
      TransportMessage(
        action: action,
        positionMs: positionMs,
        hostAtMs: now + leadMs,
      ),
    );
  }

  /// The slow re-anchor.
  ///
  /// Between beats each guest corrects locally, which is what keeps the traffic
  /// down. But a local correction can only pull toward the anchor it was given,
  /// and that anchor slowly goes stale; without a fresh one every few seconds the
  /// whole room drifts together, following whichever guest has the worst clock.
  void _broadcastBeat() {
    if (!isHost || !player.isPlaying) return;
    _send(
      SyncMessage(
        positionMs: player.position.inMilliseconds,
        hostAtMs: _now(),
        playing: true,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Guest: applying what the host said
  // ---------------------------------------------------------------------------

  void _setAnchor({required int positionMs, required int hostAtMs, required bool playing}) {
    _anchorPositionMs = positionMs;
    _anchorLocalMs = _clock.toLocal(hostAtMs);
    _anchorPlaying = playing;
  }

  /// Where the room expects the playhead to be, in *this* device's clock.
  ///
  /// Clamped at the anchor for a frame that arrived early: a scheduled start
  /// names a moment a quarter of a second out, and until that moment arrives the
  /// right answer is "at the start position", not "before it".
  int _expectedPositionMs(int nowLocalMs) {
    if (!_anchorPlaying) return _anchorPositionMs;
    final elapsed = nowLocalMs - _anchorLocalMs;
    return _anchorPositionMs + (elapsed > 0 ? elapsed : 0);
  }

  /// Where the room expects this device's playhead to be right now.
  ///
  /// The same number the drift loop corrects toward, exposed so it can be shown
  /// and asserted on: a guest that is out of step is out of step by the
  /// difference between this and its own position.
  int get expectedPositionMs => _expectedPositionMs(_now());

  Future<void> _applyStart(StartMessage message) async {
    _setAnchor(
      positionMs: message.positionMs,
      hostAtMs: message.hostAtMs,
      playing: message.playing,
    );

    final ref = message.track;
    final matcher = TrackMatcher(_library());

    var found = matcher.match(ref) ?? _audioCache.cachedFor(ref.fingerprint);
    found ??= await _fetchFromHost(ref);

    final song = found;
    if (song == null) {
      _send(
        MissingTrackMessage(
          fingerprint: ref.fingerprint,
          hostSongId: ref.hostSongId,
        ),
      );
      _set('“${ref.title}” is not in your library.');
      notifyListeners();
      return;
    }

    final queue = matcher.matchQueue(message.queue);
    // Always a queue of at least one, and always containing the track being
    // played: playTrack locates it in the list to decide what plays next, and a
    // queue without it would leave it to fall back to index 0 -- the wrong song.
    // A downloaded copy the matcher could not resolve, or a window taken from
    // the wrong place, is repaired by putting the track in front of the queue.
    final context = queue.isEmpty
        ? <WavelySong>[song]
        : queue.any((entry) => entry.id == song.id)
        ? queue
        : <WavelySong>[song, ...queue];
    final target = _expectedPositionMs(_now());
    final playing = message.playing;

    await player.applyRemote(() async {
      await player.playTrack(
        song,
        queueContext: context,
        queueTitle: 'Listening room',
      );
      await player.seek(Duration(milliseconds: target));
      // playTrack starts the audio because that is what tapping a track means;
      // here the room decides, and the room may be paused.
      if (!playing) await player.togglePlayPause();
    });

    _set(null);
    notifyListeners();
  }

  Future<void> _applyTransport(TransportMessage message) async {
    switch (message.action) {
      case TransportAction.seek:
        _setAnchor(
          positionMs: message.positionMs,
          hostAtMs: message.hostAtMs,
          playing: _anchorPlaying,
        );
        await player.applyRemote(
          () => player.seek(Duration(milliseconds: message.positionMs)),
        );

      case TransportAction.play:
        _setAnchor(
          positionMs: message.positionMs,
          hostAtMs: message.hostAtMs,
          playing: true,
        );
        final target = _expectedPositionMs(_now());
        await player.applyRemote(() async {
          await player.seek(Duration(milliseconds: target));
          if (!player.isPlaying) await player.togglePlayPause();
        });

      case TransportAction.pause:
        _setAnchor(
          positionMs: message.positionMs,
          hostAtMs: message.hostAtMs,
          playing: false,
        );
        if (player.isPlaying) {
          await player.applyRemote(player.togglePlayPause);
        }
    }
  }

  Future<void> _applySync(SyncMessage message) async {
    _setAnchor(
      positionMs: message.positionMs,
      hostAtMs: message.hostAtMs,
      playing: message.playing,
    );

    if (message.playing != player.isPlaying) {
      await player.applyRemote(player.togglePlayPause);
    }
    notifyListeners();
  }

  /// The local drift correction, run on a timer while the room is playing.
  ///
  /// Three bands, because the right correction depends on how wrong things are.
  /// Under [nudgeThresholdMs] nothing is done -- chasing tens of milliseconds
  /// means changing the rate constantly for a difference nobody can hear. Up to
  /// [seekThresholdMs] the rate is nudged, which pulls the playhead back over a
  /// few seconds without a click. Beyond that the guest has really fallen behind
  /// (a stall, a lost buffer) and seeking is the only thing that catches up.
  Future<void> _correctDrift() async {
    if (_correcting || !isGuest || _transport == null) return;
    if (!_anchorPlaying || !player.isPlaying) return;

    _correcting = true;
    try {
      final drift = player.position.inMilliseconds - _expectedPositionMs(_now());
      _lastDriftMs = drift;

      if (drift.abs() > seekThresholdMs) {
        await player.applyRemote(
          () => player.seek(
            Duration(milliseconds: _expectedPositionMs(_now())),
          ),
        );
        await player.audioService.setSpeed(1.0);
      } else if (drift.abs() > nudgeThresholdMs) {
        // Ahead of the room means slowing down, hence the minus.
        final rate = (1 - drift / _nudgeScale).clamp(_minRate, _maxRate);
        await player.audioService.setSpeed(rate);
      } else {
        await player.audioService.setSpeed(1.0);
      }
    } finally {
      _correcting = false;
    }
  }

  /// Ask the host for a track this device does not have.
  ///
  /// Only worth trying when the room is local: the file is served from the host's
  /// own HTTP server, which a guest on another network cannot reach.
  Future<WavelySong?> _fetchFromHost(TrackRef ref) async {
    final base = _roomUri;
    final transport = _transport;
    if (base == null || transport == null) return null;

    _set('Fetching “${ref.title}” from the host…');
    notifyListeners();
    return _audioCache.fetch(
      base: base,
      roomCode: transport.roomCode,
      ref: ref,
    );
  }

  /// Serve a track to a guest that asked for it, from this device's own files.
  ///
  /// Resolved out of the loaded queue rather than the whole library: a guest only
  /// ever needs what the room is playing, and the queue is the one list the
  /// player already holds.
  Future<RoomSharedFile?> _shareTrack(String songId) async {
    for (final song in player.queue) {
      if (song.id != songId) continue;
      final file = File(song.uri);
      if (!await file.exists()) return null;
      return RoomSharedFile(
        bytes: file.openRead(),
        length: await file.length(),
        contentType: _contentTypeFor(song.uri),
      );
    }
    return null;
  }

  /// Best-effort container type from the file's extension.
  ///
  /// The guest needs it for two things: to name the downloaded file so the
  /// player picks the right extractor, and to satisfy a strict content-type check
  /// on a player that inspects it.
  static String _contentTypeFor(String path) {
    final dot = path.lastIndexOf('.');
    final extension = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
    return switch (extension) {
      'mp3' => 'audio/mpeg',
      'flac' => 'audio/flac',
      'm4a' || 'mp4' || 'aac' => 'audio/mp4',
      'ogg' || 'oga' => 'audio/ogg',
      'opus' => 'audio/opus',
      'wav' => 'audio/wav',
      _ => 'application/octet-stream',
    };
  }
}
