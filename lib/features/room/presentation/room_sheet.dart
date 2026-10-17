import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wavely/core/theme/ios27_colors.dart';
import 'package:wavely/core/widgets/ambient_background.dart';
import 'package:wavely/core/widgets/glass_button.dart';
import 'package:wavely/core/widgets/glass_container.dart';
import 'package:wavely/features/player/controllers/player_controller.dart';
import 'package:wavely/features/room/controllers/room_controller.dart';
import 'package:wavely/features/room/models/room_member.dart';
import 'package:wavely/features/room/services/local_room_transport.dart'
    show LocalRoomRoutes;

/// The listening room, as a sheet.
///
/// One sheet for every state of the room, because the states are one flow: not
/// in a room, hosting one, or following one. Splitting them would mean three
/// places that all have to agree about what "the room" means, and the sheet is
/// the only thing in the app that does not play music -- it only shows who is
/// here and hands over the link.
class RoomSheet extends StatefulWidget {
  const RoomSheet({super.key});

  /// Open the sheet over the current screen.
  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const RoomSheet(),
  );

  @override
  State<RoomSheet> createState() => _RoomSheetState();
}

class _RoomSheetState extends State<RoomSheet> {
  final TextEditingController _linkController = TextEditingController();

  /// The code, for a guest that was given the address rather than the link.
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _linkController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = context.watch<RoomController>();
    final player = context.watch<PlayerController>();

    return FractionallySizedBox(
      heightFactor: 0.78,
      child: AmbientBackground(
        washPrimary: player.ambientPrimary,
        washSecondary: player.ambientSecondary,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 12.0),
              Container(
                width: 40.0,
                height: 4.0,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
              const SizedBox(height: 16.0),
              const Text(
                'Listen together',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6.0),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Text(
                  _subtitle(room),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13.0,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 18.0),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20.0, 0.0, 20.0, 20.0),
                  child: room.isActive
                      ? _ActiveRoom(room: room)
                      : _RoomLobby(
                          linkController: _linkController,
                          codeController: _codeController,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A line under the title that says what the room is, in the state it is in.
  ///
  /// States the Wi-Fi requirement once, where the user is deciding, rather than
  /// letting them find out when the join fails -- two phones on different
  /// networks simply cannot reach each other, and there is no server in the
  /// middle to fix that yet.
  static String _subtitle(RoomController room) {
    if (room.isHost) {
      return 'Everyone on the same Wi-Fi plays their own copy, in step. Send '
          'them the link, or read out the address and the code.';
    }
    if (room.isGuest) return 'Following ${room.hostName ?? 'the host'}';
    return 'Play one song on every phone in the room. Same Wi-Fi, up to five '
        'guests, no account and no server.';
  }
}

/// Not in a room yet: start one, or join one.
class _RoomLobby extends StatelessWidget {
  final TextEditingController linkController;
  final TextEditingController codeController;

  const _RoomLobby({
    required this.linkController,
    required this.codeController,
  });

  @override
  Widget build(BuildContext context) {
    final room = context.watch<RoomController>();

    return Column(
      children: [
        GlassButton(
          isPrimary: true,
          width: double.infinity,
          onTap: room.startRoom,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.person_2_fill, size: 18.0),
              SizedBox(width: 10.0),
              Text(
                'Start a room',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22.0),
        Row(
          children: [
            Expanded(child: _rule()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Text(
                'or join one',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 12.0,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Expanded(child: _rule()),
          ],
        ),
        const SizedBox(height: 18.0),
        GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: TextField(
            controller: linkController,
            style: const TextStyle(color: Colors.white, fontSize: 14.0),
            textInputAction: TextInputAction.go,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
            // Joining is the action the field exists for, so the keyboard's own
            // button does it rather than dismissing and making the user reach
            // for the button below.
            onSubmitted: (value) => _join(context, value, codeController.text),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: "Room link, or the host's address",
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 13.0,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10.0),
        GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: TextField(
            controller: codeController,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14.0,
              letterSpacing: 3.0,
            ),
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            // The code has a fixed shape, so the field enforces it instead of
            // accepting anything and failing later at the host. Six characters,
            // and only the ones a code can be made of.
            inputFormatters: [
              LengthLimitingTextInputFormatter(LocalRoomRoutes.codeLength),
              FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
            ],
            onSubmitted: (value) => _join(context, linkController.text, value),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: 'Room code, if you typed an address',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 13.0,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12.0),
        GlassButton(
          width: double.infinity,
          onTap: () =>
              _join(context, linkController.text, codeController.text),
          child: const Text(
            'Join',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15.0,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (room.statusMessage != null) ...[
          const SizedBox(height: 16.0),
          _StatusLine(text: room.statusMessage!),
        ],
      ],
    );
  }

  void _join(BuildContext context, String value, String code) {
    FocusScope.of(context).unfocus();
    context.read<RoomController>().joinRoom(value, code: code);
  }

  static Widget _rule() => Container(
    height: 1.0,
    color: Colors.white.withValues(alpha: 0.15),
  );
}

/// In a room: who is here, and how to get someone in.
class _ActiveRoom extends StatelessWidget {
  final RoomController room;

  const _ActiveRoom({required this.room});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (room.isHost) _InviteCard(room: room),
        if (room.isGuest) _SyncCard(room: room),
        const SizedBox(height: 18.0),
        _SectionLabel(
          'IN THE ROOM  ·  ${room.members.length} of '
          '${RoomController.maxMembers}',
        ),
        const SizedBox(height: 8.0),
        GlassContainer(
          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 6.0),
          child: Column(
            children: [
              for (final member in room.members)
                _MemberRow(member: member, isSelf: _isSelf(room, member)),
              if (room.members.length == 1)
                Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Text(
                    'Nobody else yet. Share the link to invite.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13.0,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (room.guestsMissingTrack) ...[
          const SizedBox(height: 12.0),
          Text(
            'A guest does not have this track yet.',
            style: TextStyle(
              color: IOS27Colors.amberGlow.withValues(alpha: 0.9),
              fontSize: 12.0,
            ),
          ),
        ],
        if (room.statusMessage != null) ...[
          const SizedBox(height: 14.0),
          _StatusLine(text: room.statusMessage!),
        ],
        const SizedBox(height: 20.0),
        GlassButton(
          width: double.infinity,
          onTap: room.leave,
          child: Text(
            room.isHost ? 'Close the room' : 'Leave the room',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15.0,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 10.0),
        Text(
          room.isHost
              ? 'Guests control nothing while you host: play, pause and seek '
                    'here and they follow.'
              : '${room.hostName ?? 'The host'} is driving. Your controls are '
                    'locked until you leave.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 12.0,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  /// "You" rather than the device name, which the user chose once and does not
  /// remember choosing.
  static bool _isSelf(RoomController room, RoomMember member) =>
      member.isHost ? room.isHost : room.isGuest && !member.isHost;
}

/// What a guest needs to get in, for the host: the code, the address it belongs
/// to, and the whole link the two of them make.
class _InviteCard extends StatelessWidget {
  final RoomController room;

  const _InviteCard({required this.room});

  @override
  Widget build(BuildContext context) {
    final uri = room.joinUri;
    final link = uri?.toString() ?? '';
    // The two halves a guest can type, as opposed to the whole link, which is
    // the one piece that can simply be sent.
    final address = uri == null ? '' : '${uri.host}:${uri.port}';

    return GlassContainer(
      padding: const EdgeInsets.fromLTRB(18.0, 16.0, 18.0, 14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('ROOM CODE'),
          const SizedBox(height: 6.0),
          Text(
            room.roomCode,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34.0,
              fontWeight: FontWeight.w700,
              // Spaced out because the code is read off one screen and typed
              // into another, and six characters the user is holding in their
              // head are easier to keep when they are not run together.
              letterSpacing: 10.0,
            ),
          ),
          const SizedBox(height: 12.0),
          const _SectionLabel('ADDRESS'),
          const SizedBox(height: 4.0),
          SelectableText(
            address,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8.0),
          SelectableText(
            link,
            maxLines: 2,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12.0,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12.0),
          Row(
            children: [
              Expanded(
                child: _InviteAction(
                  icon: CupertinoIcons.doc_on_clipboard,
                  label: 'Copy link',
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: link));
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Room link copied.')),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: _InviteAction(
                  icon: CupertinoIcons.share,
                  label: 'Share',
                  onTap: () => _share(context, link),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Future<void> _share(BuildContext context, String link) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: 'Join my Wavely room: $link',
          subject: 'Listen with me',
        ),
      );
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text('Sharing is not available here.')),
      );
    }
  }
}

class _InviteAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _InviteAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
      semanticLabel: label,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15.0, color: Colors.white),
          const SizedBox(width: 6.0),
          // Flexible rather than fixed: the two actions share the card's width
          // between them, and a label that runs out of room has to give way
          // rather than paint outside its own glass.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How well this guest is tracking the host.
///
/// Shown because the interesting failure of a synchronised room is not silence
/// but *lag*, and a number is the difference between "this is broken" and "this
/// link is slow". It is also the honest place to say that the clock has not been
/// measured yet, which is the one moment a guest may be slightly off.
class _SyncCard extends StatelessWidget {
  final RoomController room;

  const _SyncCard({required this.room});

  @override
  Widget build(BuildContext context) {
    final roundTrip = room.roundTripMs;
    final drift = room.lastDriftMs;
    final synced = roundTrip != null;

    return GlassContainer(
      padding: const EdgeInsets.fromLTRB(18.0, 16.0, 18.0, 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                synced ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.wifi,
                size: 16.0,
                color: synced
                    ? IOS27Colors.liquidEmerald
                    : IOS27Colors.amberGlow,
              ),
              const SizedBox(width: 8.0),
              // Flexible and ellipsised like every other row in this sheet: the
              // line is longer than it looks once a phone is set to a larger
              // text size, and a row that cannot shrink paints outside its own
              // glass.
              Flexible(
                child: Text(
                  synced
                      ? 'In sync with the host'
                      : 'Measuring the host’s clock…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          Text(
            [
              if (roundTrip != null) 'round trip ${roundTrip}ms',
              if (drift != null) 'off by ${drift}ms',
            ].join('  ·  '),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final RoomMember member;
  final bool isSelf;

  const _MemberRow({required this.member, required this.isSelf});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 9.0),
      child: Row(
        children: [
          Icon(
            member.isHost ? CupertinoIcons.person_2_fill : CupertinoIcons.person,
            size: 16.0,
            color: Colors.white.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 10.0),
          Expanded(
            child: Text(
              isSelf ? '${member.name} (you)' : member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14.0),
            ),
          ),
          if (member.isHost)
            Text(
              'HOST',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 10.0,
                letterSpacing: 1.0,
                fontWeight: FontWeight.w700,
              ),
            )
          else if (member.missingCurrentTrack)
            Icon(
              CupertinoIcons.music_note,
              size: 14.0,
              color: IOS27Colors.amberGlow.withValues(alpha: 0.9),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10.0,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w700,
        color: Colors.white.withValues(alpha: 0.5),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final String text;

  const _StatusLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.7),
          fontSize: 13.0,
          height: 1.3,
        ),
      ),
    );
  }
}
