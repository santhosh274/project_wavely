import 'dart:convert';

import 'track_ref.dart';

/// Everything two devices in a room say to each other.
///
/// One frame per event, JSON encoded, with a version and a `type` tag so a peer
/// on an older or newer build can ignore what it does not understand instead of
/// failing. Every frame is small -- the largest is a queue of [TrackRef]s -- and
/// they are sent only on real events. Nothing here is periodic except the clock
/// exchange and the re-anchor beat.
///
/// The important design decision is that a start carries an **absolute host
/// timestamp** rather than meaning "play as soon as you read this". A frame that
/// says "play now" is unsynchronised by construction: by the time it arrives,
/// "now" is a different moment on every device.
sealed class RoomMessage {
  const RoomMessage();

  /// Bumped when a frame's shape changes incompatibly.
  static const int protocolVersion = 1;

  /// The discriminator written into the JSON.
  String get type;

  /// The frame's own fields, without the envelope.
  Map<String, Object?> payload();

  Map<String, Object?> toJson() => {
    'v': protocolVersion,
    'type': type,
    ...payload(),
  };

  /// Decode a frame, or null when the text is not one this build understands.
  ///
  /// Never throws: this is the boundary where another device's bytes enter the
  /// app, and a malformed frame has to be dropped rather than allowed to tear
  /// down the room.
  static RoomMessage? tryParse(String raw) {
    final Object? decoded;
    try {
      decoded = _decodeJson(raw);
    } on Object {
      return null;
    }
    if (decoded is! Map) return null;

    final type = decoded['type'];
    if (type is! String) return null;

    switch (type) {
      case HelloMessage.typeName:
        return HelloMessage.tryParse(decoded);
      case TimeRequestMessage.typeName:
        return TimeRequestMessage.tryParse(decoded);
      case TimeReplyMessage.typeName:
        return TimeReplyMessage.tryParse(decoded);
      case StartMessage.typeName:
        return StartMessage.tryParse(decoded);
      case TransportMessage.typeName:
        return TransportMessage.tryParse(decoded);
      case SyncMessage.typeName:
        return SyncMessage.tryParse(decoded);
      case MissingTrackMessage.typeName:
        return MissingTrackMessage.tryParse(decoded);
      case NoticeMessage.typeName:
        return NoticeMessage.tryParse(decoded);
      default:
        // An unknown frame from a newer peer is ignored, not an error.
        return null;
    }
  }
}

/// Announced by every device as soon as it joins, so the member list has names.
class HelloMessage extends RoomMessage {
  static const String typeName = 'hello';

  /// What to show for this device in the member list.
  final String name;

  /// Whether the sender is the room's host.
  final bool isHost;

  const HelloMessage({required this.name, required this.isHost});

  @override
  String get type => typeName;

  @override
  Map<String, Object?> payload() => {'name': name, 'isHost': isHost};

  static HelloMessage? tryParse(Map<Object?, Object?> json) {
    final name = json['name'];
    return HelloMessage(
      name: name is String && name.isNotEmpty ? name : 'Listener',
      isHost: json['isHost'] == true,
    );
  }
}

/// First half of the clock exchange: "what time do you think it is?"
class TimeRequestMessage extends RoomMessage {
  static const String typeName = 'ping';

  final int seq;

  /// The sender's clock when the frame left.
  final int clientEpochMs;

  const TimeRequestMessage({required this.seq, required this.clientEpochMs});

  @override
  String get type => typeName;

  @override
  Map<String, Object?> payload() => {
    'seq': seq,
    'clientEpochMs': clientEpochMs,
  };

  static TimeRequestMessage? tryParse(Map<Object?, Object?> json) {
    final seq = json['seq'];
    final clientEpochMs = json['clientEpochMs'];
    if (seq is! int || clientEpochMs is! int) return null;
    return TimeRequestMessage(seq: seq, clientEpochMs: clientEpochMs);
  }
}

/// Second half of the clock exchange. The host echoes the client's stamps back
/// with its own two, which is what lets the client solve for the offset and the
/// round trip without either device trusting the other's clock to be correct.
class TimeReplyMessage extends RoomMessage {
  static const String typeName = 'pong';

  final int seq;

  /// Echoed, so the client can pair the reply with the request it sent.
  final int clientEpochMs;

  /// The host's clock when the request arrived.
  final int hostEpochMs;

  /// The host's clock when the reply left.
  final int hostReplyMs;

  const TimeReplyMessage({
    required this.seq,
    required this.clientEpochMs,
    required this.hostEpochMs,
    required this.hostReplyMs,
  });

  @override
  String get type => typeName;

  @override
  Map<String, Object?> payload() => {
    'seq': seq,
    'clientEpochMs': clientEpochMs,
    'hostEpochMs': hostEpochMs,
    'hostReplyMs': hostReplyMs,
  };

  static TimeReplyMessage? tryParse(Map<Object?, Object?> json) {
    final seq = json['seq'];
    final clientEpochMs = json['clientEpochMs'];
    final hostEpochMs = json['hostEpochMs'];
    final hostReplyMs = json['hostReplyMs'];
    if (seq is! int ||
        clientEpochMs is! int ||
        hostEpochMs is! int ||
        hostReplyMs is! int) {
      return null;
    }
    return TimeReplyMessage(
      seq: seq,
      clientEpochMs: clientEpochMs,
      hostEpochMs: hostEpochMs,
      hostReplyMs: hostReplyMs,
    );
  }
}

/// "Be at [positionMs] of [track] when the host's clock reads [hostAtMs]."
///
/// [hostAtMs] is deliberately a little in the future -- roughly a quarter of a
/// second -- so the frame is already read and the decoder primed by the time the
/// moment arrives, on the devices whose clocks run fast as well as slow.
class StartMessage extends RoomMessage {
  static const String typeName = 'start';

  final TrackRef track;
  final int positionMs;
  final int hostAtMs;
  final bool playing;

  /// The host's queue, resolved per-track on each guest. Best effort: a guest
  /// omits what it does not have.
  final List<TrackRef> queue;

  const StartMessage({
    required this.track,
    required this.positionMs,
    required this.hostAtMs,
    required this.playing,
    this.queue = const [],
  });

  @override
  String get type => typeName;

  @override
  Map<String, Object?> payload() => {
    'track': track.toJson(),
    'positionMs': positionMs,
    'hostAtMs': hostAtMs,
    'playing': playing,
    'queue': [for (final ref in queue) ref.toJson()],
  };

  static StartMessage? tryParse(Map<Object?, Object?> json) {
    final track = TrackRef.tryParse(json['track']);
    if (track == null) return null;

    final positionMs = json['positionMs'];
    final hostAtMs = json['hostAtMs'];
    if (positionMs is! int || hostAtMs is! int) return null;

    final rawQueue = json['queue'];
    final queue = <TrackRef>[
      if (rawQueue is List)
        for (final entry in rawQueue) ?TrackRef.tryParse(entry),
    ];

    return StartMessage(
      track: track,
      positionMs: positionMs,
      hostAtMs: hostAtMs,
      playing: json['playing'] == true,
      queue: queue,
    );
  }
}

/// The three things a host can do to an already-loaded track.
enum TransportAction { play, pause, seek }

/// Play, pause or seek, leaving the current track alone.
class TransportMessage extends RoomMessage {
  static const String typeName = 'transport';

  final TransportAction action;
  final int positionMs;
  final int hostAtMs;

  const TransportMessage({
    required this.action,
    required this.hostAtMs,
    this.positionMs = 0,
  });

  @override
  String get type => typeName;

  @override
  Map<String, Object?> payload() => {
    'action': action.name,
    'positionMs': positionMs,
    'hostAtMs': hostAtMs,
  };

  static TransportMessage? tryParse(Map<Object?, Object?> json) {
    final action = json['action'];
    final hostAtMs = json['hostAtMs'];
    if (action is! String || hostAtMs is! int) return null;

    TransportAction? parsed;
    for (final candidate in TransportAction.values) {
      if (candidate.name == action) parsed = candidate;
    }
    if (parsed == null) return null;

    final positionMs = json['positionMs'];
    return TransportMessage(
      action: parsed,
      hostAtMs: hostAtMs,
      positionMs: positionMs is int ? positionMs : 0,
    );
  }
}

/// A periodic re-anchor from the host.
///
/// Drift correction handles a guest that falls behind, but it can only correct
/// toward the position it was told about; without a fresh anchor the whole room
/// slowly follows one guest's accumulating error. The beat is slow -- every few
/// seconds -- because the correction between beats is entirely local.
class SyncMessage extends RoomMessage {
  static const String typeName = 'sync';

  final int positionMs;
  final int hostAtMs;
  final bool playing;

  const SyncMessage({
    required this.positionMs,
    required this.hostAtMs,
    required this.playing,
  });

  @override
  String get type => typeName;

  @override
  Map<String, Object?> payload() => {
    'positionMs': positionMs,
    'hostAtMs': hostAtMs,
    'playing': playing,
  };

  static SyncMessage? tryParse(Map<Object?, Object?> json) {
    final positionMs = json['positionMs'];
    final hostAtMs = json['hostAtMs'];
    if (positionMs is! int || hostAtMs is! int) return null;
    return SyncMessage(
      positionMs: positionMs,
      hostAtMs: hostAtMs,
      playing: json['playing'] == true,
    );
  }
}

/// "I do not have that recording."
///
/// Sent so the host can say so in the room instead of wondering why one phone is
/// silent, and so a track the host is happy to share can be offered as a file.
class MissingTrackMessage extends RoomMessage {
  static const String typeName = 'missing';

  final String fingerprint;
  final String hostSongId;

  const MissingTrackMessage({
    required this.fingerprint,
    required this.hostSongId,
  });

  @override
  String get type => typeName;

  @override
  Map<String, Object?> payload() => {
    'fingerprint': fingerprint,
    'hostSongId': hostSongId,
  };

  static MissingTrackMessage? tryParse(Map<Object?, Object?> json) {
    final fingerprint = json['fingerprint'];
    final hostSongId = json['hostSongId'];
    if (fingerprint is! String || hostSongId is! String) return null;
    return MissingTrackMessage(
      fingerprint: fingerprint,
      hostSongId: hostSongId,
    );
  }
}

/// A human-readable line for the room's status area.
class NoticeMessage extends RoomMessage {
  static const String typeName = 'notice';

  final String text;

  const NoticeMessage(this.text);

  @override
  String get type => typeName;

  @override
  Map<String, Object?> payload() => {'text': text};

  static NoticeMessage? tryParse(Map<Object?, Object?> json) {
    final text = json['text'];
    if (text is! String) return null;
    return NoticeMessage(text);
  }
}

/// Decoding is isolated so the parser can be swapped or instrumented in one
/// place rather than sprinkled through the frame classes.
Object? _decodeJson(String raw) => jsonDecode(raw);
