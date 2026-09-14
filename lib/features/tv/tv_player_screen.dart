import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../domain/models/drama.dart';
import '../../domain/models/preferences.dart';
import '../../playback/device_controls.dart';
import '../../playback/media_kit_engine.dart';
import '../../playback/playback_session.dart';
import '../shared/widgets.dart';
import 'tv_focus.dart';

/// TV 版播放器。
///
/// 复用 PlaybackSession + MediaKitEngine + DeviceControls 的全部播放逻辑。
/// UI 全新：横屏固定、无手势、D-pad 控件栏。
/// 遥控器映射：
///   OK/ENTER → 播放/暂停（无焦点时）/ 激活按钮（有焦点时）
///   左右 → 焦点在控件间移动 / 长按快进快退 10s
///   上下 → 切换焦点区（视频区 ↔ 控件栏）
///   BACK → 退出播放器
///   MENU → 弹出选集/速度/画质面板
class TVPlayerScreen extends StatefulWidget {
  const TVPlayerScreen({super.key, required this.drama, this.initialEpisode});
  final Drama drama;
  final int? initialEpisode;
  @override
  State<TVPlayerScreen> createState() => _TVPlayerScreenState();
}

class _TVPlayerScreenState extends State<TVPlayerScreen>
    with WidgetsBindingObserver {
  late final AppController _app;
  late final MediaKitEngine _engine;
  late final PlaybackSession _session;
  late final DeviceControls _device;
  bool _controlsVisible = true;
  bool _sheetOpen = false;
  bool _foreground = true;
  bool _awake = false;
  bool _closing = false;
  bool _controlsFocused = false; // 焦点是否在底部控件栏按钮上
  final GlobalKey _controlsBarKey = GlobalKey();
  Timer? _hideTimer;
  // seek 预览
  Duration? _seekPreview;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _app = AppScope.read(context);
    _engine = MediaKitEngine();
    _device = DeviceControls(_engine);
    _session = PlaybackSession(
      app: _app,
      engine: _engine,
      drama: widget.drama,
    );
    _session.addListener(_sessionChanged);
    unawaited(_prepareDevice());
    unawaited(_session.initialize(initialEpisode: widget.initialEpisode));
    _showControls();
  }

  Future<void> _prepareDevice() async {
    if (Platform.isAndroid) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      if (!mounted || _closing) return;
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    await _device.initialize();
    if (mounted && !_closing) setState(() {});
  }

  void _sessionChanged() {
    if (!mounted || _closing) return;
    final awake = _foreground &&
        (_session.playing || _session.buffering) &&
        !_sheetOpen;
    if (awake != _awake) {
      _awake = awake;
      unawaited(_device.keepAwake(awake));
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closing) return;
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _session.release('background');
    } else {
      _session.boost(false);
      _session.hold('background');
    }
    _sessionChanged();
  }

  void _showControls() {
    _hideTimer?.cancel();
    _controlsVisible = true;
    if (mounted) setState(() {});
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted &&
          !_closing &&
          _session.playing &&
          !_sheetOpen &&
          _seekPreview == null &&
          !_controlsFocused) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  /// 焦点进入/离开控件栏时调用。
  void _onControlsFocusChanged(bool focused) {
    _controlsFocused = focused;
    if (focused && !_controlsVisible) {
      _showControls();
    } else if (focused) {
      // 焦点在控件栏时，取消自动隐藏
      _hideTimer?.cancel();
    }
  }

  void _togglePlay() {
    _session.togglePlay();
    _showControls();
  }

  /// 遥控器左右键 seek：快进/快退 10s
  void _seekBy(Duration delta) {
    if (_session.duration == Duration.zero) return;
    final current = _seekPreview ?? _session.position;
    var target = current + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (target > _session.duration) target = _session.duration;
    _seekPreview = target;
    _showControls();
    // 防抖：停止操作 800ms 后真正 seek
    _seekDebounce?.cancel();
    _seekDebounce = Timer(const Duration(milliseconds: 800), () {
      if (_seekPreview != null && mounted) {
        unawaited(_session.seek(_seekPreview!));
        _seekPreview = null;
        setState(() {});
      }
    });
  }

  Timer? _seekDebounce;

  void _changeEpisode(bool next) {
    if (_session.episodes.isEmpty) return;
    if (next && !_session.canNext) return;
    if (!next && !_session.canPrevious) return;
    unawaited(next ? _session.next() : _session.previous());
    _showControls();
  }

  Future<void> _openMenu() async {
    if (_sheetOpen) return;
    _session.hold('sheet');
    setState(() => _sheetOpen = true);
    _sessionChanged();
    try {
      await showReelSheet<void>(
        context,
        dark: true,
        builder: (context) => ListenableBuilder(
          listenable: _app,
          builder: (context, _) => _menuContent(context),
        ),
      );
    } finally {
      if (mounted && !_closing) {
        setState(() => _sheetOpen = false);
        _session.release('sheet');
        _showControls();
      }
    }
  }

  Widget _menuContent(BuildContext context) => SheetFrame(
    title: _session.drama.title,
    subtitle:
        '第 ${_session.episode?.index ?? 1} 集 · 共 ${_session.episodes.length} 集',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _menuAction(context, Icons.grid_view_rounded, '选集', () {
              Navigator.of(context).pop();
              _openEpisodes();
            }),
            _menuAction(
              context,
              _app.isFavorite(_session.drama.id)
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              _app.isFavorite(_session.drama.id) ? '已收藏' : '收藏',
              () => _app.toggleFavorite(_session.drama),
              active: _app.isFavorite(_session.drama.id),
            ),
            _menuAction(
              context,
              Icons.speed_rounded,
              '${_app.preferences.speed}x',
              () {
                Navigator.of(context).pop();
                _openSpeed();
              },
            ),
            _menuAction(
              context,
              Icons.high_quality_outlined,
              _session.currentQuality,
              () {
                Navigator.of(context).pop();
                _openQuality();
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_session.drama.intro.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _session.drama.intro,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                height: 1.7,
              ),
            ),
          ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _exit();
            },
            icon: const Icon(Icons.logout_rounded, size: 19),
            label: const Text('退出播放'),
          ),
        ),
      ],
    ),
  );

  Widget _menuAction(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TVFocusable(
        radius: 14,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: active
                ? context.colors.primary.withValues(alpha: .12)
                : Colors.white.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 24,
                color: active ? context.colors.primary : Colors.white70,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: active ? context.colors.primary : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _openEpisodes() async {
    _session.hold('sheet');
    setState(() => _sheetOpen = true);
    try {
      final result = await showReelSheet<Episode>(
        context,
        dark: true,
        builder: (context) => SheetFrame(
          title: '选集',
          subtitle: '共 ${_session.episodes.length} 集',
          child: _EpisodeGrid(
            episodes: _session.episodes,
            current: _session.episode?.index,
            onSelect: (episode) => Navigator.of(context).pop(episode),
          ),
        ),
      );
      if (result != null) {
        final index = _session.episodes.indexOf(result);
        unawaited(_session.playEpisode(index));
      }
    } finally {
      if (mounted && !_closing) {
        setState(() => _sheetOpen = false);
        _session.release('sheet');
        _showControls();
      }
    }
  }

  Future<void> _openSpeed() async {
    _session.hold('sheet');
    setState(() => _sheetOpen = true);
    try {
      final result = await showReelSheet<double>(
        context,
        dark: true,
        builder: (context) => SheetFrame(
          title: '倍速',
          subtitle: '当前 ${_app.preferences.speed}x',
          child: LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                for (final speed in playbackSpeeds)
                  SizedBox(
                    width: (constraints.maxWidth - 18) / 3,
                    child: TVFocusable(
                      radius: 12,
                      onTap: () => Navigator.of(context).pop(speed),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: speed == _app.preferences.speed
                              ? context.colors.primary
                              : Colors.white.withValues(alpha: .08),
                        ),
                        onPressed: null,
                        child: Text('${speed}x'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      if (result != null) _session.setSpeed(result);
    } finally {
      if (mounted && !_closing) {
        setState(() => _sheetOpen = false);
        _session.release('sheet');
        _showControls();
      }
    }
  }

  Future<void> _openQuality() async {
    final choices = _session.options?.sources.map((s) => s.quality).toSet() ??
        {_session.currentQuality};
    _session.hold('sheet');
    setState(() => _sheetOpen = true);
    try {
      final result = await showReelSheet<String>(
        context,
        dark: true,
        builder: (context) => SheetFrame(
          title: '画质',
          subtitle: choices.length == 1 ? '这集提供一种画质' : '切换后会保留当前播放进度',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final quality in choices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: TVFocusable(
                    radius: 12,
                    onTap: () => Navigator.of(context).pop(quality),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        quality,
                        style: TextStyle(
                          fontSize: 15,
                          color: quality == _session.currentQuality
                              ? context.colors.primary
                              : Colors.white,
                        ),
                      ),
                      trailing: quality == _session.currentQuality
                          ? Icon(
                              Icons.check_rounded,
                              color: context.colors.primary,
                              size: 20,
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      if (result != null) unawaited(_session.setQuality(result));
    } finally {
      if (mounted && !_closing) {
        setState(() => _sheetOpen = false);
        _session.release('sheet');
        _showControls();
      }
    }
  }

  void _exit() {
    _closing = true;
    unawaited(_session.close());
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _closing = true;
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _seekDebounce?.cancel();
    _session.removeListener(_sessionChanged);
    _session.dispose();
    unawaited(_device.dispose());
    if (Platform.isAndroid) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
      unawaited(SystemChrome.setPreferredOrientations([]));
    }
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_sheetOpen) return KeyEventResult.ignored;
    final key = event.logicalKey;
    // BACK / ESC → 退出
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      _exit();
      return KeyEventResult.handled;
    }
    // MENU → 打开菜单
    if (key == LogicalKeyboardKey.contextMenu ||
        key == LogicalKeyboardKey.f1) {
      unawaited(_openMenu());
      return KeyEventResult.handled;
    }
    // 焦点在控件栏按钮上时，方向键和 OK 交给 TVFocusable 处理（移动焦点 / 激活按钮）
    if (_controlsFocused) {
      // 仅处理上下：上键收起控件栏焦点回到视频区
      if (key == LogicalKeyboardKey.arrowUp) {
        // 离开控件栏，回到视频区（无焦点）
        FocusScope.of(context).unfocus();
        _showControls();
        return KeyEventResult.handled;
      }
      // 左右/OK/ENTER/SPACE 由 TVFocusable 自行处理
      return KeyEventResult.ignored;
    }
    // 以下：焦点不在控件栏（视频区无焦点）
    // OK/ENTER/SPACE → 播放暂停
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      if (!_controlsVisible) {
        _showControls();
        return KeyEventResult.handled;
      }
      _togglePlay();
      return KeyEventResult.handled;
    }
    // 左右 → seek 10s
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (!_controlsVisible) {
        _showControls();
        return KeyEventResult.handled;
      }
      _seekBy(const Duration(seconds: -10));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (!_controlsVisible) {
        _showControls();
        return KeyEventResult.handled;
      }
      _seekBy(const Duration(seconds: 10));
      return KeyEventResult.handled;
    }
    // 下 → 显示控件栏并聚焦到播放按钮
    if (key == LogicalKeyboardKey.arrowDown) {
      _showControls();
      // 聚焦到控件栏（播放按钮 autofocus）
      _requestControlsFocus();
      return KeyEventResult.handled;
    }
    // 上 → 显示控件
    if (key == LogicalKeyboardKey.arrowUp) {
      _showControls();
      return KeyEventResult.handled;
    }
    // 媒体键
    if (key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(const Duration(seconds: 10));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaRewind) {
      _seekBy(const Duration(seconds: -10));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 请求焦点进入控件栏。
  void _requestControlsFocus() {
    final scope = _controlsBarKey.currentContext;
    if (scope != null) {
      final node = FocusScope.of(scope);
      node.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          node.traversalChildren.firstOrNull?.requestFocus();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayed = _seekPreview ?? _session.position;
    final fraction = _session.duration.inMilliseconds <= 0
        ? 0.0
        : (displayed.inMilliseconds / _session.duration.inMilliseconds)
            .clamp(0.0, 1.0);
    return Theme(
      data: ReelTheme.make(Brightness.dark),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _exit();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Focus(
            onKeyEvent: _onKey,
            autofocus: true,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 视频层
                Video(
                  controller: _engine.video,
                  fit: BoxFit.contain,
                  controls: NoVideoControls,
                  pauseUponEnteringBackgroundMode: false,
                  resumeUponEnteringForegroundMode: false,
                  wakelock: false,
                ),
                // 加载/缓冲指示
                if (_session.loadingDetail || _session.buffering)
                  IgnorePointer(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _session.loadingDetail
                                ? '正在加载短剧…'
                                : _session.resolving
                                ? (_session.loadingMessage ?? '正在加载本集…')
                                : '正在缓冲…',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // 暂停指示
                if (!_session.playing &&
                    !_session.buffering &&
                    !_session.loadingDetail &&
                    _session.error == null &&
                    !_sheetOpen)
                  IgnorePointer(
                    child: Center(
                      child: _glass(
                        radius: 42,
                        child: const Padding(
                          padding: EdgeInsets.all(22),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                    ),
                  ),
                // 错误提示
                if (_session.error != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: _glass(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.cloud_off_outlined,
                                size: 36,
                                color: Colors.white70,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _session.error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  height: 1.6,
                                ),
                              ),
                              const SizedBox(height: 22),
                              TVFocusable(
                                radius: 12,
                                onTap: _session.retry,
                                child: FilledButton.icon(
                                  onPressed: null,
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 19,
                                  ),
                                  label: const Text('重新播放'),
                                ),
                              ),
                              if (_session.canNext)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: TVFocusable(
                                    radius: 12,
                                    onTap: () => _changeEpisode(true),
                                    child: TextButton(
                                      onPressed: null,
                                      child: const Text('试试下一集'),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                // seek HUD
                if (_seekPreview != null)
                  IgnorePointer(
                    child: Center(
                      child: _glass(
                        radius: 20,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          child: Text(
                            '${formatTime(_seekPreview!)} / ${formatTime(_session.duration)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // 顶部信息栏 + 底部控件栏
                if (_controlsVisible && !_sheetOpen) ...[
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: 1,
                        duration: const Duration(milliseconds: 240),
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xAA000000), Colors.transparent],
                            ),
                          ),
                          child: SafeArea(
                            bottom: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                16,
                                24,
                                36,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _session.drama.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '第 ${_session.episode?.index ?? 1} 集 · 共 ${_session.episodes.length} 集',
                                          style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _bottomControls(fraction),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomControls(double fraction) => Focus(
    key: _controlsBarKey,
    canRequestFocus: false,
    descendantsAreFocusable: true,
    onFocusChange: _onControlsFocusChanged,
    child: FocusTraversalGroup(
      policy: TVFocusTraversalPolicy(),
      child: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 40, 32, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度条
            Row(
              children: [
                Text(
                  formatTime(_seekPreview ?? _session.position),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 5,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation(
                        context.colors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  formatTime(_session.duration),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 控件按钮行
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ctrlButton(
                  Icons.skip_previous_rounded,
                  '上一集',
                  _session.canPrevious ? () => _changeEpisode(false) : null,
                ),
                const SizedBox(width: 20),
                _ctrlButton(
                  Icons.replay_10_rounded,
                  '快退 10s',
                  () => _seekBy(const Duration(seconds: -10)),
                ),
                const SizedBox(width: 20),
                _ctrlButton(
                  _session.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  _session.playing ? '暂停' : '播放',
                  _togglePlay,
                  big: true,
                  autofocus: true,
                ),
                const SizedBox(width: 20),
                _ctrlButton(
                  Icons.forward_10_rounded,
                  '快进 10s',
                  () => _seekBy(const Duration(seconds: 10)),
                ),
                const SizedBox(width: 20),
                _ctrlButton(
                  Icons.skip_next_rounded,
                  '下一集',
                  _session.canNext ? () => _changeEpisode(true) : null,
                ),
                const SizedBox(width: 20),
                _ctrlButton(
                  Icons.menu_rounded,
                  '菜单',
                  _openMenu,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
      ),
    ),
  );

  Widget _ctrlButton(
    IconData icon,
    String label,
    VoidCallback? onTap, {
    bool big = false,
    bool autofocus = false,
  }) => TVFocusable(
    radius: big ? 42 : 14,
    onTap: onTap,
    autofocus: autofocus,
    enableGlow: big,
    child: Container(
      padding: EdgeInsets.all(big ? 18 : 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(big ? 42 : 14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: big ? 36 : 26,
            color: onTap == null ? Colors.white24 : Colors.white,
          ),
          if (!big) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _glass({double radius = 28, required Widget child}) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xCF12141A),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.white12),
        ),
        child: child,
      ),
    ),
  );
}

/// TV 版选集网格：每集用 TVFocusable 包裹。
class _EpisodeGrid extends StatelessWidget {
  const _EpisodeGrid({
    required this.episodes,
    required this.current,
    required this.onSelect,
  });
  final List<Episode> episodes;
  final int? current;
  final void Function(Episode) onSelect;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = (constraints.maxWidth / 90).floor().clamp(4, 10);
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final episode in episodes)
            SizedBox(
              width: (constraints.maxWidth - (columns - 1) * 8) / columns,
              child: TVFocusable(
                radius: 12,
                onTap: () => onSelect(episode),
                autofocus: episode.index == current,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: episode.index == current
                        ? context.colors.primary
                        : Colors.white.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      '${episode.index}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: episode.index == current
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: episode.index == current
                            ? Colors.white
                            : Colors.white70,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
