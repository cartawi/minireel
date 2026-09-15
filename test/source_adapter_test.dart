import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minireel/core/config/source_config.dart';
import 'package:minireel/core/errors/app_exception.dart';
import 'package:minireel/core/network/app_http_client.dart';
import 'package:minireel/data/sources/hongguo/hongguo_adapter.dart';
import 'package:minireel/data/sources/hongguo/hongguo_parser.dart';
import 'package:minireel/data/sources/hongguo/hongguo_playback_codec.dart';
import 'package:minireel/domain/models/drama.dart';
import 'package:minireel/domain/models/playback_source.dart';

String html(String loader, Map<String, dynamic> data) =>
    '<script>window._ROUTER_DATA = '
    '${jsonEncode({
      'loaderData': {'category_layout': null, loader: data},
    })}; window.after=true;</script>';

class _Client implements TextClient {
  final calls = <Uri>[];
  late Future<String> Function(Uri) respond;
  @override
  Future<String> getText(
    Uri uri, {
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    calls.add(uri);
    return respond(uri);
  }
}

void main() {
  const parser = HongguoParser();
  const codec = HongguoPlaybackCodec();
  final vectors =
      jsonDecode(File('test/fixtures/playback_codec.json').readAsStringSync())
          as Map<String, dynamic>;
  final config = SourceConfig(
    baseUrl: Uri.parse('https://example.invalid'),
    playbackEndpoint: Uri.parse('https://example.invalid/api/play'),
    referer: 'https://example.invalid/',
    mediaReferer: 'https://media.invalid/',
  );
  const drama = Drama(
    id: 'hongguo:100',
    source: 'hongguo',
    sourceId: '100',
    title: '测试短剧',
  );
  const episode = Episode(
    id: 'hongguo:100:202',
    dramaId: 'hongguo:100',
    sourceEpisodeId: '202',
    index: 2,
  );

  test(
    'fallbackOnly bypasses a previously unusable web URL and preserves media headers',
    () async {
      final client = _Client()
        ..respond = (_) async => vectors['response'] as String;
      final result = await HongguoAdapter(
        config,
        client,
      ).resolvePlayback(drama, episode, fallbackOnly: true);
      expect(client.calls, hasLength(1));
      expect(client.calls.single.path, '/api/play');
      expect(result.sources.single.route, PlaybackRoute.fallback);
      expect(result.sources.single.headers['Origin'], 'https://media.invalid');
      expect(result.sources.single.headers['Accept-Encoding'], 'identity');
    },
  );

  test(
    'echoed request response from unavailable long series is not treated as media',
    () async {
      final client = _Client()
        ..respond = (uri) async =>
            jsonEncode({'parse': 0, 'url': uri.queryParameters['id']});
      await expectLater(
        HongguoAdapter(
          config,
          client,
        ).resolvePlayback(drama, episode, fallbackOnly: true),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('片源暂未提供'),
          ),
        ),
      );
    },
  );

  test(
    'plain fallback media response is accepted without inventing a content key',
    () async {
      final client = _Client()
        ..respond = (_) async =>
            jsonEncode({'parse': 0, 'url': 'https://media.invalid/play.m3u8'});
      final result = await HongguoAdapter(
        config,
        client,
      ).resolvePlayback(drama, episode, fallbackOnly: true);
      expect(result.sources.single.kind, PlaybackKind.hls);
      expect(result.sources.single.contentKey, isNull);
      expect(result.sources.single.route, PlaybackRoute.fallback);
    },
  );

  test(
    'router parser handles quoted braces, null layout and trailing scripts',
    () {
      final body = html(r'category_$', {
        'isSuccess': true,
        'recommendList': [
          {
            'video_data': {
              'series_id': '100',
              'series_title': '故事 {转折} "开始"',
              'episode_cnt': '84',
              'tags': ['甜宠', '都市'],
            },
          },
          {
            'video_data': {
              'series_id': '100',
              'series_title': '故事 {转折} "开始"',
              'episode_cnt': '84',
            },
          },
        ],
      });
      final items = parser.catalog(body, DramaChannel.real);
      expect(items.length, 1);
      expect(items.single.title, '故事 {转折} "开始"');
      expect(items.single.episodeCount, 84);
      expect(
        () => parser.routerData('bad response'),
        throwsA(isA<AppException>()),
      );
    },
  );

  test(
    'detail preserves large string ids and maps episode identity without media URLs',
    () {
      final detail = parser.detail(
        html('detail_page', {
          'seriesDetail': {
            'series_id': '100',
            'series_name': '短剧',
            'vid_list': ['7399912345678990001', '7399912345678990002'],
          },
        }),
        drama,
      );
      expect(detail.episodes[1].sourceEpisodeId, '7399912345678990002');
      expect(detail.episodes[1].index, 2);
      expect(detail.episodes[1].toJson().containsKey('url'), false);
      expect(
        () => parser.detail(
          html('detail_page', {
            'seriesDetail': {'vid_list': []},
          }),
          drama,
        ),
        throwsA(isA<AppException>()),
      );
    },
  );

  test(
    'Go-compatible v2 AES wrapper and spade key match independent golden vectors',
    () {
      expect(
        utf8.decode(codec.decodeResponse(vectors['wrapped'] as String)),
        vectors['response'],
      );
      final key = codec.decodeContentKey(vectors['content'] as String);
      expect(
        key.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        vectors['key'],
      );
      expect(
        utf8.decode(codec.decodeResponse(vectors['response'] as String)),
        vectors['response'],
      );
      expect(
        codec.decodeContentKey(
          (vectors['content'] as String).replaceAll('=', ''),
        ),
        key,
      );
    },
  );

  test(
    'malformed response and unsupported media-key versions fail clearly',
    () {
      for (final body in [
        'v2.bad.data',
        'v2.0000ff.data',
        'v2.0000${'00' * 32}.AA==',
      ]) {
        expect(() => codec.decodeResponse(body), throwsA(isA<AppException>()));
      }
      expect(
        () => codec.decodeContentKey(vectors['unsupportedContent'] as String),
        throwsA(isA<AppException>()),
      );
      expect(
        () => codec.decodeContentKey('not-base64!'),
        throwsA(isA<AppException>()),
      );
    },
  );

  test(
    'a mismatched preview falls back and sends the requested episode identity',
    () async {
      final client = _Client();
      client.respond = (uri) async => uri.path.startsWith('/player/')
          ? html('player_page', {
              'series_id': '100',
              'vid': '201',
              'video_player_info': {
                'main_url': 'https://example.invalid/wrong.mp4',
              },
            })
          : vectors['wrapped'] as String;
      final options = await HongguoAdapter(
        config,
        client,
      ).resolvePlayback(drama, episode);
      expect(options.sources.single.kind, PlaybackKind.cenc);
      expect(options.sources.single.quality, '1080P');
      final reference = jsonDecode(
        utf8.decode(base64.decode(client.calls.last.queryParameters['id']!)),
      );
      expect(reference['vid'], '202');
      expect(reference['series_id'], '100');
      expect(
        options.sources.single.headers['Referer'],
        'https://media.invalid/',
      );
    },
  );

  test(
    'valid direct media skips fallback and sends playback headers',
    () async {
      final client = _Client()
        ..respond = (_) async => html('player_page', {
          'series_id': '100',
          'vid': '202',
          'video_player_info': {
            'main_url': 'https://example.invalid/video.m3u8',
            'duration': '92.5',
          },
        });
      final options = await HongguoAdapter(
        config,
        client,
      ).resolvePlayback(drama, episode);
      expect(client.calls.length, 1);
      expect(options.sources.single.kind, PlaybackKind.hls);
      expect(
        options.sources.single.duration,
        const Duration(milliseconds: 92500),
      );
    },
  );

  test(
    'invalid highest quality does not discard valid lower quality',
    () async {
      final good =
          (jsonDecode(vectors['response'] as String)['key_urls'] as List).first;
      final payload = jsonEncode({
        'parse': 0,
        'jx': '0',
        'key_urls': [
          {...good, 'name': '1080P', 'spade_a': 'bad'},
          {...good, 'name': '720P'},
        ],
      });
      final client = _Client()
        ..respond = (uri) async =>
            uri.path.startsWith('/player/') ? 'invalid' : payload;
      final options = await HongguoAdapter(
        config,
        client,
      ).resolvePlayback(drama, episode);
      expect(options.select('1080P').quality, '720P');
    },
  );

  test('already cancelled resolve sends no requests', () async {
    final token = CancelToken()..cancel();
    final client = _Client()..respond = (_) async => throw token.cancelError!;
    await expectLater(
      HongguoAdapter(
        config,
        client,
      ).resolvePlayback(drama, episode, cancelToken: token),
      throwsA(isA<DioException>()),
    );
    expect(client.calls, isEmpty);
  });

  test(
    'cancellation during web resolve never sends fallback request',
    () async {
      final token = CancelToken();
      final client = _Client()
        ..respond = (_) async {
          token.cancel();
          throw token.cancelError!;
        };
      await expectLater(
        HongguoAdapter(
          config,
          client,
        ).resolvePlayback(drama, episode, cancelToken: token),
        throwsA(isA<DioException>()),
      );
      expect(client.calls.map((uri) => uri.path), ['/player/100/202']);
    },
  );
}
