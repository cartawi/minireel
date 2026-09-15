import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/models/drama.dart';
import '../../domain/models/catalog_page.dart';
import '../../domain/models/playback_source.dart';
import '../../domain/models/discovery.dart';
import '../../core/network/app_http_client.dart';
import '../local/app_store.dart';
import '../sources/source_adapter.dart';

final class DramaRepository extends ChangeNotifier {
  DramaRepository(this.registry, this.store);

  final SourceRegistry registry;
  final AppStore store;
  final Map<String, Drama> _catalog = {};
  final Map<String, int> _pages = {};
  final Map<String, CatalogCursor> _cursors = {};
  Future<void> _catalogWrites = Future.value();
  int _successfulPages = 0;
  final Set<String> _exhausted = {};
  final Map<String, Set<String>> _previousPageIds = {};
  final Map<String, String> errors = {};
  CancelToken? _catalogToken;
  int _generation = 0;
  bool _disposed = false;
  bool refreshing = false;
  bool loadingMore = false;
  DateTime? lastRefresh;

  List<Drama> get catalog => List.unmodifiable(_catalog.values);
  bool get canSearchRemote =>
      registry.all.any((source) => source is RemoteSearchSource);
  bool get hasRankings => registry.all.any((source) => source is RankingSource);
  List<Drama> searchLocal(String keyword) =>
      catalog.where((drama) => drama.matches(keyword)).toList();

  Future<SearchResult> searchRemote(
    String keyword, {
    CancelToken? cancelToken,
  }) async {
    final generation = _generation;
    final items = <String, Drama>{};
    final warnings = <String>[];
    var total = 0;
    var successful = 0;
    for (final source in registry.all.whereType<RemoteSearchSource>()) {
      try {
        final result = await source.searchRemote(
          keyword,
          cancelToken: cancelToken,
        );
        successful++;
        total += result.total;
        for (final drama in result.items) {
          items[drama.id] = drama;
        }
      } on AppException catch (error) {
        warnings.add(error.message);
      }
    }
    cancelToken?.throwIfCancellationRequested();
    if (successful == 0) {
      throw AppException(warnings.isEmpty ? '当前剧库不支持联网搜索' : warnings.first);
    }
    final merged = await _mergeCatalog(
      items.values.toList(),
      generation,
      cancelToken: cancelToken,
      preserveChannel: true,
    );
    return SearchResult(items: merged, total: total, warnings: warnings);
  }

  Future<RankingPage> getRanking(
    RankingType type, {
    int page = 1,
    bool refresh = false,
    CancelToken? cancelToken,
  }) async {
    final generation = _generation;
    final sources = registry.all.whereType<RankingSource>();
    if (sources.isEmpty) throw const AppException('当前剧库不支持榜单');
    final result = await sources.first.getRanking(
      type,
      page: page,
      refresh: refresh,
      cancelToken: cancelToken,
    );
    cancelToken?.throwIfCancellationRequested();
    final merged = await _mergeCatalog(
      result.items.map((item) => item.drama).toList(),
      generation,
      cancelToken: cancelToken,
      preserveChannel: type == RankingType.hot,
    );
    return RankingPage(
      type: type,
      page: page,
      totalPages: result.totalPages,
      updatedText: result.updatedText,
      items: [
        for (var i = 0; i < result.items.length; i++)
          RankingItem(
            rank: result.items[i].rank,
            drama: merged[i],
            metric: result.items[i].metric,
          ),
      ],
    );
  }

  Future<List<Drama>> _mergeCatalog(
    List<Drama> items,
    int generation, {
    CancelToken? cancelToken,
    bool preserveChannel = false,
    String? catalogKey,
    CatalogPage? page,
  }) async {
    var merged = items;
    await _writeCatalog(() async {
      if (_disposed ||
          generation != _generation ||
          cancelToken?.isCancelled == true) {
        return;
      }
      merged = items
          .map(
            (drama) => drama.mergeMissing(
              _catalog[drama.id],
              preserveChannel: preserveChannel,
            ),
          )
          .toList();
      final stateStore = store;
      if (page != null &&
          catalogKey != null &&
          stateStore is SourceStateStore) {
        await (stateStore as SourceStateStore).saveCatalogPage(
          catalogKey,
          merged,
          page.cursor,
          page.hasMore,
        );
      } else {
        await store.saveCatalog(merged);
      }
      if (!_disposed &&
          generation == _generation &&
          cancelToken?.isCancelled != true) {
        for (final drama in merged) {
          _catalog[drama.id] = drama;
        }
      }
    });
    cancelToken?.throwIfCancellationRequested();
    _notify();
    return merged;
  }

  List<DramaChannel> _channels(DramaSourceAdapter source) =>
      source is CursorCatalogSource
      ? (source as CursorCatalogSource).catalogChannels
      : DramaChannel.values;

  List<DramaChannel> get channels => DramaChannel.values
      .where(
        (channel) =>
            registry.all.any((source) => _channels(source).contains(channel)) ||
            _catalog.values.any((drama) => drama.channel == channel),
      )
      .toList();

  bool get hasMore => registry.all.any(
    (source) => _channels(
      source,
    ).any((channel) => !_exhausted.contains('${source.id}:${channel.name}')),
  );

  bool hasMoreFor(DramaChannel? channel) => registry.all.any(
    (source) => (channel == null ? _channels(source) : [channel]).any(
      (channel) => !_exhausted.contains('${source.id}:${channel.name}'),
    ),
  );

  Future<void> loadCache() async {
    for (final drama in await store.readCatalog()) {
      _catalog[drama.id] = drama;
    }
    lastRefresh = await store.readLastRefresh();
    final stateStore = store;
    if (stateStore is SourceStateStore) {
      for (final source in registry.all.whereType<CursorCatalogSource>()) {
        final id = (source as DramaSourceAdapter).id;
        for (final channel in DramaChannel.values) {
          final key = '$id:${channel.name}';
          final state = await (stateStore as SourceStateStore).readSourceState(
            'catalog:$key',
          );
          if (state?['cursor'] is Map<String, dynamic>) {
            _cursors[key] = CatalogCursor.fromJson(
              state!['cursor'] as Map<String, dynamic>,
            );
            if (state['hasMore'] == false) _exhausted.add(key);
          }
        }
      }
    }
    _notify();
  }

  Future<void> loadInitial() => refresh();
  Future<void> refreshNewItems() => refresh();

  Future<void> refresh() => _refresh();

  /// Manual update checks the head and continues three saved pages per feed.
  /// Keep startup refresh light and retain the same cancellation/persistence
  /// boundary for the entire manual update.
  Future<void> updateCatalog() => _refresh(continueCatalog: true);

  Future<void> _refresh({bool continueCatalog = false}) async {
    if (refreshing) return;
    final generation = ++_generation;
    _catalogToken?.cancel();
    final token = _catalogToken = CancelToken();
    refreshing = true;
    loadingMore = false;
    errors.clear();
    final successfulBefore = _successfulPages;
    _pages.clear();
    _exhausted.removeWhere(
      (key) => registry.require(key.split(':').first) is! CursorCatalogSource,
    );
    _previousPageIds.clear();
    _notify();
    final requested = <String>{};
    await Future.wait([
      for (final source in registry.all)
        for (final channel in _channels(source))
          if (requested.add('${source.id}:${channel.name}'))
            _fetchPage(source, channel, 1, token, generation, refresh: true),
    ]);
    if (_disposed || generation != _generation) return;
    // Web fallback may expose an extra category during the first batch.
    await Future.wait([
      for (final source in registry.all)
        for (final channel in _channels(source))
          if (requested.add('${source.id}:${channel.name}'))
            _fetchPage(source, channel, 1, token, generation, refresh: true),
    ]);
    if (_disposed || generation != _generation) return;
    if (continueCatalog) {
      for (var batch = 0; batch < 3; batch++) {
        await Future.wait([
          for (final source in registry.all)
            for (final channel in _channels(source))
              if (!_exhausted.contains('${source.id}:${channel.name}') &&
                  !errors.containsKey('${source.id}:${channel.name}'))
                _fetchPage(
                  source,
                  channel,
                  (_pages['${source.id}:${channel.name}'] ?? 0) + 1,
                  token,
                  generation,
                ),
        ]);
        if (_disposed || generation != _generation) return;
      }
    }
    refreshing = false;
    if (_successfulPages > successfulBefore) {
      lastRefresh = DateTime.now();
      final time = lastRefresh!;
      await _writeCatalog(() async {
        if (!_disposed && generation == _generation) {
          await store.saveLastRefresh(time);
        }
      });
    }
    _notify();
  }

  Future<void> loadMore({DramaChannel? channel}) async {
    if (loadingMore || refreshing || !hasMoreFor(channel)) return;
    final generation = _generation;
    final token = _catalogToken ??= CancelToken();
    loadingMore = true;
    _notify();
    await Future.wait([
      for (final source in registry.all)
        for (final item in channel == null ? _channels(source) : [channel])
          if (!_exhausted.contains('${source.id}:${item.name}'))
            _fetchPage(
              source,
              item,
              (_pages['${source.id}:${item.name}'] ?? 0) + 1,
              token,
              generation,
            ),
    ]);
    if (_disposed || generation != _generation) return;
    loadingMore = false;
    _notify();
  }

  Future<void> _fetchPage(
    DramaSourceAdapter source,
    DramaChannel channel,
    int page,
    CancelToken token,
    int generation, {
    bool refresh = false,
  }) async {
    final key = '${source.id}:${channel.name}';
    try {
      final catalogPage = source is CursorCatalogSource
          ? await (source as CursorCatalogSource).loadCatalog(
              channel,
              cursor: _cursors[key] ?? const CatalogCursor(),
              refresh: refresh,
              knownIds: _catalog.keys.toSet(),
              cancelToken: token,
            )
          : null;
      final items =
          catalogPage?.items ??
          await source.fetchCatalog(channel, page, cancelToken: token);
      if (_disposed || generation != _generation || token.isCancelled) return;
      // Never clear cached rows before receiving a successful response. Pages
      // are merged; favorites/history carry independent metadata snapshots.
      await _mergeCatalog(
        items,
        generation,
        cancelToken: token,
        catalogKey: key,
        page: catalogPage,
      );
      if (_disposed || generation != _generation) return;
      final ids = items.map((drama) => drama.id).toSet();
      final repeatedPage = setEquals(ids, _previousPageIds[key]);
      _previousPageIds[key] = ids;
      _pages[key] = page;
      _successfulPages++;
      errors.remove(key);
      if (catalogPage != null) {
        _cursors[key] = catalogPage.cursor;
        if (catalogPage.hasMore) {
          _exhausted.remove(key);
        } else {
          _exhausted.add(key);
        }
      } else if (items.length < source.pageSize ||
          page >= source.maxPages ||
          repeatedPage) {
        _exhausted.add(key);
      }
      _notify();
    } on DioException catch (error) {
      if (!CancelToken.isCancel(error) &&
          !_disposed &&
          generation == _generation) {
        errors[key] = '网络连接失败，请重试';
      }
    } on AppException catch (error) {
      if (!_disposed && generation == _generation) errors[key] = error.message;
    } on Exception {
      if (!_disposed && generation == _generation) {
        errors[key] = '剧库保存失败，请检查存储空间后重试';
      }
    }
  }

  Future<DramaDetail> getDetail(Drama drama, {CancelToken? cancelToken}) async {
    final generation = _generation;
    try {
      final detail = await registry
          .require(drama.source)
          .fetchDetail(drama, cancelToken: cancelToken);
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      final merged = await _mergeCatalog(
        [detail.drama],
        generation,
        cancelToken: cancelToken,
      );
      final enriched = DramaDetail(
        drama: merged.single,
        episodes: detail.episodes,
      );
      await _writeCatalog(() async {
        if (!_disposed &&
            generation == _generation &&
            cancelToken?.isCancelled != true) {
          await store.saveDetail(enriched);
        }
      });
      return enriched;
    } on AppException {
      final cached = await store.readDetail(drama.id);
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<PlaybackOptions> resolve(
    Drama drama,
    Episode episode, {
    CancelToken? cancelToken,
    bool fallbackOnly = false,
    PlaybackRoute? startRoute,
  }) {
    final source = registry.require(drama.source);
    if (source is RoutedPlaybackSource) {
      return (source as RoutedPlaybackSource).resolveFrom(
        drama,
        episode,
        start:
            startRoute ??
            (fallbackOnly ? PlaybackRoute.fallback : PlaybackRoute.app),
        cancelToken: cancelToken,
      );
    }
    return source.resolvePlayback(
      drama,
      episode,
      cancelToken: cancelToken,
      fallbackOnly: fallbackOnly,
    );
  }

  Future<void> _writeCatalog(Future<void> Function() action) {
    final next = _catalogWrites.then((_) => action());
    _catalogWrites = next.catchError((Object _) {});
    return next;
  }

  Future<void> clearCache() async {
    ++_generation;
    _catalogToken?.cancel();
    _catalogToken = null;
    for (final source in registry.all.whereType<SourceCacheControl>()) {
      source.clearTransientCache();
    }
    refreshing = false;
    loadingMore = false;
    await _writeCatalog(store.clearCache);
    _catalog.clear();
    _pages.clear();
    _cursors.clear();
    _exhausted.clear();
    _previousPageIds.clear();
    errors.clear();
    lastRefresh = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _catalogToken?.cancel();
    for (final source in registry.all.whereType<SourceCacheControl>()) {
      source.clearTransientCache();
    }
    super.dispose();
  }
}
