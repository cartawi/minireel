import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../domain/models/drama.dart';
import 'mac_library_screen.dart';
import 'mac_mine_screen.dart';
import 'mac_player_screen.dart';
import 'mac_settings_screen.dart';
import 'mac_theme.dart';

/// macOS 版主界面。
///
/// 原生 macOS app 布局：毛玻璃侧边栏（vibrancy）+ 平面内容区。
/// 侧边栏用 BackdropFilter 模拟 NSVisualEffectView，导航项紧凑（32px 高），
/// 选中态用 accent 半透明圆角块。内容区无圆角容器，贴合 macOS 原生
/// （Finder/邮件/音乐 都是侧边栏与内容区平齐，仅靠分隔线区分）。
class MacAppShell extends StatefulWidget {
  const MacAppShell({super.key});
  @override
  State<MacAppShell> createState() => _MacAppShellState();
}

class _MacAppShellState extends State<MacAppShell> {
  int _tab = 0;
  bool _openingPlayer = false;

  Future<void> _play(Drama drama, [int? episode]) async {
    if (_openingPlayer) return;
    _openingPlayer = true;
    try {
      await Navigator.of(context).push(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) =>
              MacPlayerScreen(drama: drama, initialEpisode: episode),
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          transitionsBuilder: (_, animation, _, child) => FadeTransition(
            opacity: animation,
            child: child,
          ),
        ),
      );
    } finally {
      _openingPlayer = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(AppScope.read(context).repository.refresh());
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.watch(context);
    return Theme(
      data: MacTheme.make(context.dark ? Brightness.dark : Brightness.light),
      child: Scaffold(
        body: Column(
          children: [
            if (app.persistenceError != null)
              MaterialBanner(
                content: Text(
                  app.persistenceError!,
                  style: const TextStyle(fontSize: 12),
                ),
                actions: [
                  TextButton(
                    onPressed: () =>
                        setState(() => app.persistenceError = null),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            Expanded(
              child: Row(
                children: [
                  _MacSidebar(
                    tab: _tab,
                    onSelect: (tab) => setState(() => _tab = tab),
                  ),
                  Expanded(child: _MacContent(tab: _tab, onPlay: _play)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// macOS 毛玻璃侧边栏。
///
/// 用 BackdropFilter + 半透明色模拟 NSVisualEffectView 的 vibrancy。
/// 顶部 52px 给原生交通灯让位（titleBarStyle: normal 时交通灯在标题栏，
/// 但侧边栏从顶部开始，留白让 logo 不与交通灯重叠）。
class _MacSidebar extends StatelessWidget {
  const _MacSidebar({required this.tab, required this.onSelect});
  final int tab;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final dark = context.dark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          width: 200,
          decoration: BoxDecoration(
            color: (dark ? MacTheme.sidebarDark : MacTheme.sidebarLight)
                .withValues(alpha: .72),
            border: Border(
              right: BorderSide(
                color: dark
                    ? MacTheme.separatorDark
                    : MacTheme.separatorLight,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 交通灯留白
              const SizedBox(height: 52),
              // logo + 品牌名
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: dark
                            ? const Color(0xFF2C2C2E)
                            : Colors.white,
                        borderRadius:
                            BorderRadius.circular(MacTheme.radiusControl),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .08),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/logo.png',
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      'MiniReel',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.colors.onSurface,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _MacNavItem(
                index: 0,
                icon: Icons.movie_outlined,
                selectedIcon: Icons.movie_rounded,
                label: '短剧库',
                selected: tab == 0,
                onSelect: onSelect,
              ),
              _MacNavItem(
                index: 1,
                icon: Icons.person_outline_rounded,
                selectedIcon: Icons.person_rounded,
                label: '我的',
                selected: tab == 1,
                onSelect: onSelect,
              ),
              const Spacer(),
              _MacNavItem(
                index: 2,
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings_rounded,
                label: '设置',
                selected: tab == 2,
                onSelect: onSelect,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// macOS 风格导航项：32px 高，选中态 accent 半透明圆角块。
class _MacNavItem extends StatefulWidget {
  const _MacNavItem({
    required this.index,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onSelect,
  });
  final int index;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final ValueChanged<int> onSelect;

  @override
  State<_MacNavItem> createState() => _MacNavItemState();
}

class _MacNavItemState extends State<_MacNavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = context.dark;
    final accent = context.colors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: () => widget.onSelect(widget.index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: widget.selected
                  ? context.macSelectionOverlay
                  : (_hover ? context.macTertiary : Colors.transparent),
              borderRadius: BorderRadius.circular(MacTheme.radiusControl),
            ),
            child: Row(
              children: [
                Icon(
                  widget.selected ? widget.selectedIcon : widget.icon,
                  size: 16,
                  color: widget.selected
                      ? accent
                      : (dark
                          ? const Color(0xFF98989F)
                          : const Color(0xFF636366)),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        widget.selected ? FontWeight.w600 : FontWeight.w500,
                    color: widget.selected
                        ? context.colors.onSurface
                        : (dark
                            ? const Color(0xFFD1D1D6)
                            : const Color(0xFF3A3A3C)),
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

/// 内容区：平面，无圆角容器。贴合 macOS 原生（侧边栏与内容区平齐）。
class _MacContent extends StatelessWidget {
  const _MacContent({required this.tab, required this.onPlay});
  final int tab;
  final void Function(Drama drama, [int? episode]) onPlay;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: tab,
      children: [
        MacLibraryScreen(onPlay: onPlay),
        MacMineScreen(onPlay: onPlay),
        const MacSettingsScreen(),
      ],
    );
  }
}
