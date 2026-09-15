import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../app/app_controller.dart';
import '../core/errors/app_exception.dart';
import '../core/network/app_http_client.dart';
import '../domain/models/drama.dart';
import '../domain/models/playback_source.dart';
import '../domain/models/watch_record.dart';
import 'playback_engine.dart';
import 'next_episode_prefetch.dart';

/// Owns one viewing session. UI gestures express intent; this controller owns
/// cancellation, playback sequencing, progress, pause reasons and auto-next.
final class PlaybackSession extends ChangeNotifier {
  PlaybackSession({
    required this.app,
    required this.engine,
    required this.drama,
  }) {
    engine.state.addListener(_onEngine);
    _recordTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => saveProgress(),
    );
  }

  final AppController app;
  final PlaybackEngine engine;
  Drama drama;
  List<Episode> episodes = [];
  int currentIndex = 0;
  Episode? get episode => episodes.isEmpty ? null : episodes[currentIndex];
  EngineSnapshot snapshot = const EngineSnapshot();
  PlaybackOptions? options;
  String currentQuality = '原画';
  bool loadingDetail = true;
  bool resolving = false;
  bool showLoading = false;
  String? error;
  String? loadingMessage;
  bool temporaryBoost = false;
  bool get playing => snapshot.playing && !resolving;
  bool get buffering => resolving || snapshot.buffering;
  Duration get position => snapshot.position;
  Duration get duration => snapshot.duration;
  double get rate => temporaryBoost ? 2 : app.preferences.speed;
  bool get canPrevious => currentIndex > 0;
  bool get canNext => currentIndex + 1 < episodes.length;
  bool get ready =>
      episode != null && !loadingDetail && !resolving && error == null;

  int _generation = 0;
  CancelToken? _request;
  Timer? _recordTimer;
  Timer? _loadTimer;
  Timer? _prefetchTimer;
  Timer? _loadingIndicatorTimer;
  final _prefetch = NextEpisodePrefetch(ttl: const Duration(minutes: 3));
  bool _usedPrefetch = false;
  int? _prefetchGeneration;
  DateTime? _preloadAfter;
  final Set<String> _pauseReasons = {};
  bool _wantPlaying = true;
  bool _acceptEvents = false;
  bool _completedHandled = false;
  bool _disposed = false;
  bool _usingFallback = false;
  PlaybackRoute _route = PlaybackRoute.app;
  int _maxRecoverySteps = 2;
  int _recoveryStep = 0;
  Duration _requestedStart = Duration.zero;
  Future<void> _commands = Future.value();

  Future<void> initialize({int? initialEpisode}) async {
    trimPreload();
    final generation = ++_generation;
    _request?.cancel();
    final token = _request = CancelToken();
    loadingDetail = true;
    error = null;
    _notify();
    try {
      final detail = await app.repository.getDetail(drama, cancelToken: token);
      if (!_current(generation)) return;
      drama = detail.drama;
      episodes = detail.episodes;
      final history = app.preferences.rememberProgress
          ? app.historyOf(drama.id)
          : null;
      var target = initialEpisode ?? history?.episodeIndex ?? 1;
      if (initialEpisode == null &&
          history?.completed == true &&
          app.preferences.autoNext &&
          target < episodes.length) {
        target++;
      }
      var index = episodes.indexWhere((ep) => ep.index == target);
      if (index < 0) index = 0;
      loadingDetail = false;
      final resume =
          history != null &&
              history.episodeId == episodes[index].id &&
              !history.completed
          ? history.position
          : Duration.zero;
      await playEpisode(index, resume: resume);
    } on DioException catch (error) {
      if (!CancelToken.isCancel(error) && _current(generation)) {
        _fail('网络连接失败，请重试');
      }
    } on AppException catch (error) {
      if (_current(generation)) _fail(error.message);
    }
  }

  Future<void> playEpisode(int index, {Duration resume = Duration.zero}) =>
      _loadEpisode(index, resume: resume);

  Future<void> _loadEpisode(
    int index, {
    Duration resume = Duration.zero,
    bool fallbackOnly = false,
    PlaybackRoute? startRoute,
    int recoveryStep = 0,
    String? quality,
    String? message,
    bool preserveIntent = false,
  }) async {
    if (_disposed || index < 0 || index >= episodes.length) return;
    saveProgress();
    final generation = ++_generation;
    _request?.cancel();
    final token = _request = CancelToken();
    _loadTimer?.cancel();
    _prefetchTimer?.cancel();
    _acceptEvents = false;
    currentIndex = index;
    if (!preserveIntent) _wantPlaying = true;
    _usingFallback = fallbackOnly;
    _usedPrefetch = false;
    _route =
        startRoute ??
        (fallbackOnly ? PlaybackRoute.fallback : PlaybackRoute.app);
    _recoveryStep = recoveryStep;
    _requestedStart = resume;
    temporaryBoost = false;
    snapshot = const EngineSnapshot();
    options = null;
    error = null;
    resolving = true;
    loadingMessage = message;
    _completedHandled = false;
    _notify();
    try {
      await engine.stop();
      if (!_current(generation)) return;
      final cached = startRoute == null && !fallbackOnly
          ? await _prefetch.take(episodes[index].id, token)
          : null;
      if (!_current(generation)) return;
      if (cached == null) trimPreload();
      _usedPrefetch = cached != null;
      final resolved =
          cached ??
          await app.repository.resolve(
            drama,
            episodes[index],
            cancelToken: token,
            fallbackOnly: fallbackOnly,
            startRoute: _route,
          );
      if (!_current(generation)) return;
      options = resolved;
      final source = resolved.select(quality ?? app.preferences.quality);
      _route = source.route;
      if (recoveryStep == 0) {
        _maxRecoverySteps = _route == PlaybackRoute.app ? 3 : 2;
      }
      _usingFallback = fallbackOnly || source.route == PlaybackRoute.fallback;
      currentQuality = source.quality;
      await engine.open(
        source,
        start: resume,
        isCurrent: () => _current(generation),
        episodeId: episodes[index].id,
      );
      if (!_current(generation)) return;
      await engine.setRate(rate);
      _acceptEvents = true;
      resolving = false;
      loadingMessage = null;
      snapshot = engine.state.value;
      if (snapshot.error != null) {
        _recoverOrFail(snapshot.error!);
        return;
      }
      await _syncIntent();
      _schedulePrefetch(generation);
      _notify();
    } on DioException catch (error) {
      if (!CancelToken.isCancel(error) && _current(generation)) {
        _fail('网络连接失败，请重试');
      }
    } on AppException catch (error) {
      if (_current(generation)) {
        if (options != null) {
          resolving = false;
          _acceptEvents = true;
          _recoverOrFail(error.message);
        } else {
          _fail(error.message);
        }
      }
    } on Exception {
      if (_current(generation)) {
        if (options != null) {
          resolving = false;
          _acceptEvents = true;
          _recoverOrFail('视频加载失败，请重试或切换下一集');
        } else {
          _fail('视频加载失败，请重试或切换下一集');
        }
      }
    }
  }

  Future<void> previous() => playEpisode(currentIndex - 1);
  Future<void> next() => playEpisode(currentIndex + 1);
  Future<void> retry() => episodes.isEmpty
      ? initialize()
      : _loadEpisode(
          currentIndex,
          resume: _recoveryPosition,
          fallbackOnly: _usingFallback,
          startRoute: _route,
          preserveIntent: true,
        );

  Duration get _recoveryPosition =>
      position > Duration.zero ? position : _requestedStart;

  void _recoverOrFail(String message) {
    if (_disposed || !_acceptEvents || resolving) return;
    _loadTimer?.cancel();
    saveProgress();
    final resume = _recoveryPosition;
    // A prefetched URL can expire before its nominal TTL: retry this route
    // once with fresh resolution before advancing to the next source.
    if (_usedPrefetch) {
      _usedPrefetch = false;
      _acceptEvents = false;
      unawaited(
        _loadEpisode(
          currentIndex,
          resume: resume,
          startRoute: _route,
          fallbackOnly: _usingFallback,
          recoveryStep: _recoveryStep,
          message: '正在重新获取播放地址…',
          preserveIntent: true,
        ),
      );
      return;
    }
    if (_recoveryStep >= _maxRecoverySteps) {
      _acceptEvents = false;
      _fail(message);
      // Stop the demuxer as well: pausing alone can leave HTTP reconnects alive.
      unawaited(engine.stop());
      return;
    }
    String? nextQuality;
    if (_usingFallback && options != null) {
      final sources = options!.sources;
      final current = sources.indexWhere(
        (source) => source.quality == currentQuality,
      );
      if (current >= 0 && current + 1 < sources.length) {
        nextQuality = sources[current + 1].quality;
      }
    }
    final notice = !_usingFallback
        ? '正在尝试备用片源…'
        : nextQuality != null
        ? '正在切换到 $nextQuality…'
        : '正在重新连接…';
    _acceptEvents = false;
    unawaited(
      _loadEpisode(
        currentIndex,
        resume: resume,
        fallbackOnly: _route != PlaybackRoute.app,
        startRoute: _route == PlaybackRoute.app
            ? PlaybackRoute.primary
            : PlaybackRoute.fallback,
        recoveryStep: _recoveryStep + 1,
        quality: nextQuality,
        message: notice,
        preserveIntent: true,
      ),
    );
  }

  void _armLoadTimeout() {
    if (_disposed ||
        resolving ||
        loadingDetail ||
        error != null ||
        !_acceptEvents ||
        !_wantPlaying ||
        _pauseReasons.isNotEmpty ||
        (_preloadAfter != null && DateTime.now().isBefore(_preloadAfter!)) ||
        _loadTimer?.isActive == true) {
      return;
    }
    final generation = _generation;
    final startedAt = position;
    _loadTimer = Timer(const Duration(seconds: 30), () {
      if (_current(generation) &&
          _pauseReasons.isEmpty &&
          _wantPlaying &&
          !snapshot.completed &&
          position <= startedAt) {
        _recoverOrFail('视频加载较慢，请检查网络后重试');
      }
    });
  }

  void _schedulePrefetch(int generation) {
    if (!app.preferences.prefetchNextEpisode) {
      if (_prefetchTimer?.isActive == true || _prefetchGeneration == generation) {
        trimPreload();
      }
      return;
    }
    if (!canNext ||
        !_current(generation) ||
        !_wantPlaying ||
        _pauseReasons.isNotEmpty ||
        (_prefetchGeneration == generation && !_prefetch.expired) ||
        _prefetchTimer?.isActive == true) {
      return;
    }
    final next = episodes[currentIndex + 1];
    _prefetchTimer = Timer(const Duration(milliseconds: 800), () {
      if (!_current(generation) ||
          !ready ||
          !playing ||
          buffering ||
          !_wantPlaying ||
          _pauseReasons.isNotEmpty) {
        return;
      }
      _prefetchGeneration = generation;
      final preloader = engine;
      if (preloader is PreloadingPlaybackEngine) {
        (preloader as PreloadingPlaybackEngine).discardPreload();
      }
      _prefetch.start(next.id, (token) async {
        final resolved = await app.repository.resolve(
          drama,
          next,
          cancelToken: token,
        );
        token.throwIfCancellationRequested();
        if (!_disposed && preloader is PreloadingPlaybackEngine) {
          unawaited(
            (preloader as PreloadingPlaybackEngine)
                .preload(
                  resolved.select(app.preferences.quality),
                  episodeId: next.id,
                )
                .catchError((Object _) {}),
          );
        }
        return resolved;
      });
    });
  }

  /// Release speculative media on backgrounding, memory pressure or a jump.
  void trimPreload({Duration cooldown = Duration.zero}) {
    if (cooldown > Duration.zero) {
      _preloadAfter = DateTime.now().add(cooldown);
    }
    _prefetchTimer?.cancel();
    _prefetch.clear();
    _prefetchGeneration = null;
    final preloader = engine;
    if (preloader is PreloadingPlaybackEngine) {
      (preloader as PreloadingPlaybackEngine).discardPreload();
    }
  }

  void togglePlay() {
    if (!ready) return;
    if (snapshot.completed && !_wantPlaying) {
      _completedHandled = false;
      unawaited(seek(Duration.zero));
    }
    _wantPlaying = !_wantPlaying;
    if (!_wantPlaying) saveProgress();
    unawaited(_syncIntent());
    _notify();
  }

  void hold(String reason) {
    _pauseReasons.add(reason);
    _loadTimer?.cancel();
    _prefetchTimer?.cancel();
    if (reason == 'background' || reason == 'minimized' || reason == 'system') {
      trimPreload();
    }
    saveProgress();
    unawaited(_syncIntent());
  }

  void release(String reason) {
    _pauseReasons.remove(reason);
    unawaited(_syncIntent());
  }

  Future<void> _syncIntent() {
    _commands = _commands
        .then((_) async {
          if (_disposed || resolving || loadingDetail) return;
          await engine.setPlaying(
            _wantPlaying && _pauseReasons.isEmpty && error == null,
          );
          _armLoadTimeout();
        })
        .catchError((Object _) {
          if (!_disposed) _fail('播放状态更新失败，请重试');
        });
    return _commands;
  }

  Future<void> seek(Duration target) async {
    if (!ready || duration <= Duration.zero) return;
    final ms = target.inMilliseconds.clamp(0, duration.inMilliseconds);
    await engine.seek(Duration(milliseconds: ms));
    if (_disposed) return;
    _completedHandled = false;
    saveProgress();
  }

  void boost(bool active) {
    if (_disposed || temporaryBoost == active) return;
    temporaryBoost = active;
    unawaited(engine.setRate(rate));
    _notify();
  }

  void setSpeed(double speed) {
    app.setPreferences(app.preferences.copyWith(speed: speed));
    unawaited(engine.setRate(rate));
    _notify();
  }

  Future<void> setQuality(String quality) async {
    trimPreload();
    app.setPreferences(app.preferences.copyWith(quality: quality));
    if (options == null || options!.select(quality).quality == currentQuality) {
      return;
    }
    // Resolve afresh: signed URLs/keys are intentionally never reused on retry.
    final resume = position;
    final wasWanted = _wantPlaying;
    hold('quality');
    await _loadEpisode(
      currentIndex,
      resume: resume,
      fallbackOnly: _usingFallback,
      startRoute: _route,
      quality: quality,
      preserveIntent: true,
    );
    _wantPlaying = wasWanted;
    release('quality');
  }

  void _onEngine() {
    if (_disposed || !_acceptEvents) return;
    snapshot = engine.state.value;
    if (snapshot.error != null) {
      _recoverOrFail(snapshot.error!);
      return;
    }
    if (snapshot.buffering) {
      _armLoadTimeout();
      if (_prefetchGeneration == _generation) trimPreload();
    }
    if (playing && !buffering) _schedulePrefetch(_generation);
    if (snapshot.completed && !_completedHandled && !resolving) {
      _completedHandled = true;
      saveProgress();
      if (app.preferences.autoNext &&
          canNext &&
          _pauseReasons.isEmpty &&
          _wantPlaying) {
        unawaited(next());
      } else {
        _wantPlaying = false;
      }
    }
    _notify();
  }

  void saveProgress() {
    if (!_acceptEvents ||
        episode == null ||
        resolving ||
        duration <= Duration.zero) {
      return;
    }
    app.record(
      WatchRecord(
        drama: drama,
        episodeId: episode!.id,
        episodeIndex: episode!.index,
        position: position > duration ? duration : position,
        duration: duration,
        updatedAt: DateTime.now(),
      ),
    );
  }

  bool _current(int generation) => !_disposed && generation == _generation;
  void _fail(String message) {
    if (_disposed) return;
    trimPreload();
    loadingDetail = false;
    resolving = false;
    error = message;
    loadingMessage = null;
    _loadTimer?.cancel();
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    if (error == null && (loadingDetail || buffering)) {
      if (!showLoading && _loadingIndicatorTimer == null) {
        _loadingIndicatorTimer = Timer(const Duration(milliseconds: 180), () {
          _loadingIndicatorTimer = null;
          if (!_disposed && error == null && (loadingDetail || buffering)) {
            showLoading = true;
            notifyListeners();
          }
        });
      }
    } else {
      _loadingIndicatorTimer?.cancel();
      _loadingIndicatorTimer = null;
      showLoading = false;
    }
    notifyListeners();
  }

  Future<void> close() async {
    if (_disposed) return;
    saveProgress();
    _disposed = true;
    ++_generation;
    _request?.cancel();
    _recordTimer?.cancel();
    _loadTimer?.cancel();
    _loadingIndicatorTimer?.cancel();
    trimPreload();
    engine.state.removeListener(_onEngine);
    options = null;
    await _commands;
    await engine.dispose();
    await app.flush();
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
