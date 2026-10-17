import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wavely/app/wavely_providers.dart';
import 'package:wavely/features/library/controllers/library_controller.dart';
import 'package:wavely/features/navigation/controllers/shell_controller.dart';
import 'package:wavely/features/navigation/presentation/screens/main_navigation_screen.dart'
    show ShellTabs;
import 'package:wavely/features/player/controllers/player_controller.dart';
import 'package:wavely/features/room/controllers/room_controller.dart';
import 'package:wavely/features/room/services/local_network_permission.dart';
import 'package:wavely/features/room/services/local_room_transport.dart'
    show LocalRoomRoutes;
import 'package:wavely/main.dart';

import 'support/fake_artwork_service.dart';
import 'support/fake_audio_engine.dart';
import 'support/fake_local_network_permission.dart';
import 'support/fake_media_service.dart';
import 'support/fake_room_device.dart';
import 'support/fake_room_transport.dart';
import 'support/memory_playback_store.dart';

void main() {
  late FakeAudioEngine engine;
  late FakeLocalMediaService media;
  late FakeArtworkService artwork;
  late MemoryPlaybackStateStore store;
  late FakeRoomTransportFactory roomFactory;

  // Live controllers, read back out of the provider tree once it is mounted.
  // The tree owns their lifetime, so nothing is disposed by hand here.
  late LibraryController library;
  late PlayerController player;
  late RoomController room;
  late ShellController shell;

  setUp(() {
    engine = FakeAudioEngine();
    media = FakeLocalMediaService(libraryFixture());
    artwork = FakeArtworkService();
    store = MemoryPlaybackStateStore();
    roomFactory = FakeRoomTransportFactory();
  });

  /// Mount the app on the *real* provider wiring -- the same function `main()`
  /// uses -- with the fakes substituted, so the test covers the wiring and not a
  /// hand-copied version of it.
  Future<void> pumpApp(
    WidgetTester tester, {
    LocalNetworkPermission? localNetwork,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: wavelyProviders(
          mediaService: media,
          audioService: engine,
          artworkService: artwork,
          stateStore: store,
          roomTransportFactory: roomFactory,
          localNetworkPermission: localNetwork,
        ),
        child: const WavelyApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final root = tester.element(find.byType(WavelyApp));
    library = root.read<LibraryController>();
    player = root.read<PlayerController>();
    room = root.read<RoomController>();
    shell = root.read<ShellController>();
  }

  /// Mount the app, play the fixture's first track, and open the expanded
  /// player -- the only place a room can be started from.
  Future<void> openPlayer(WidgetTester tester) async {
    await pumpApp(tester);
    await player.playTrack(
      library.allSongs.first,
      queueContext: library.allSongs,
      queueTitle: 'All Songs',
    );
    shell.selectTab(ShellTabs.player);
    await tester.pumpAndSettle();
  }

  /// Open the room sheet the way a user does: the control beside the overflow
  /// menu, then the sheet.
  Future<void> openRoomSheet(WidgetTester tester) async {
    await openPlayer(tester);
    await tester.tap(find.byIcon(CupertinoIcons.person_2));
    await tester.pumpAndSettle();
  }

  group('local network permission', () {
    testWidgets('launching the app asks for it once, like the media permission', (
      tester,
    ) async {
      final permission = FakeLocalNetworkPermission();

      await pumpApp(tester, localNetwork: permission);

      expect(permission.requests, 1);
    });

    testWidgets('a room opening asks through the same seam', (tester) async {
      final permission = FakeLocalNetworkPermission();

      await pumpApp(tester, localNetwork: permission);
      expect(permission.requests, 1);

      await room.startRoom();

      // Once at launch, and again for the room: the second ask is what lets a
      // permission granted after launch be picked up without a restart.
      expect(permission.requests, 2);
      expect(room.isActive, isTrue);

      // Left here rather than left open: the room's beat timer is periodic, and
      // one still pending when the tree goes away fails the test.
      await room.leave();
    });
  });

  group('listening room', () {
    testWidgets('the expanded player offers one', (tester) async {
      await openPlayer(tester);

      expect(find.byIcon(CupertinoIcons.person_2), findsOneWidget);

      await tester.tap(find.byIcon(CupertinoIcons.person_2));
      await tester.pumpAndSettle();

      expect(find.text('Listen together'), findsOneWidget);
      expect(find.text('Start a room'), findsOneWidget);
      expect(find.text('Join'), findsOneWidget);
      // The Wi-Fi requirement is stated where the decision is made, not after a
      // join silently fails.
      expect(find.textContaining('Same Wi-Fi'), findsOneWidget);
    });

    testWidgets('starting one shows the code a guest has to type', (
      tester,
    ) async {
      await openRoomSheet(tester);

      await tester.tap(find.text('Start a room'));
      await tester.pumpAndSettle();

      expect(room.isHost, isTrue);
      expect(find.text('TEST01'), findsOneWidget);
      expect(find.text('ROOM CODE'), findsOneWidget);
      // The two halves of a hand-typed invitation, and then the link, which is
      // both of them in one piece: what the guest can read out, and what they
      // can simply be sent.
      expect(find.text('ADDRESS'), findsOneWidget);
      final selectable = tester.widgetList<SelectableText>(
        find.byType(SelectableText),
      );
      expect(selectable.first.data, '${room.joinUri!.host}:${room.joinUri!.port}');
      expect(selectable.last.data, room.joinUri.toString());
      expect(find.text('Copy link'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Close the room'), findsOneWidget);
      // A room with nobody in it says so instead of showing an empty list.
      expect(find.textContaining('(you)'), findsOneWidget);
      expect(find.textContaining('Nobody else yet'), findsOneWidget);
    });

    testWidgets('a guest joining appears on the host\'s screen', (tester) async {
      await openRoomSheet(tester);
      await tester.tap(find.text('Start a room'));
      await tester.pumpAndSettle();

      // A second phone, standing in for another device in the room.
      final guest = RoomTestDevice(
        factory: roomFactory,
        displayName: 'Priya',
      );
      addTearDown(guest.dispose);
      await guest.room.joinRoom(roomFactory.hostUri.toString());
      await tester.pumpAndSettle();

      expect(find.text('Priya'), findsOneWidget);
      expect(find.textContaining('2 of 6'), findsOneWidget);
      expect(find.text('HOST'), findsOneWidget);

      // Left here rather than only in a teardown: the room's clock and drift
      // timers are periodic, and one still pending when the tree goes away
      // fails the test -- and tearDowns run after that check, not before it.
      await guest.room.leave();
    });

    testWidgets('the host\'s track is playing on the guest', (tester) async {
      await openRoomSheet(tester);
      await tester.tap(find.text('Start a room'));
      await tester.pumpAndSettle();

      // The guest holds the same songs the host's library does, so the room's
      // matching has something to find.
      final guest = RoomTestDevice(
        factory: roomFactory,
        library: library.allSongs,
        displayName: 'Priya',
      );
      addTearDown(guest.dispose);
      await guest.room.joinRoom(roomFactory.hostUri.toString());
      await tester.pumpAndSettle();

      await player.skipNext();
      await tester.pumpAndSettle();

      expect(guest.player.currentSong?.id, player.currentSong?.id);
      expect(guest.player.isPlaying, isTrue);
      // And the guest is not allowed to steer: the host is the single writer.
      expect(guest.room.controlsLocked, isTrue);

      await guest.room.leave();
    });

    testWidgets('a room banner says who is driving, and opens the room', (
      tester,
    ) async {
      await openRoomSheet(tester);
      await tester.tap(find.text('Start a room'));
      await tester.pumpAndSettle();

      // Closed, so the banner is what is left on the player.
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();

      expect(find.textContaining('Room TEST01'), findsOneWidget);
      expect(find.textContaining('1 listening'), findsOneWidget);

      await tester.tap(find.textContaining('Room TEST01'));
      await tester.pumpAndSettle();
      expect(find.text('Listen together'), findsOneWidget);

      // The invite card puts the button below the fold on a phone-sized screen,
      // so it has to be scrolled to -- exactly as a user would.
      await tester.ensureVisible(find.text('Close the room'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close the room'));
      await tester.pumpAndSettle();

      expect(room.isActive, isFalse);
      expect(find.textContaining('Room TEST01'), findsNothing);
    });

    testWidgets('a link that is not a room link says so', (tester) async {
      await openRoomSheet(tester);

      await tester.enterText(
        find.byType(TextField).first,
        'https://example.com/nope',
      );
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      expect(find.textContaining('room link'), findsOneWidget);
      expect(room.isActive, isFalse);
      expect(roomFactory.joinedUris, isEmpty);
    });

    testWidgets('an address and a code typed by hand get a guest in', (
      tester,
    ) async {
      // A room to dial: the host's half of the pair, with nobody attached to it
      // yet, so what is exercised is the guest's own side of the sheet.
      final host = await roomFactory.host();
      addTearDown(host.close);

      await openRoomSheet(tester);

      final fields = find.byType(TextField);
      await tester.enterText(fields.first, '127.0.0.1:9');
      // As the keyboard offers it, not as the host shows it.
      await tester.enterText(fields.last, 'test01');
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      final dialled = roomFactory.joinedUris.single;
      // Completed to the route the host answers on, with the code in the case
      // the host uses.
      expect(dialled.path, LocalRoomRoutes.socket);
      expect(dialled.queryParameters['code'], 'TEST01');
      expect(room.isGuest, isTrue);
      // Once on the banner and once in the sheet's own subtitle.
      expect(find.textContaining('Following'), findsWidgets);

      await room.leave();
      await tester.pumpAndSettle();
    });
  });
}
