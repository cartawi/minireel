import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../domain/models/drama.dart';
import '../desktop/desktop_navigation.dart';
import '../desktop/desktop_window.dart';
import '../desktop/window_chrome.dart';
import '../domain/models/preferences.dart';
import '../features/library/library_screen.dart';
import '../features/mine/mine_screen.dart';
import '../features/player/player_screen.dart';
import '../features/player/desktop_player_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/tv/tv_shell.dart';
import '../features/tv/tv_player_screen.dart';
import '../features/tv/tv_debug_pad.dart';
import 'app_controller.dart';
import 'theme.dart';
import 'platform.dart';

class MiniReelApp extends StatefulWidget {
  const MiniReelApp({super.key, required this.controller});
  final AppController controller;

  @override
  State<MiniReelApp> createState() => _MiniReelAppState();
}

class _MiniReelAppState extends State<MiniReelApp> {
  final _rootFocus = FocusNode(debugLabel: 'mini-reel-root');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rootFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _rootFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onRootKey(FocusNode node, KeyEvent event) {
    // F9：调试时切换强制 TV 模式（用键盘方向键模拟遥控器）
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.f9) {
      toggleDebugTvMode();
      setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => AppScope(
    controller: widget.controller,
    child: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => MaterialApp(
        title: 'MiniReel',
        debugShowCheckedModeBanner: false,
        theme: ReelTheme.make(Brightness.light),
        darkTheme: ReelTheme.make(Brightness.dark),
        themeMode: switch (widget.controller.preferences.appearance) {
          AppAppearance.system => ThemeMode.system,
          AppAppearance.light => ThemeMode.light,
          AppAppearance.dark => ThemeMode.dark,
        },
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          final scale =
              media.textScaler.scale(1) *
              (widget.controller.preferences.largeText ? 1.18 : 1);
          return MediaQuery(
            data: media.copyWith(textScaler: TextScaler.linear(scale)),
            child: TVDebugPad(
              child: isWindowsDesktop
                ? ListenableBuilder(
                    listenable: DesktopWindow.instance,
                    child: child,
                    builder: (context, navigator) => Overlay.wrap(
                      child: Column(
                        children: [
                          if (!DesktopWindow.instance.inPlayer)
                            const DesktopTitleBar(),
                          Expanded(child: navigator!),
                        ],
                      ),
                    ),
                  )
                : child!,
            ),
          );
        },
        home: Focus(
          focusNode: _rootFocus,
          onKeyEvent: _onRootKey,
          child: const _AppShell(),
        ),
      ),
    ),
  );
}

class _AppShell extends StatefulWidget {
  const _AppShell();
  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _tab = 0;
  bool _openingPlayer = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(AppScope.read(context).repository.refresh());
    });
  }

  Future<void> _play(Drama drama, [int? episode]) async {
    if (_openingPlayer) return;
    _openingPlayer = true;
    try {
      await Navigator.of(context).push(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => isAndroidTV
              ? TVPlayerScreen(drama: drama, initialEpisode: episode)
              : (isWindowsDesktop
                  ? DesktopPlayerScreen(drama: drama, initialEpisode: episode)
                  : PlayerScreen(drama: drama, initialEpisode: episode)),
          transitionDuration: const Duration(milliseconds: 240),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (_, animation, _, child) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(begin: const Offset(.08, 0), end: Offset.zero)
                  .animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
          ),
        ),
      );
    } finally {
      _openingPlayer = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.watch(context);
    final content = Column(
      children: [
        if (app.persistenceError != null)
          MaterialBanner(
            content: Text(
              app.persistenceError!,
              style: const TextStyle(fontSize: 12),
            ),
            actions: [
              TextButton(
                onPressed: () => setState(() => app.persistenceError = null),
                child: const Text('知道了'),
              ),
            ],
          ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              LibraryScreen(onPlay: _play),
              MineScreen(
                onPlay: _play,
                onExplore: () => setState(() => _tab = 0),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isWindowsDesktop ? 900 : double.infinity,
                  ),
                  child: const SettingsScreen(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: context.dark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: context.dark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: isAndroidTV
              ? const TVAppShell()
              : (isWindowsDesktop
                  ? Row(
                      children: [
                        DesktopNavigation(
                          selected: _tab,
                          onSelect: (tab) => setState(() => _tab = tab),
                        ),
                        Expanded(child: content),
                      ],
                    )
                  : content),
        ),
        bottomNavigationBar: isAndroidTV || isWindowsDesktop ? null : Container(
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).dividerColor,
                      width: .7,
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 3, 16, 5),
                    child: Row(
                      children: [
                        _navigation(
                          0,
                          Icons.movie_outlined,
                          Icons.movie_rounded,
                          '短剧库',
                        ),
                        _navigation(
                          1,
                          Icons.person_outline_rounded,
                          Icons.person_rounded,
                          '我的',
                        ),
                        _navigation(
                          2,
                          Icons.tune_rounded,
                          Icons.tune_rounded,
                          '设置',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _navigation(
    int tab,
    IconData icon,
    IconData selectedIcon,
    String label,
  ) {
    final selected = tab == _tab;
    final color = selected ? context.colors.primary : context.muted;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        child: InkWell(
          key: ValueKey('tab-$tab'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _tab = tab),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? selectedIcon : icon, size: 22, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: color,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
