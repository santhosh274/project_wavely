import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/core/services/media_item_mapper.dart';

const _withArt = WavelySong(
  id: '42',
  title: 'Paper Lanterns',
  artist: 'Vela',
  album: 'Harbour Lights',
  duration: Duration(minutes: 3, seconds: 12),
  uri: 'content://media/external/audio/media/42',
  albumArtUri: 'content://media/external/audio/albumart/100',
  albumId: 100,
);

const _withoutArt = WavelySong(
  id: '43',
  title: 'Low Tide',
  artist: 'Vela',
  album: 'Harbour Lights',
  duration: Duration(minutes: 2, seconds: 58),
  uri: 'content://media/external/audio/media/43',
);

void main() {
  group('mediaItemFor', () {
    test('carries what a media notification has to show', () {
      final item = mediaItemFor(_withArt);

      expect(item.id, '42');
      expect(item.title, 'Paper Lanterns');
      expect(item.artist, 'Vela');
      expect(item.album, 'Harbour Lights');
      expect(item.duration, const Duration(minutes: 3, seconds: 12));
      expect(
        item.artUri.toString(),
        'content://media/external/audio/albumart/100',
      );
      expect(item.extras, {
        'albumId': 100,
        // Opts the native loader into its fast thumbnail path; without it
        // the cover loads slowly or not at all.
        'loadThumbnailUri': 'content://media/external/audio/albumart/100',
      });
    });

    test('a http cover never asks for the content fast path', () {
      final item = mediaItemFor(
        _withArt.copyWith(albumArtUri: 'https://example.com/cover.jpg'),
      );

      expect(item.extras, {'albumId': 100});
    });

    test('a track with no cover still produces a usable item', () {
      final item = mediaItemFor(_withoutArt);

      // Left out rather than set to something unopenable: the notification
      // falls back to the app icon instead of failing to draw.
      expect(item.artUri, isNull);
      expect(item.extras, isNull);
      expect(item.id, '43');
    });
  });

  group('songIdOf', () {
    test('reads the id out of a media item', () {
      expect(songIdOf(mediaItemFor(_withArt)), '42');
    });

    test('accepts a plain id, for a source loaded without a media item', () {
      expect(songIdOf('42'), '42');
    });

    test('has nothing to say about a tag that is neither', () {
      expect(songIdOf(null), isNull);
      expect(songIdOf(7), isNull);
    });
  });
}
