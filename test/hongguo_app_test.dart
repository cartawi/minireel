import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minireel/core/config/source_config.dart';
import 'package:minireel/core/errors/app_exception.dart';
import 'package:minireel/core/network/app_http_client.dart';
import 'package:minireel/data/local/app_store.dart';
import 'package:minireel/data/repositories/drama_repository.dart';
import 'package:minireel/data/sources/hongguo/hongguo_adapter.dart';
import 'package:minireel/data/sources/source_adapter.dart';
import 'package:minireel/domain/models/catalog_page.dart';
import 'package:minireel/domain/models/drama.dart';
import 'package:minireel/domain/models/playback_source.dart';

import 'support/fakes.dart';

class _StateStore extends MemoryStore implements SourceStateStore {
  final state = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>?> readSourceState(String key) async => state[key];
  @override
  Future<void> saveSourceState(String key, Map<String, dynamic> value) async {
    state[key] = value;
  }

  @override
  Future<void> saveCatalogPage(
    String key,
    List<Drama> dramas,
    CatalogCursor cursor,
    bool hasMore,
  ) async {
    await saveCatalog(dramas);
    state['catalog:$key'] = {'cursor': cursor.toJson(), 'hasMore': hasMore};
  }

  @override
  Future<void> clearCache() async {
    await super.clearCache();
    state.removeWhere((key, _) => key.startsWith('catalog:'));
  }
}

class _Client implements TextClient, SignedJsonClient {
  final calls =
      <({Uri uri, Map<String, dynamic> body, Map<String, String> headers})>[];
  final webCalls = <Uri>[];
  late Future<Map<String, dynamic>> Function(Uri, Map<String, dynamic>) respond;
  Future<String> Function(Uri)? web;
  @override
  Future<String> postSignedJson(
    Uri Function() prepareUri,
    String body,
    Map<String, String> Function(Uri) prepareHeaders, {
    CancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancellationRequested();
    final uri = prepareUri();
    final data = jsonDecode(body) as Map<String, dynamic>;
    calls.add((uri: uri, body: data, headers: prepareHeaders(uri)));
    final result = await respond(uri, data);
    cancelToken?.throwIfCancellationRequested();
    return jsonEncode(result);
  }

  @override
  Future<String> getText(
    Uri uri, {
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancellationRequested();
    webCalls.add(uri);
    if (web != null) return web!(uri);
    throw const AppException('web unavailable');
  }
}

final _config = SourceConfig(
  baseUrl: Uri.parse('https://web.invalid'),
  playbackEndpoint: Uri.parse('https://legacy.invalid/play'),
  referer: 'https://web.invalid/',
  mediaReferer: 'https://media.invalid/',
  appBaseUrl: Uri.parse('https://app.invalid'),
  appUserAgent: 'fixture',
  appParameters: const {'aid': '8662'},
);
const _drama = Drama(
  id: 'hongguo:100',
  source: 'hongguo',
  sourceId: '100',
  title: 'fixture',
);
const _episode = Episode(
  id: 'hongguo:100:201',
  dramaId: 'hongguo:100',
  sourceEpisodeId: '201',
  index: 1,
);

Map<String, dynamic> _detail({int total = 2}) => {
  'data': {
    'video_data': {
      'series_id_str': '100',
      'episode_cnt': total,
      'video_list': [
        {'vid': '202', 'vid_index': 2},
        {'vid': '201', 'vid_index': 1},
      ],
    },
  },
};
Map<String, dynamic> _media() => {
  'data': {
    'video_model': {
      'video_duration': 12.5,
      'video_list': {
        'unsupported': {
          'main_url': 'https://media.invalid/2160.mp4',
          'video_meta': {'codec_type': 'bytevc2', 'definition': '2160p'},
        },
        'hevc': {
          'main_url': 'https://media.invalid/hevc.mp4',
          'video_meta': {'codec_type': 'hevc', 'definition': '1080p'},
        },
        'avc': {
          'main_url': 'https://media.invalid/avc.mp4',
          'video_meta': {'codec_type': 'h264', 'definition': '1080p'},
        },
      },
    },
  },
};

void main() {
  test(
    'manual update resumes saved tails, persists progress and stops at the end',
    () async {
      final store = _StateStore();
      final client = _Client()
        ..respond = (_, body) async {
          final offset = body['offset'] as int;
          final genre = (body['select_items'] as Map)['genre'][0] as String;
          final base = {
            'short_play': 1000,
            'comic_series': 2000,
            'ai_series': 3000,
          }[genre]!;
          return {
            'data': {
              'video_data': [
                {'series_id': '${base + offset}', 'series_title': 'fixture'},
              ],
              'next_offset': offset + 18,
              'session_id': 'session-$genre',
              'has_more': offset < 90,
            },
          };
        };
      DramaRepository repository() => DramaRepository(
        SourceRegistry([HongguoAdapter(_config, client, store: store)]),
        store,
      );
      List<int> offsets() => client.calls
          .where(
            (call) =>
                (call.body['select_items'] as Map)['genre'][0] == 'short_play',
          )
          .map((call) => call.body['offset'] as int)
          .toList();
      final first = repository();
      addTearDown(first.dispose);
      await first.loadInitial();
      await first.loadMore();
      client.calls.clear();
      await first.updateCatalog();
      expect(offsets(), [0, 36, 54, 72]);
      expect(first.catalog, hasLength(15));
      expect(store.catalog, hasLength(15));
      expect(first.refreshing, false);
      final second = repository();
      addTearDown(second.dispose);
      await second.loadCache();
      client.calls.clear();
      await second.updateCatalog();
      expect(offsets(), [0, 90]);
      expect(second.catalog, hasLength(18));
      expect(second.hasMore, false);
      client.calls.clear();
      await second.updateCatalog();
      expect(offsets(), [0]);
      expect(second.catalog, hasLength(18));
    },
  );

  test(
    'manual update retains successful pages when continuation fails',
    () async {
      final store = _StateStore();
      final client = _Client()
        ..respond = (_, body) async {
          final offset = body['offset'] as int;
          if (offset >= 36) throw const AppException('offline');
          final genre = (body['select_items'] as Map)['genre'][0] as String;
          final base = {
            'short_play': 1000,
            'comic_series': 2000,
            'ai_series': 3000,
          }[genre]!;
          return {
            'data': {
              'video_data': [
                {'series_id': '${base + offset}', 'series_title': 'fixture'},
              ],
              'next_offset': offset + 18,
              'has_more': true,
            },
          };
        };
      final repo = DramaRepository(
        SourceRegistry([HongguoAdapter(_config, client, store: store)]),
        store,
      );
      addTearDown(repo.dispose);
      await repo.loadInitial();
      await repo.updateCatalog();
      expect(repo.catalog, hasLength(6));
      expect(store.catalog, hasLength(6));
      expect(repo.errors.keys, contains('hongguo:real'));
      expect(
        (store.state['catalog:hongguo:real']!['cursor'] as Map)['offset'],
        36,
      );
      expect(repo.refreshing, false);
    },
  );

  test(
    'catalog refresh preserves tail and restart continues each feed with the same device',
    () async {
      final store = _StateStore();
      final client = _Client()
        ..respond = (uri, body) async {
          final offset = body['offset'] as int;
          final genre = (body['select_items'] as Map)['genre'][0] as String;
          final base = {
            'short_play': 1000,
            'comic_series': 2000,
            'ai_series': 3000,
          }[genre]!;
          return {
            'data': {
              'video_data': [
                {'series_id': '${base + offset}', 'series_title': 'fixture'},
              ],
              'next_offset': offset + 18,
              'session_id': 'session-$genre',
              'has_more': true,
            },
          };
        };
      DramaRepository repository() => DramaRepository(
        SourceRegistry([HongguoAdapter(_config, client, store: store)]),
        store,
      );
      final first = repository();
      await first.loadInitial();
      await first.loadMore();
      expect(first.catalog, hasLength(6));
      await first.refreshNewItems();
      expect(
        (store.state['catalog:hongguo:real']!['cursor'] as Map)['offset'],
        36,
      );
      final identity = client.calls.first.uri.queryParameters['device_id'];
      first.dispose();
      final second = repository();
      addTearDown(second.dispose);
      await second.loadCache();
      await second.loadMore();
      expect(
        client.calls.skip(client.calls.length - 3).map((c) => c.body['offset']),
        everyElement(36),
      );
      expect(client.calls.last.uri.queryParameters['device_id'], identity);
      expect(second.catalog, hasLength(9));
      await second.clearCache();
      expect(store.state.keys, contains('hongguo:identity'));
      expect(store.state.keys.where((k) => k.startsWith('catalog:')), isEmpty);
      await second.loadMore();
      expect(second.catalog, hasLength(3));
    },
  );

  test(
    'detail requests merge and a cancelled waiter does not cancel another caller',
    () async {
      final reply = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      final client = _Client()
        ..respond = (_, _) {
          started.complete();
          return reply.future;
        };
      final adapter = HongguoAdapter(_config, client);
      final token = CancelToken();
      final one = adapter.fetchDetail(_drama, cancelToken: token);
      final two = adapter.fetchDetail(_drama);
      final cancelled = expectLater(one, throwsA(isA<DioException>()));
      await started.future;
      token.cancel();
      await cancelled;
      reply.complete(_detail());
      final detail = await two;
      expect(detail.episodes.map((e) => e.index), [1, 2]);
      await adapter.fetchDetail(_drama);
      expect(client.calls, hasLength(1));
      expect(client.webCalls, isEmpty);
    },
  );

  test('incomplete App detail falls back to a complete web detail', () async {
    final client = _Client();
    client.respond = (_, _) async => _detail(total: 3);
    client.web = (_) async =>
        'window._ROUTER_DATA = ${jsonEncode({
          'loaderData': {
            'detail_page': {
              'seriesDetail': {
                'series_id': '100',
                'episode_cnt': 3,
                'vid_list': ['201', '202', '203'],
              },
            },
          },
        })};';
    final detail = await HongguoAdapter(_config, client).fetchDetail(_drama);
    expect(detail.episodes, hasLength(3));
    expect(client.webCalls.single.path, '/detail');
  });

  test(
    'App media prefers AVC at equal quality and resolution failure reaches legacy',
    () async {
      final client = _Client()..respond = (_, _) async => _media();
      final adapter = HongguoAdapter(_config, client);
      final appMedia = await adapter.resolvePlayback(_drama, _episode);
      expect(appMedia.sources.single.uri.path, '/avc.mp4');
      expect(appMedia.sources.single.route, PlaybackRoute.app);
      expect(
        appMedia.sources.single.duration,
        const Duration(milliseconds: 12500),
      );
      expect(client.webCalls, isEmpty);
      client.respond = (_, _) async => throw const AppException('app failed');
      client.web = (uri) async {
        if (uri.host == 'web.invalid') throw const AppException('web failed');
        return jsonEncode({'url': 'https://media.invalid/legacy.mp4'});
      };
      final fallback = await adapter.resolvePlayback(_drama, _episode);
      expect(client.webCalls.map((uri) => uri.host), [
        'web.invalid',
        'legacy.invalid',
      ]);
      expect(fallback.sources.single.route, PlaybackRoute.fallback);
    },
  );

  test(
    'invalid App pagination retains its cursor when web also fails',
    () async {
      final client = _Client()
        ..respond = (_, _) async => {
          'data': {
            'video_data': [
              {'series_id': '999'},
            ],
            'has_more': true,
            'next_offset': 18,
          },
        };
      final adapter = HongguoAdapter(_config, client);
      const cursor = CatalogCursor(
        offset: 18,
        initialized: true,
        lastId: 'hongguo:101',
      );
      await expectLater(
        adapter.loadCatalog(DramaChannel.real, cursor: cursor),
        throwsA(isA<AppException>()),
      );
      expect(cursor.offset, 18);
      expect(client.webCalls.single.path, '/category/real-drama');
    },
  );
}
