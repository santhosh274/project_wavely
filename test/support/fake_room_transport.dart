import 'dart:async';

import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/features/room/models/room_message.dart';
import 'package:wavely/features/room/models/track_ref.dart';
import 'package:wavely/features/room/services/room_audio_cache.dart';
import 'package:wavely/features/room/services/room_transport.dart';

/// One end of a room link, wired straight to the other end in memory.
///
/// The room's behaviour -- who broadcasts what, when a guest applies it, how a
/// correction is chosen -- is decided by the controller, not by the socket. A
/// pair of these lets the controller be exercised end to end without binding a
/// server or waiting on a port, while `local_room_transport_test.dart` covers the
/// socket itself.
class FakeRoomTransport implements RoomTransport {
  FakeRoomTransport({
    required this.selfId,
    this.joinUri,
    this.roomCode = 'TEST01',
  });

  @override
  final String selfId;

  @override
  final Uri? joinUri;

  @override
  final String roomCode;

  /// The endpoints this one reaches: every guest for a host, the host for a
  /// guest. Two-way, because a host answers its peers and a guest answers only
  /// the host.
  final List<FakeRoomTransport> peers = [];

  final _incoming = StreamController<RoomEnvelope>.broadcast();
  final _joined = StreamController<String>.broadcast();
  final _left = StreamController<String>.broadcast();

  bool closed = false;

  /// Every frame this endpoint sent, in order. Kept so a test can assert on what
  /// the host broadcast, not only on what the other side made of it.
  final List<RoomMessage> sent = [];

  @override
  Stream<RoomEnvelope> get incoming => _incoming.stream;

  @override
  Stream<String> get peerJoined => _joined.stream;

  @override
  Stream<String> get peerLeft => _left.stream;

  @override
  void send(RoomMessage message, {String? to}) {
    sent.add(message);
    if (closed) return;
    for (final peer in peers) {
      if (peer.closed) continue;
      if (to != null && peer.selfId != to) continue;
      peer._incoming.add(RoomEnvelope(from: selfId, message: message));
    }
  }

  /// Connect two ends and tell each that the other arrived.
  static void link(FakeRoomTransport host, FakeRoomTransport guest) {
    host.peers.add(guest);
    guest.peers.add(host);
    host.announcePeer(guest.selfId);
    guest.announcePeer(host.selfId);
  }

  /// Deliver a join on a zero-duration timer rather than immediately, so the
  /// endpoint being joined has finished subscribing first. That ordering is what
  /// a socket gives for free: the dialling code returns, attaches its listener,
  /// and only then does the far side's join callback arrive. Without the delay a
  /// broadcast stream would drop the event into the void, and with it the start
  /// frame a host sends a guest that arrives mid-song.
  void announcePeer(String peerId) => Timer.run(() {
    if (!_joined.isClosed) _joined.add(peerId);
  });

  /// Deliver a departure.
  void dropPeer(String peerId) {
    if (!_left.isClosed) _left.add(peerId);
  }

  /// Hand a decoded frame in from `peerId`, standing in for a guest speaking.
  void deliver(RoomMessage message, {String from = 'guest1'}) {
    if (_incoming.isClosed) return;
    _incoming.add(RoomEnvelope(from: from, message: message));
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    // Closing one end of a socket is what tells the other end it has gone, so
    // each peer is told before this end goes quiet. Without it, a host leaving
    // would look to its guests like a room that merely stopped speaking.
    for (final peer in peers) {
      peer.dropPeer(selfId);
    }
    // The ends are shut down and *not* awaited. A `close()` future on a stream
    // that has ever delivered an event does not complete until the done event
    // has been delivered to its subscriptions, and a widget test's clock only
    // advances when the test pumps -- so awaiting it here deadlocks the test
    // that is leaving the room, which is the very thing this is standing in for
    // a socket to do. Nothing downstream needs the acknowledgement: after
    // `closed` is set, no further frame is delivered either way.
    unawaited(_incoming.close());
    unawaited(_joined.close());
    unawaited(_left.close());
  }
}

/// Opens fake rooms, remembering the host that later guests dial into.
class FakeRoomTransportFactory implements RoomTransportFactory {
  /// The link a host advertises. Loopback so a test that accidentally lets a
  /// real connection happen fails fast instead of reaching out to the network.
  Uri hostUri = Uri.parse('ws://127.0.0.1:9/wavely?code=TEST01');

  final List<FakeRoomTransport> hosts = [];
  final List<FakeRoomTransport> guests = [];
  final List<Uri> joinedUris = [];

  /// Set to make the next [host] or [join] throw, standing in for a device that
  /// cannot open a socket.
  Object? failWith;

  /// The endpoint a guest dials into: the last room opened through this factory.
  FakeRoomTransport? get lastHost => hosts.isEmpty ? null : hosts.last;

  @override
  Future<RoomTransport> host() async {
    final failure = failWith;
    if (failure != null) throw failure;
    final endpoint = FakeRoomTransport(
      selfId: 'host',
      joinUri: hostUri,
      roomCode: hostUri.queryParameters['code'] ?? 'TEST01',
    );
    hosts.add(endpoint);
    return endpoint;
  }

  @override
  Future<RoomTransport> join(Uri uri) async {
    joinedUris.add(uri);
    final failure = failWith;
    if (failure != null) throw failure;

    final hostEndpoint = lastHost;
    if (hostEndpoint == null) throw StateError('No host has been opened.');

    final guest = FakeRoomTransport(
      selfId: 'guest${guests.length + 1}',
      roomCode: uri.queryParameters['code'] ?? '',
    );
    guests.add(guest);
    FakeRoomTransport.link(hostEndpoint, guest);
    return guest;
  }
}

/// A room audio cache that answers from a script instead of the network.
class FakeRoomAudioCache extends RoomAudioCache {
  FakeRoomAudioCache([this.downloadable]);

  /// What a fetch hands back, or null for a host that cannot serve the track.
  final WavelySong? downloadable;

  final List<String> fetchedFingerprints = [];
  Uri? lastBase;
  String? lastRoomCode;

  @override
  Future<WavelySong?> fetch({
    required Uri base,
    required String roomCode,
    required TrackRef ref,
  }) async {
    lastBase = base;
    lastRoomCode = roomCode;
    fetchedFingerprints.add(ref.fingerprint);
    return downloadable;
  }
}
