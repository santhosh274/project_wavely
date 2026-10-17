/// Somebody in the room, as shown in its member list.
class RoomMember {
  final String id;
  final String name;
  final bool isHost;

  /// Whether this guest has said it does not have the current track.
  ///
  /// Surfaced on the host's screen so a silent phone is explained rather than
  /// mysterious: the host can see that it is a missing file, not a broken link.
  final bool missingCurrentTrack;

  const RoomMember({
    required this.id,
    required this.name,
    required this.isHost,
    this.missingCurrentTrack = false,
  });

  RoomMember copyWith({String? name, bool? missingCurrentTrack}) => RoomMember(
    id: id,
    name: name ?? this.name,
    isHost: isHost,
    missingCurrentTrack: missingCurrentTrack ?? this.missingCurrentTrack,
  );
}
