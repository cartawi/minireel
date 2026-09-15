import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../domain/models/drama.dart';
import '../../domain/models/preferences.dart';
import '../../playback/media_kit_engine.dart';
import '../../playback/playback_engine.dart';
import '../../playback/playback_session.dart';
import '../../playback/device_controls.dart';
import '../player/desktop_player_input.dart';
import '../shared/widgets.dart';

/// macOS 版播放器。
///
/// 复用 PlaybackSession + MediaKitEngine + DeviceControls + DesktopPlayerControls
/// + DesktopPlayerInput（键盘映射），仅替换窗口管理层：
/// DesktopWindow（Windows 专用的 mini 模式 / 窗口形态切换）→ window_manager
/// （仅全屏切换）。控件 UI 直接复用 DesktopPlayerControls。
class MacPlayerScreen extends StatefulWidget {
  const MacPlayerScreen({
    super.key,
    required this.drama,
    this.initialEpisode,
    this.engine,
  });

  final Drama drama;
  final int? initialEpisode;
  final PlaybackEngine? engine;

  @override
  State<MacPlayerScreen> createState() => _MacPlayerScreenState();
}

class _MacPlayerScreenState extends State<MacPlayerScreen>
    with WidgetsBindingObserver, WindowListener {
  late final AppController _app;
  late final PlaybackEngine _engine;
  late final PlaybackSession _session;
  late final DeviceControls _device;
  final _focus = FocusNode(debugLabel: 'Mac player');
  final _episodesScroll = ScrollController();
  bool _controlsVisible = true;
  bool _keyboardNavigation = false;
  bool _hidden = false;
  bool _heldForMinimize = false;
  bool _awake = false;
  bool _wasPlaying = false;
  bool _closing = false;
  bool _leaving = false;
  bool _allowPop = false;
  bool _fullScreen = false;
  bool _miniMode = false;
  _MacPanel? _panel;
  Duration? _seekPreview;
  Duration? _keyboardSeek;
  late double _volume;
  double _unmutedVolume = .75;
  String? _notice;
  Timer? _hideTimer;
  Timer? _noticeTimer;
  Future<void>? _closeFuture;

  @override
  void initState() {
    super.initState();
    _app = AppScope.read(context);
    _engine = widget.engine ?? MediaKitEngine();
    _device = DeviceControls(_engine);
    _volume = _app.preferences.desktopVolume;
    if (_volume > 0) _unmutedVolume = _volume;
    _session = PlaybackSession(app: _app, engine: _engine, drama: widget.drama);
    _session.addListener(_sessionChanged);
    _app.addListener(_preferencesChanged);
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_prepareDevice());
    _syncPauseReasons();
    unawaited(_session.initialize(initialEpisode: widget.initialEpisode));
  }

  Future<void> _prepareDevice() async {
    await _device.initialize();
    if (!_closing) await _device.setVolume(_volume);
  }

  void _sessionChanged() {
    if (!mounted || _closing) return;
    final playing = _session.playing;
    if (_wasPlaying != playing) {
      _wasPlaying = playing;
      _showControls();
    }
    _updateAwake();
    setState(() {});
  }

  void _preferencesChanged() {
    if (_closing) return;
    _syncPauseReasons();
    final volume = _app.preferences.desktopVolume;
    if (_volume != volume) {
      _volume = volume;
      unawaited(_device.setVolume(volume));
    }
    setState(() {});
  }

  void _syncPauseReasons() {
    if (_app.preferences.pauseWhenMinimized) {
      if (_hidden && !_heldForMinimize) {
        _heldForMinimize = true;
        _session.hold('minimized');
      }
    } else {
      if (_heldForMinimize) {
        _heldForMinimize = false;
        _session.release('minimized');
      }
    }
  }

  void _updateAwake() {
    final should = _session.playing && !_hidden;
    if (should != _awake) {
      _awake = should;
      unawaited(_device.keepAwake(should));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closing) return;
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _hidden = true;
      _session.hold('system');
      _syncPauseReasons();
    } else if (state == AppLifecycleState.resumed) {
      _hidden = false;
      _session.release('system');
      _syncPauseReasons();
    }
    _updateAwake();
  }

  @override
  void onWindowMinimize() {
    _hidden = true;
    _syncPauseReasons();
    _updateAwake();
  }

  @override
  void onWindowRestore() {
    _hidden = false;
    _syncPauseReasons();
    _updateAwake();
  }

  @override
  void onWindowClose() => unawaited(_closeSession());

  void _mouseActivity() {
    if (_keyboardNavigation) {
      _keyboardNavigation = false;
    }
    _showControls();
  }

  void _showControls() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _hideTimer?.cancel();
    if (_session.playing && _panel == null) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _panel == null) {
          setState(() => _controlsVisible = false);
        }
      });
    }
  }

  void _command(DesktopPlayerCommand cmd, bool accelerated) {
    _focus.requestFocus();
    switch (cmd) {
      case DesktopPlayerCommand.playPause:
        _session.togglePlay();
        _showControls();
      case DesktopPlayerCommand.seekBack:
        _seekBy(accelerated ? -30 : -5);
      case DesktopPlayerCommand.seekForward:
        _seekBy(accelerated ? 30 : 5);
      case DesktopPlayerCommand.volumeUp:
        _setVolume((_volume + .05).clamp(0, 1));
      case DesktopPlayerCommand.volumeDown:
        _setVolume((_volume - .05).clamp(0, 1));
      case DesktopPlayerCommand.mute:
        _toggleMute();
      case DesktopPlayerCommand.fullScreen:
        _toggleFullScreen();
      case DesktopPlayerCommand.back:
        unawaited(_escape());
      case DesktopPlayerCommand.previous:
        _changeEpisode(false);
      case DesktopPlayerCommand.next:
        _changeEpisode(true);
      case DesktopPlayerCommand.episodes:
        _openPanel(_panel == _MacPanel.episodes ? null : _MacPanel.episodes);
    }
  }

  Future<void> _seekBy(int seconds) async {
    if (!_session.ready || _session.duration <= Duration.zero) return;
    final next = Duration(
      milliseconds:
          ((_keyboardSeek ?? _session.position).inMilliseconds +
                  seconds * 1000)
              .clamp(0, _session.duration.inMilliseconds),
    );
    _keyboardSeek = next;
    _showNotice(seconds > 0 ? '快进 $seconds 秒' : '后退 ${-seconds} 秒');
    setState(() => _seekPreview = next);
    await _session.seek(next);
  }

  Future<void> _setVolume(double value) async {
    _volume = value;
    if (value > 0) _unmutedVolume = value;
    _app.setPreferences(_app.preferences.copyWith(desktopVolume: value));
    await _device.setVolume(value);
    setState(() {});
  }

  Future<void> _toggleMute() async {
    if (_volume > 0) {
      _unmutedVolume = _volume;
      await _setVolume(0);
    } else {
      await _setVolume(_unmutedVolume);
    }
  }

  Future<void> _toggleFullScreen() async {
    await windowManager.setFullScreen(!_fullScreen);
  }

  /// 切换摸鱼小窗模式：缩小窗口 + 置顶，方便边看边做其他事。
  Future<void> _toggleMiniMode() async {
    if (_miniMode) {
      // 恢复正常窗口 + 居中
      await windowManager.setMinimumSize(const Size(860, 560));
      await windowManager.setSize(const Size(1180, 780));
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      await windowManager.center();
      setState(() => _miniMode = false);
    } else {
      // 进入小窗模式
      if (_fullScreen) await windowManager.setFullScreen(false);
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setMinimumSize(const Size(280, 180));
      await windowManager.setSize(const Size(380, 240));
      await windowManager.setAlwaysOnTop(true);
      setState(() {
        _miniMode = true;
        _controlsVisible = true;
      });
    }
  }

  @override
  void onWindowEnterFullScreen() => setState(() => _fullScreen = true);

  @override
  void onWindowLeaveFullScreen() => setState(() => _fullScreen = false);

  Future<void> _changeEpisode(bool next) async {
    if (next ? !_session.canNext : !_session.canPrevious) return;
    _keyboardSeek = null;
    unawaited(next ? _session.next() : _session.previous());
  }

  void _openPanel(_MacPanel? panel) {
    setState(() {
      _panel = panel;
      _controlsVisible = true;
    });
    _hideTimer?.cancel();
    _focus.requestFocus();
    if (panel == _MacPanel.episodes) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_episodesScroll.hasClients) {
          _episodesScroll.jumpTo(
            math.min(
              (_session.currentIndex ~/ 5) * 50.0,
              _episodesScroll.position.maxScrollExtent,
            ),
          );
        }
      });
    }
  }

  void _closePanel() {
    setState(() => _panel = null);
    _focus.requestFocus();
    _showControls();
  }

  Future<void> _escape() async {
    if (_panel != null) {
      _closePanel();
    } else if (_fullScreen) {
      await windowManager.setFullScreen(false);
    } else {
      await _leave();
    }
  }

  Future<void> _closeSession() => _closeFuture ??= _doCloseSession();
  Future<void> _doCloseSession() async {
    _closing = true;
    _hideTimer?.cancel();
    _noticeTimer?.cancel();
    await _session.close();
    await _device.keepAwake(false);
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    // 退出前恢复窗口状态（小窗/全屏都要恢复 + 居中）
    if (_miniMode) {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      await windowManager.setMinimumSize(const Size(860, 560));
      await windowManager.setSize(const Size(1180, 780));
      await windowManager.center();
    }
    if (_fullScreen) await windowManager.setFullScreen(false);
    await _closeSession();
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  void _showNotice(String text) {
    setState(() => _notice = text);
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  // ── Seek scrub ──
  void _onSeekStart(double value) {
    _session.hold('scrub');
    setState(() => _seekPreview = _session.position);
  }

  Future<void> _onSeek(double value) async {
    if (!_session.ready || _session.duration <= Duration.zero) return;
    final next = Duration(
      milliseconds: (_session.duration.inMilliseconds * value).round(),
    );
    setState(() => _seekPreview = next);
  }

  Future<void> _onSeekEnd(double value) async {
    if (!_session.ready || _session.duration <= Duration.zero) return;
    final next = Duration(
      milliseconds: (_session.duration.inMilliseconds * value).round(),
    );
    _keyboardSeek = null;
    await _session.seek(next);
    _session.release('scrub');
    setState(() => _seekPreview = null);
  }

  void _onSeekCancel() {
    _session.release('scrub');
    setState(() => _seekPreview = null);
  }

  @override
  void dispose() {
    _closing = true;
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    _hideTimer?.cancel();
    _noticeTimer?.cancel();
    _app.removeListener(_preferencesChanged);
    _session.removeListener(_sessionChanged);
    unawaited(_closeSession());
    _session.dispose();
    unawaited(_device.dispose());
    _focus.dispose();
    _episodesScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    return Theme(
      data: ReelTheme.make(Brightness.dark),
      child: PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_escape());
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: DesktopPlayerInput(
            focusNode: _focus,
            onCommand: _command,
            allowPlayback: _panel == null && !_closing,
            onKeyboardNavigation: () {
              _keyboardNavigation = true;
              _showControls();
            },
            child: MouseRegion(
              cursor: _controlsVisible || _panel != null
                  ? MouseCursor.defer
                  : SystemMouseCursors.none,
              onHover: (_) => _mouseActivity(),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // 视频画面
                      engine is MediaKitEngine
                          ? Video(
                              key: ObjectKey(engine.video),
                              controller: engine.video,
                              fit: BoxFit.contain,
                              controls: NoVideoControls,
                              pauseUponEnteringBackgroundMode: false,
                              resumeUponEnteringForegroundMode: false,
                              wakelock: false,
                            )
                          : const ColoredBox(color: Colors.black),
                      // 点击层
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _focus.requestFocus();
                          _session.togglePlay();
                          _showControls();
                        },
                        onDoubleTap: _toggleFullScreen,
                        onSecondaryTap: () =>
                            _openPanel(_panel == _MacPanel.menu
                                ? null
                                : _MacPanel.menu),
                        child: const SizedBox.expand(),
                      ),
                      // 加载指示
                      if (_session.showLoading)
                        IgnorePointer(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    color: Colors.white70,
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _session.loadingDetail
                                      ? '正在加载短剧…'
                                      : _session.loadingMessage ?? '正在缓冲…',
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // 暂停图标
                      if (!_session.playing &&
                          !_session.buffering &&
                          !_session.loadingDetail &&
                          _session.error == null)
                        const IgnorePointer(
                          child: Center(
                            child: Icon(
                              Icons.play_circle_outline_rounded,
                              size: 62,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                      // 错误
                      if (_session.error != null)
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.cloud_off_outlined,
                                    color: Colors.white54,
                                    size: 36,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _session.error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      height: 1.6,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  FilledButton.icon(
                                    onPressed: _session.retry,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('重新播放'),
                                  ),
                                  if (_session.canNext)
                                    TextButton(
                                      onPressed: () => _changeEpisode(true),
                                      child: const Text('试试下一集'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      // 通知
                      if (_notice != null)
                        IgnorePointer(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _notice!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // 顶部标题栏
                      if (_controlsVisible || _panel != null)
                        _MacPlayerTopBar(
                          title: widget.drama.title,
                          episodeLabel: _session.episodes.isEmpty
                              ? null
                              : '第 ${_session.currentIndex + 1} 集',
                          fullScreen: _fullScreen,
                          miniMode: _miniMode,
                          onBack: _leave,
                          onFullScreen: _toggleFullScreen,
                          onMiniMode: _toggleMiniMode,
                        ),
                      // 底部控制栏（小窗模式下隐藏）
                      if ((_controlsVisible || _panel != null) && !_miniMode)
                        _MacPlayerBottomBar(
                          playing: _session.playing,
                          position: _seekPreview ?? _session.position,
                          duration: _session.duration,
                          buffer: _session.snapshot.buffer,
                          volume: _volume,
                          speed: _session.rate,
                          canPrevious: _session.canPrevious,
                          canNext: _session.canNext,
                          onPlayPause: () {
                            _session.togglePlay();
                            _showControls();
                          },
                          onPrevious: () => _changeEpisode(false),
                          onNext: () => _changeEpisode(true),
                          onVolume: _setVolume,
                          onMute: _toggleMute,
                          onEpisodes: () => _openPanel(
                            _panel == _MacPanel.episodes
                                ? null
                                : _MacPanel.episodes,
                          ),
                          onSpeed: () => _openPanel(
                            _panel == _MacPanel.speed
                                ? null
                                : _MacPanel.speed,
                          ),
                          onMenu: () => _openPanel(
                            _panel == _MacPanel.menu
                                ? null
                                : _MacPanel.menu,
                          ),
                          onFullScreen: _toggleFullScreen,
                          onSeekStart: _onSeekStart,
                          onSeek: _onSeek,
                          onSeekEnd: _onSeekEnd,
                          onSeekCancel: _onSeekCancel,
                        ),
                      // 面板
                      if (_panel != null) _buildPanel(),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel() {
    switch (_panel!) {
      case _MacPanel.episodes:
        return _episodesPanel();
      case _MacPanel.speed:
        return _speedPanel();
      case _MacPanel.menu:
        return _menuPanel();
    }
  }

  Widget _episodesPanel() {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 320,
        margin: const EdgeInsets.fromLTRB(0, 64, 16, 80),
        decoration: BoxDecoration(
          color: const Color(0xCF12141A),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  const Text(
                    '选集',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: Colors.white54,
                    onPressed: _closePanel,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _episodesScroll,
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: _session.episodes.length,
                itemBuilder: (context, index) {
                  final current = index == _session.currentIndex;
                  return InkWell(
                    onTap: () {
                      unawaited(_session.playEpisode(index));
                      _closePanel();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: current
                            ? const Color(0xFF1F2330)
                            : Colors.transparent,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: current
                                  ? const Color(0xFFFF3D6B)
                                  : const Color(0xFF2A2E3A),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: current
                                    ? Colors.white
                                    : Colors.white60,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '第 ${index + 1} 集',
                              style: TextStyle(
                                color: current
                                    ? Colors.white
                                    : Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (current)
                            const Icon(
                              Icons.play_arrow_rounded,
                              color: Color(0xFFFF3D6B),
                              size: 16,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _speedPanel() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.fromLTRB(0, 0, 0, 80),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xCF12141A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final speed in playbackSpeeds)
              TextButton(
                onPressed: () {
                  _session.setSpeed(speed);
                  _closePanel();
                },
                style: TextButton.styleFrom(
                  foregroundColor: _session.rate == speed
                      ? const Color(0xFFFF3D6B)
                      : Colors.white70,
                ),
                child: Text('${speed}x'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _menuPanel() {
    return Align(
      alignment: Alignment.topRight,
      child: Container(
        width: 220,
        margin: const EdgeInsets.fromLTRB(0, 64, 16, 0),
        decoration: BoxDecoration(
          color: const Color(0xCF12141A),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _menuItem(
              Icons.favorite_rounded,
              _app.isFavorite(widget.drama.id) ? '取消收藏' : '收藏',
              () {
                _app.toggleFavorite(widget.drama);
                _closePanel();
              },
            ),
            _menuItem(
              Icons.skip_next_rounded,
              '播放下一集',
              _session.canNext
                  ? () {
                      _changeEpisode(true);
                      _closePanel();
                    }
                  : null,
            ),
            _menuItem(
              Icons.skip_previous_rounded,
              '播放上一集',
              _session.canPrevious
                  ? () {
                      _changeEpisode(false);
                      _closePanel();
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.white70),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// macOS 播放器顶部标题栏：返回按钮 + 剧集标题 + 全屏按钮。
/// 贴合 macOS 视频播放器惯例（如 QuickTime / IINA）：顶部标题信息，底部控制。
class _MacPlayerTopBar extends StatelessWidget {
  const _MacPlayerTopBar({
    required this.title,
    required this.episodeLabel,
    required this.fullScreen,
    required this.miniMode,
    required this.onBack,
    required this.onFullScreen,
    required this.onMiniMode,
  });
  final String title;
  final String? episodeLabel;
  final bool fullScreen;
  final bool miniMode;
  final VoidCallback onBack;
  final VoidCallback onFullScreen;
  final VoidCallback onMiniMode;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: false,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xCC000000), Colors.transparent],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              miniMode ? 12 : 16,
              miniMode ? 28 : (fullScreen ? 16 : 12),
              16,
              24,
            ),
            child: Row(
              children: [
                // 返回按钮
                _MacPlayerIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: '返回 · Esc',
                  onTap: onBack,
                ),
                const SizedBox(width: 14),
                // 标题
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (episodeLabel != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          episodeLabel!,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // 悬浮小窗按钮（摸鱼模式）
                _MacPlayerIconButton(
                  icon: miniMode
                      ? Icons.open_in_full_rounded
                      : Icons.picture_in_picture_alt_rounded,
                  tooltip: miniMode ? '退出小窗' : '悬浮小窗 · 摸鱼',
                  onTap: onMiniMode,
                ),
                const SizedBox(width: 4),
                // 全屏按钮
                _MacPlayerIconButton(
                  icon: fullScreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  tooltip: fullScreen ? '退出全屏 · F' : '全屏 · F',
                  onTap: onFullScreen,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// macOS 播放器底部控制栏：进度条 + 控制按钮行。
class _MacPlayerBottomBar extends StatelessWidget {
  const _MacPlayerBottomBar({
    required this.playing,
    required this.position,
    required this.duration,
    required this.buffer,
    required this.volume,
    required this.speed,
    required this.canPrevious,
    required this.canNext,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onVolume,
    required this.onMute,
    required this.onEpisodes,
    required this.onSpeed,
    required this.onMenu,
    required this.onFullScreen,
    required this.onSeekStart,
    required this.onSeek,
    required this.onSeekEnd,
    required this.onSeekCancel,
  });
  final bool playing;
  final Duration position, duration, buffer;
  final double volume, speed;
  final bool canPrevious, canNext;
  final VoidCallback onPlayPause, onPrevious, onNext, onMute, onEpisodes,
      onSpeed, onMenu, onFullScreen, onSeekCancel;
  final ValueChanged<double> onVolume;
  final ValueChanged<double>? onSeekStart, onSeek, onSeekEnd;

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds;
    final fraction = total <= 0
        ? 0.0
        : (position.inMilliseconds / total).clamp(0.0, 1.0);
    final buffered = total <= 0
        ? 0.0
        : (buffer.inMilliseconds / total).clamp(fraction, 1.0);
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xE6000000), Colors.transparent],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 时间 + 进度条
              Row(
                children: [
                  Text(
                    formatTime(position),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 24,
                      child: Listener(
                        onPointerCancel: (_) => onSeekCancel(),
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 10,
                            ),
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5,
                            ),
                            secondaryActiveTrackColor: Colors.white24,
                          ),
                          child: Slider(
                            value: fraction,
                            secondaryTrackValue: buffered,
                            onChangeStart: onSeekStart,
                            onChanged: onSeek,
                            onChangeEnd: onSeekEnd,
                            semanticFormatterCallback: (value) => formatTime(
                              Duration(
                                milliseconds: (total * value).round(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatTime(duration),
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11.5,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 按钮行
              Row(
                children: [
                  _MacPlayerIconButton(
                    icon: Icons.skip_previous_rounded,
                    tooltip: '上一集 · PageUp',
                    onTap: canPrevious ? onPrevious : null,
                  ),
                  const SizedBox(width: 8),
                  _MacPlayerIconButton(
                    icon: playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    tooltip: '播放 / 暂停 · 空格',
                    onTap: onPlayPause,
                    highlighted: true,
                  ),
                  const SizedBox(width: 8),
                  _MacPlayerIconButton(
                    icon: Icons.skip_next_rounded,
                    tooltip: '下一集 · PageDown',
                    onTap: canNext ? onNext : null,
                  ),
                  const SizedBox(width: 16),
                  _MacPlayerIconButton(
                    icon: volume == 0
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    tooltip: '音量 ${(volume * 100).round()}% · M 静音',
                    onTap: onMute,
                  ),
                  SizedBox(
                    width: 80,
                    child: Slider(
                      value: volume,
                      onChanged: onVolume,
                      semanticFormatterCallback: (value) =>
                          '音量 ${(value * 100).round()}%',
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onSpeed,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: Text(
                      '${speed}x',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  _MacPlayerIconButton(
                    icon: Icons.playlist_play_rounded,
                    tooltip: '选集 · E',
                    onTap: onEpisodes,
                  ),
                  _MacPlayerIconButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: '播放菜单',
                    onTap: onMenu,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// macOS 播放器圆形图标按钮。
class _MacPlayerIconButton extends StatefulWidget {
  const _MacPlayerIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.highlighted = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  State<_MacPlayerIconButton> createState() => _MacPlayerIconButtonState();
}

class _MacPlayerIconButtonState extends State<_MacPlayerIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: widget.highlighted
                  ? const Color(0xFFFF3D6B)
                  : (_hover && enabled
                      ? Colors.white.withValues(alpha: .12)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color: widget.highlighted
                  ? Colors.white
                  : (enabled ? Colors.white : Colors.white30),
            ),
          ),
        ),
      ),
    );
  }
}

enum _MacPanel { episodes, speed, menu }
