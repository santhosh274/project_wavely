import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/room_message.dart';
import 'room_transport.dart';

/// A file the host is willing to hand over, for a guest that does not have the
/// track. Streamed rather than read into memory: a lossless rip can be tens of
/// megabytes, and holding one per guest would be the whole point of the exercise
/// thrown away.
class RoomSharedFile {
  final Stream<List<int>> bytes;
  final int length;
  final String contentType;

  const RoomSharedFile({
    required this.bytes,
    required this.length,
    required this.contentType,
  });
}

/// Finds the bytes of a song the host owns. Null when it cannot be served.
typedef RoomFileSource = Future<RoomSharedFile?> Function(String songId);

/// Creates the host's listening socket.
///
/// Injectable so a test can make the wider addresses fail and watch the room
/// fall back, rather than depending on what the machine running the tests
/// happens to allow.
typedef RoomServerBinder = Future<HttpServer> Function(
  InternetAddress address,
  int port,
);

/// The default [RoomServerBinder]: a plain wildcard-dialable server socket.
Future<HttpServer> _bindServerDefault(InternetAddress address, int port) =>
    HttpServer.bind(address, port);

/// Raised when the device will not let the host create the socket the room is
/// served from.
///
/// A local-network permission the user has refused, a VPN or firewall app
/// refusing the app's own sockets, or a network policy that blocks a wildcard
/// bind, is the usual cause. The message is written for the person holding the
/// phone: this is the one room failure they can actually do something about, so
/// it says what to do rather than naming an errno.
class RoomHostUnavailableException implements Exception {
  const RoomHostUnavailableException([this.cause]);

  /// The last socket error. Kept so a log can carry the platform detail;
  /// deliberately not part of the message shown to the user.
  final Object? cause;

  @override
  String toString() =>
      'the system would not let the app open a network socket. '
      'Allow Wavely local network access, and turn off any VPN or firewall '
      'app, then try again.';
}

/// The path a guest dials, and the path the audio is served from.
class LocalRoomRoutes {
  const LocalRoomRoutes._();

  static const String socket = '/wavely';
  static const String audio = '/wavely-audio';

  /// Characters a room code may use. `O`/`0` and `I`/`1` are left out because
  /// the code is meant to be read off one screen and typed into another, and
  /// those four are the pairs people get wrong.
  static const String codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static const int codeLength = 6;
}

/// A room carried over the local Wi-Fi, with no server anywhere.
///
/// The host binds an HTTP server on an ephemeral port and upgrades each guest's
/// connection to a WebSocket. That is the whole rendezvous: the guest is told an
/// address (`ws://192.168.1.24:51234/wavely?code=K7RW2M`) and dials it. No STUN,
/// no TURN, no signalling service, no internet, and no multicast permission --
/// which matters, because raw multicast on iOS needs an entitlement Apple grants
/// per provisioning profile, and a room code typed into a phone should not
/// require an application to Cupertino.
///
/// The star topology is the right shape here: at most five guests, so the host is
/// one socket per guest with no mesh to coordinate, and a message from any guest
/// reaches the rest in a single hop rather than five.
class LocalRoomTransportFactory implements RoomTransportFactory {
  /// The address to advertise in [RoomTransport.joinUri].
  ///
  /// Injectable because the tests dial `127.0.0.1`, and because a device with
  /// several interfaces (a VPN, a hotspot) can pick the wrong one to advertise.
  final String? advertisedHost;

  /// Where the host gets a file to serve, when a guest asks for one.
  final RoomFileSource? fileSource;

  /// How many guests one room holds besides its host.
  ///
  /// Handed in rather than repeated here: the room is what decides how big it
  /// is, and the transport is only what enforces it. Defaulted so a room opened
  /// without an opinion still has the cap.
  final int maxGuests;

  /// How the host's listening socket is created. Defaults to [HttpServer.bind].
  final RoomServerBinder binder;

  LocalRoomTransportFactory({
    this.advertisedHost,
    this.fileSource,
    this.maxGuests = 5,
    RoomServerBinder? binder,
  }) : binder = binder ?? _bindServerDefault;

  @override
  Future<RoomTransport> host() => _LanHost.start(
    binder: binder,
    advertisedHost: advertisedHost,
    fileSource: fileSource,
    maxGuests: maxGuests,
  );

  @override
  Future<RoomTransport> join(Uri uri) => _LanGuest.connect(uri);
}

/// A room code: fixed when one is supplied, random otherwise.
String _randomRoomCode([Random? random]) {
  final source = random ?? Random.secure();
  return List.generate(
    LocalRoomRoutes.codeLength,
    (_) => LocalRoomRoutes.codeAlphabet[source.nextInt(
      LocalRoomRoutes.codeAlphabet.length,
    )],
  ).join();
}

class _LanHost implements RoomTransport {
  final HttpServer _server;
  final String _roomCode;

  /// Live guests by peer id.
  final Map<String, WebSocket> _guests = {};

  final String _advertisedHost;
  final RoomFileSource? _fileSource;
  final int _maxGuests;

  final _incoming = StreamController<RoomEnvelope>.broadcast();
  final _joined = StreamController<String>.broadcast();
  final _left = StreamController<String>.broadcast();

  var _nextGuestNumber = 1;

  /// Set once [close] has run, so a socket callback that lands afterwards --
  /// which is the normal order: closing a socket is what makes it finish -- does
  /// not add to a stream that is already shut.
  var _closed = false;

  _LanHost._(
    this._server,
    this._roomCode,
    this._advertisedHost,
    this._fileSource,
    this._maxGuests,
  );

  static Future<RoomTransport> start({
    required RoomServerBinder binder,
    String? advertisedHost,
    RoomFileSource? fileSource,
    int maxGuests = 5,
  }) async {
    final (server, loopbackOnly) = await _bindRoomServer(binder);
    // The address handed to guests has to be one the server is actually
    // reachable on: a room that fell back to loopback and advertised a LAN
    // address would give its guests a link nobody can dial.
    final host =
        advertisedHost ??
        (loopbackOnly
            ? InternetAddress.loopbackIPv4.address
            : await _lanAddress());
    final transport = _LanHost._(
      server,
      _randomRoomCode(),
      host,
      fileSource,
      maxGuests,
    );
    server.listen(transport._handleRequest, onError: (_) {});
    return transport;
  }

  /// Create the room's listening socket, widest address first.
  ///
  /// `anyIPv4` is the first choice: the guest is handed the host's LAN address
  /// and dials an IPv4 socket. A device can still refuse it -- a VPN or firewall
  /// that blocks the app's own sockets rejects the bind outright, and some
  /// Android builds reject a wildcard bind for an app with no active network.
  /// A dual-stack `anyIPv6` also accepts IPv4 connections, so it is the next
  /// best thing, and loopback keeps a room usable on this machine when the
  /// network is what is being refused. Only when all three fail does the room
  /// give up, and then with a sentence the user can act on.
  static Future<(HttpServer, bool)> _bindRoomServer(
    RoomServerBinder binder,
  ) async {
    final attempts = <({InternetAddress address, bool loopback})>[
      (address: InternetAddress.anyIPv4, loopback: false),
      // v6Only is left at its default false, so this socket takes IPv4-mapped
      // guests too; it is ignored by the IPv4 binds.
      (address: InternetAddress.anyIPv6, loopback: false),
      (address: InternetAddress.loopbackIPv4, loopback: true),
    ];

    Object? lastError;
    for (final attempt in attempts) {
      try {
        final server = await binder(attempt.address, 0);
        return (server, attempt.loopback);
      } on Object catch (error) {
        lastError = error;
      }
    }
    throw RoomHostUnavailableException(lastError);
  }

  /// The device's own address on the network guests are on.
  ///
  /// Prefers a private-range address: a phone with a VPN or a hotspot up has
  /// several, and the one that reaches the room is never the public one.
  static Future<String> _lanAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (_isPrivateV4(address.address)) return address.address;
        }
      }
    } on Object {
      // A device with no network at all still has to be able to open a room:
      // falling back to loopback means two apps on the same machine can pair,
      // and the failure a user sees is an unreachable address rather than a
      // crash on the way in.
    }
    return InternetAddress.loopbackIPv4.address;
  }

  static bool _isPrivateV4(String address) {
    final parts = address.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final first = parts[0]!;
    final second = parts[1]!;
    if (first == 10) return true;
    if (first == 192 && second == 168) return true;
    if (first == 172 && second >= 16 && second <= 31) return true;
    return false;
  }

  @override
  String get selfId => 'host';

  @override
  Uri get joinUri => Uri(
    scheme: 'ws',
    host: _advertisedHost,
    port: _server.port,
    path: LocalRoomRoutes.socket,
    queryParameters: {'code': _roomCode},
  );

  @override
  String get roomCode => _roomCode;

  @override
  Stream<String> get peerJoined => _joined.stream;

  @override
  Stream<String> get peerLeft => _left.stream;

  @override
  Stream<RoomEnvelope> get incoming => _incoming.stream;

  @override
  void send(RoomMessage message, {String? to}) {
    final encoded = jsonEncode(message.toJson());
    if (to != null) {
      _sendToSocket(_guests[to], encoded);
      return;
    }
    for (final socket in _guests.values) {
      _sendToSocket(socket, encoded);
    }
  }

  void _sendToSocket(WebSocket? socket, String encoded) {
    if (socket == null) return;
    try {
      socket.add(encoded);
    } on Object {
      // A guest that vanished between the last message and this one is not an
      // error worth surfacing; its socket's onDone removes it.
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final code = request.uri.queryParameters['code'];
    final authorised = code == _roomCode;

    if (WebSocketTransformer.isUpgradeRequest(request)) {
      if (!authorised || request.uri.path != LocalRoomRoutes.socket) {
        await _reject(request, HttpStatus.forbidden);
        return;
      }
      if (_guests.length >= _maxGuests) {
        // Full. Refused before the upgrade rather than after it: a guest that is
        // let onto a socket only to be dropped cannot tell that apart from a
        // link that broke, and the room's own limit is nothing to do with the
        // network.
        await _reject(request, HttpStatus.serviceUnavailable);
        return;
      }
      await _acceptGuest(await WebSocketTransformer.upgrade(request));
      return;
    }

    if (request.uri.path == LocalRoomRoutes.audio) {
      if (!authorised) {
        await _reject(request, HttpStatus.forbidden);
        return;
      }
      await _serveAudio(request);
      return;
    }

    await _reject(request, HttpStatus.notFound);
  }

  static Future<void> _reject(HttpRequest request, int status) async {
    request.response.statusCode = status;
    await request.response.close();
  }

  Future<void> _acceptGuest(WebSocket socket) async {
    final peerId = 'g${_nextGuestNumber++}';
    _guests[peerId] = socket;
    _joined.add(peerId);

    socket.listen(
      (data) {
        if (data is! String) return;
        final message = RoomMessage.tryParse(data);
        if (message == null) return;
        _incoming.add(RoomEnvelope(from: peerId, message: message));
      },
      onDone: () => _reportGuestGone(peerId),
      onError: (_) => _reportGuestGone(peerId),
      cancelOnError: true,
    );
  }

  /// Hand a song's bytes to a guest that asked for them.
  Future<void> _serveAudio(HttpRequest request) async {
    final songId = request.uri.queryParameters['id'];
    final source = _fileSource;
    final file = songId == null || source == null
        ? null
        : await source(songId);

    if (file == null) {
      await _reject(request, HttpStatus.notFound);
      return;
    }

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.parse(file.contentType)
      ..headers.contentLength = file.length
      ..headers.set('x-wavely-bytes', file.length.toString());

    try {
      await request.response.addStream(file.bytes);
    } on Object {
      // The guest may have walked away mid-download; the response is simply
      // abandoned rather than treated as a room failure.
    }
    await request.response.close();
  }

  void _reportGuestGone(String peerId) {
    _guests.remove(peerId);
    if (_closed) return;
    _left.add(peerId);
  }

  @override
  Future<void> close() async {
    _closed = true;
    for (final socket in _guests.values) {
      await socket.close();
    }
    _guests.clear();
    await _server.close(force: true);
    // The three ends are shut down without waiting on their done futures: see
    // [RoomTransport.close] for why an implementation must not await them.
    unawaited(_incoming.close());
    unawaited(_joined.close());
    unawaited(_left.close());
  }
}

class _LanGuest implements RoomTransport {
  final WebSocket _socket;
  final String _roomCode;

  final _incoming = StreamController<RoomEnvelope>.broadcast();
  final _joined = StreamController<String>.broadcast();
  final _left = StreamController<String>.broadcast();

  _LanGuest._(this._socket, this._roomCode);

  static Future<RoomTransport> connect(Uri uri) async {
    final socket = await WebSocket.connect(uri.toString());
    final guest = _LanGuest._(socket, uri.queryParameters['code'] ?? '');

    socket.listen(
      (data) {
        if (data is! String || guest._closed) return;
        final message = RoomMessage.tryParse(data);
        if (message == null) return;
        // Everything a guest receives comes from the host: the topology is a
        // star, so there is no one else it could be.
        guest._incoming.add(RoomEnvelope(from: 'host', message: message));
      },
      // The socket finishing is how a guest finds out the host has gone. Once
      // this end has closed the room itself, there is nobody left to tell.
      onDone: () => guest._reportHostGone(),
      onError: (_) => guest._reportHostGone(),
      cancelOnError: false,
    );

    guest._joined.add('host');
    return guest;
  }

  var _closed = false;

  void _reportHostGone() {
    if (_closed) return;
    _left.add('host');
  }

  @override
  String get selfId => 'guest';

  @override
  Uri? get joinUri => null;

  @override
  String get roomCode => _roomCode;

  @override
  Stream<String> get peerJoined => _joined.stream;

  @override
  Stream<String> get peerLeft => _left.stream;

  @override
  Stream<RoomEnvelope> get incoming => _incoming.stream;

  @override
  void send(RoomMessage message, {String? to}) {
    try {
      _socket.add(jsonEncode(message.toJson()));
    } on Object {
      // As on the host: a dropped socket is reported through peerLeft, not by
      // throwing into the middle of a playback update.
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _socket.close();
    // As on the host: the streams are closed, not waited on.
    unawaited(_incoming.close());
    unawaited(_joined.close());
    unawaited(_left.close());
  }
}
