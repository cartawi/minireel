import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:minireel/data/repositories/drama_repository.dart';
import 'package:minireel/data/sources/source_adapter.dart';
import 'package:minireel/domain/models/drama.dart';

import 'support/fakes.dart';

void main() {
  test(
    'clearing cache during manual continuation ignores late pages',
    () async {
      final store = MemoryStore();
      final started = Completer<void>();
      final pending = Completer<List<Drama>>();
      final source = FakeSource()
        ..catalogLoader = (channel, page) async {
          if (channel != DramaChannel.real) return [];
          if (page == 1) return [sampleDrama, sampleDrama];
          started.complete();
          return pending.future;
        };
      final repo = DramaRepository(SourceRegistry([source]), store);
      addTearDown(repo.dispose);
      final update = repo.updateCatalog();
      await started.future;
      expect(repo.refreshing, true);
      await repo.clearCache();
      pending.complete([sampleDrama]);
      await update;
      expect(repo.catalog, isEmpty);
      expect(store.catalog, isEmpty);
      expect(repo.lastRefresh, isNull);
      expect(repo.refreshing, false);
    },
  );

  test(
    'a failed refresh keeps cached catalog and independent favorites',
    () async {
      final store = MemoryStore()
        ..catalog[sampleDrama.id] = sampleDrama
        ..favorites[sampleDrama.id] = sampleDrama;
      final source = FakeSource()..failCatalog = true;
      final repo = DramaRepository(SourceRegistry([source]), store);
      addTearDown(repo.dispose);
      await repo.loadCache();
      await repo.refresh();
      expect(repo.catalog.single.id, sampleDrama.id);
      expect(repo.errors.length, 4);
      expect(repo.refreshing, false);
      await repo.clearCache();
      expect(repo.catalog, isEmpty);
      expect(store.favorites, isNotEmpty);
    },
  );

  test(
    'partial category failure retains old rows while other categories update',
    () async {
      final store = MemoryStore()..catalog[sampleDrama.id] = sampleDrama;
      final source = FakeSource();
      source.catalogLoader = (channel, _) async => channel == DramaChannel.real
          ? [
              sampleDrama,
              const Drama(
                id: 'test:200',
                source: 'test',
                sourceId: '200',
                title: '新剧',
              ),
            ]
          : [];
      final repo = DramaRepository(SourceRegistry([source]), store);
      addTearDown(repo.dispose);
      await repo.loadCache();
      await repo.refresh();
      expect(repo.catalog.length, 2);
      await repo.loadMore(channel: DramaChannel.real);
      expect(repo.catalog.length, 2);
      expect(repo.hasMoreFor(DramaChannel.real), false);
    },
  );
}
