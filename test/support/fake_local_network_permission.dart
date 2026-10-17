import 'package:wavely/features/room/services/local_network_permission.dart';

/// A [LocalNetworkPermission] that answers at once, and remembers being asked.
///
/// The real one raises a system dialog and talks to `permission_handler`, which
/// a unit test has no way to answer -- so the room is handed this instead, and
/// the permission is exercised through its answer rather than its dialog.
class FakeLocalNetworkPermission implements LocalNetworkPermission {
  FakeLocalNetworkPermission({this.granted = true});

  /// What [request] answers. False models a user who has refused for good.
  bool granted;

  /// How many times a room has asked. One per attempted room, and none unless
  /// the user asked for a room: the prompt must never appear on its own.
  int requests = 0;

  @override
  Future<bool> request() async {
    requests++;
    return granted;
  }
}
