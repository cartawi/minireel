import 'package:flutter_test/flutter_test.dart';
import 'package:minireel/app/app_controller.dart';
import 'package:minireel/data/repositories/drama_repository.dart';
import 'package:minireel/data/sources/source_adapter.dart';
import 'package:minireel/playback/buffered_playback_engine.dart';
import 'package:minireel/playback/playback_session.dart';

import 'support/fakes.dart';

void main() {
  testWidgets(
    'the session resolves once, warms media, promotes it and trims in the background',
    (tester) async {
      final store = MemoryStore();
      final resolved = <int>[];
      final source = FakeSource()
        ..resolve = (episode, _) async {
          resolved.add(episode.index);
          return mediaFor(episode);
        };
      final app = AppController(
        store,
        DramaRepository(SourceRegistry([source]), store),
      );
      await app.initialize();
      final players = <FakeEngine>[];
      final engine = BufferedPlaybackEngine((_) {
        final player = FakeEngine();
        players.add(player);
        return player;
      });
      final session = PlaybackSession(
        app: app,
        engine: engine,
        drama: sampleDrama,
      );
      try {
        await session.initialize();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(resolved, [1, 2]);
        expect(engine.preloadedEpisodeId, sampleEpisodes[1].id);
        expect(players[1].opened, ['/2.mp4']);
        expect(players[1].state.value.playing, isFalse);
        await session.next();
        expect(resolved, [1, 2]);
        expect(engine.activeEngine, same(players[1]));
        expect(players[1].opened, ['/2.mp4']);
        expect(session.playing, isTrue);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(engine.preloadedEpisodeId, sampleEpisodes[2].id);
        session.hold('background');
        await tester.pump();
        expect(engine.preloadedEpisodeId, isNull);
        expect(session.playing, isFalse);
        expect(players.where((player) => !player.disposed), hasLength(1));
        await tester.pump(const Duration(seconds: 1));
        expect(resolved, [1, 2, 3]);
        session.release('background');
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(session.playing, isTrue);
        expect(resolved, [1, 2, 3, 3]);
        expect(engine.preloadedEpisodeId, sampleEpisodes[2].id);
      } finally {
        // Dispose timers before testWidgets verifies its timer invariants.
        await session.close();
        session.dispose();
        app.repository.dispose();
        app.dispose();
      }
    },
  );
}
