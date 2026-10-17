import '../models/room_message.dart';

/// A frame that arrived, tagged with the peer that sent it.
class RoomEnvelope {
  final String from;
  final RoomMessage message;

  const RoomEnvelope({required this.from, required this.message});

  @override
  String toString() => 'RoomEnvelope($from: ${message.type})';
}

/// The link between one device and the rest of the room.
///
/// Deliberately the *same shape* on both sides. A host sends to everyone, or to
/// one peer; a guest sends to the host. Keeping one interface means
/// `RoomController` has a single code path for both roles -- and that a second
/// transport, such as a relayed room over a free realtime channel where "peers"
/// are presence joins and "send" is a publish, drops in without the controller
/// knowing it changed.
abstract interface class RoomTransport {
  /// This endpoint's id, unique inside the room. The host is always `host`.
  String get selfId;

  /// How a guest dials in. Null on a guest, which has already dialled.
  Uri? get joinUri;

  /// The short code a guest has to present to be let in.
  String get roomCode;

  /// Peers that joined after this endpoint did.
  Stream<String> get peerJoined;

  /// Peers that went away, including the host dropping.
  Stream<String> get peerLeft;

  Stream<RoomEnvelope> get incoming;

  /// Send a frame. [to] names one peer; null means everyone.
  void send(RoomMessage message, {String? to});

  /// Close the link.
  ///
  /// Callers await this, so an implementation has to complete it on the strength
  /// of its own resources being released -- and must not wait for a stream's
  /// done event to reach its listeners first. That acknowledgement arrives on a
  /// later turn of the event loop, and a widget test's fake clock only turns when
  /// the test pumps: an implementation that awaited it would deadlock the very
  /// test that is leaving the room.
  Future<void> close();
}

/// Opens one end of a room.
///
/// A factory rather than a constructor because the two ends do genuinely
/// different things -- one binds a server, the other dials -- and because the
/// tests need to hand the room controller a pair of transports wired directly
/// to each other, with no sockets in the picture.
abstract interface class RoomTransportFactory {
  Future<RoomTransport> host();

  Future<RoomTransport> join(Uri uri);
}
