import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../domain/models/drama.dart';
import '../shared/widgets.dart';
import 'tv_focus.dart';
import 'tv_library_screen.dart';
import 'tv_mine_screen.dart';
import 'tv_rankings_screen.dart';
import 'tv_player_screen.dart';
import 'tv_settings_screen.dart';

/// TV 版主界面。
///
/// 布局：左侧导航栏（图标 + 文字，~200 宽）+ 右侧内容区。
/// 设计继承：导航栏用 surface 背景 + divider 分隔（同 DesktopNavigation），
/// 选中项 accent 半透明背景 + 左侧 3px accent 竖条（同 library _category 动画竖条）。
/// 交互：D-pad 上下切换导航项，左右进入/离开内容区。
class TVAppShell extends StatefulWidget {
  const TVAppShell({super.key});
  @override
  State<TVAppShell> createState() => _TVAppShellState();
}

class _TVAppShellState extends State<TVAppShell> {
  int _tab = 0;
  bool _openingPlayer = false;
  /// 顶部搜索框的焦点节点：由 shell 统一持有，用于
  /// 1) 初始焦点落在搜索框（而非导航栏）
  /// 2) 从导航栏按→进入内容区时统一落到搜索框
  final _searchFocus = FocusNode(debugLabel: 'tv-shell-search');
  /// 内容区的焦点节点：切 tab 后用于把焦点从导航栏移到内容区。
  /// canRequestFocus=false，只作为遍历入口（requestFocus 后遍历其子节点）。
  final _contentScope = FocusNode(debugLabel: 'tv-shell-content-scope');

  Future<void> _play(Drama drama, [int? episode]) async {
    if (_openingPlayer) return;
    _openingPlayer = true;
    try {
      await Navigator.of(context).push(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) =>
              TVPlayerScreen(drama: drama, initialEpisode: episode),
          transitionDuration: const Duration(milliseconds: 240),
          reverseTransitionDuration: const Duration(milliseconds: 200),
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
    // 注册搜索框节点供导航栏→内容区跳转使用
    searchFocusNode = _searchFocus;
    // 初始内容区入口：短剧库的搜索框
    contentEntryFocusNode = _searchFocus;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 默认焦点：进入后红点在顶部搜索框
      _searchFocus.requestFocus();
      unawaited(AppScope.read(context).repository.refresh());
    });
  }

  @override
  void dispose() {
    searchFocusNode = null;
    contentEntryFocusNode = null;
    _searchFocus.dispose();
    _contentScope.dispose();
    super.dispose();
  }

  /// 切换 tab 并把焦点移到内容区。
  ///
  /// 导航项 onTap 调用。切 tab 后焦点若留在导航栏，用户按→会触发
  /// TVFocusTraversalPolicy 的「导航栏→内容区」特判，落到
  /// [contentEntryFocusNode]。这里在切 tab 时同步更新该入口节点，
  /// 并主动把焦点收到内容区，避免焦点留在导航栏。
  void _selectTab(int tab) {
    setState(() => _tab = tab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyContentEntry(tab);
    });
  }

  /// 根据当前 tab 设置内容区入口节点并把焦点收到内容区。
  ///
  /// - 短剧库：入口 = 搜索框（[_searchFocus]）
  /// - 热播榜：入口 = 左侧首个榜单类型节点（角色 `rankingsTypeFirst`）
  /// - 我的：入口 = segment「收藏」节点（角色 `mineEntry`）
  /// - 设置：入口 = 首个设置项节点（角色 `settingsEntry`）
  ///
  /// 用 [TVFocusRegistry] 角色查找而非 [findFirstFocus]，后者会遍历
  /// IndexedStack 所有子页（含隐藏 tab），返回 widget 树首个节点
  /// （短剧库搜索框），在「我的/设置」tab 会落到不可见节点。
  void _applyContentEntry(int tab) {
    if (tab == 0) {
      contentEntryFocusNode = _searchFocus;
      _searchFocus.requestFocus();
      return;
    }
    final role = switch (tab) {
      1 => 'rankingsTypeFirst',
      2 => 'mineEntry',
      3 => 'settingsEntry',
      _ => null,
    };
    if (role != null) {
      final entry = TVFocusRegistry.get(role);
      if (entry != null && entry.rect.width > 0) {
        contentEntryFocusNode = entry;
        entry.requestFocus();
        return;
      }
    }
    // 兜底：直接请求内容区 scope
    contentEntryFocusNode = _contentScope;
    _contentScope.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return TVDpadInterceptor(
      child: Scaffold(
      body: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Row(
          children: [
            // 导航栏独立焦点区：D-pad 在导航项间上下移动，右键进入内容区
            // 右键统一落到顶部搜索框（由 TVFocusTraversalPolicy 特判处理）
            FocusTraversalGroup(
              key: navRegionKey,
              policy: TVFocusTraversalPolicy(),
              child: _TVNavigation(
                selected: _tab,
                onSelect: _selectTab,
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                // 内容区独立焦点区（二维，允许上下左右）
                child: Focus(
                  focusNode: _contentScope,
                  canRequestFocus: false,
                  descendantsAreFocusable: true,
                  child: FocusTraversalGroup(
                    policy: TVFocusTraversalPolicy(),
                    child: IndexedStack(
                      index: _tab,
                      children: [
                        TVLibraryScreen(onPlay: _play, searchFocus: _searchFocus),
                        TVRankingsScreen(onPlay: _play),
                        TVMineScreen(
                          onPlay: _play,
                          onExplore: () => _selectTab(0),
                        ),
                        TVSettingsScreen(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// TV 侧边导航栏。图标 + 文字标签（TV 10 尺距离需文字辅助）。
class _TVNavigation extends StatelessWidget {
  const _TVNavigation({
    required this.selected,
    required this.onSelect,
  });
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Container(
    width: 200,
    decoration: BoxDecoration(
      color: context.colors.surface,
    ),
    child: Column(
      children: [
        const SizedBox(height: 28),
        const BrandMark(size: 40),
        const SizedBox(height: 8),
        Text(
          'MiniReel',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.muted,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        _destination(context, 0, '短剧库', Icons.movie_outlined, Icons.movie_rounded),
        const SizedBox(height: 10),
        _destination(context, 1, '热播榜', Icons.emoji_events_outlined, Icons.emoji_events_rounded),
        const SizedBox(height: 10),
        _destination(context, 2, '我的', Icons.person_outline_rounded, Icons.person_rounded),
        const Spacer(),
        _destination(context, 3, '设置', Icons.tune_rounded, Icons.tune_rounded),
        const SizedBox(height: 28),
      ],
    ),
  );

  Widget _destination(
    BuildContext context,
    int index,
    String label,
    IconData icon,
    IconData activeIcon,
  ) {
    final isSel = selected == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TVFocusable(
        radius: 13,
        onTap: () => onSelect(index),
        // 默认焦点交给内容区顶部搜索框（TVLibraryScreen 内 autofocus: true），
        // 导航栏不抢初始焦点；D-pad 左键可从内容区进入导航栏。
        semanticLabel: label,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
          decoration: BoxDecoration(
            color: isSel
                ? context.colors.primary.withValues(alpha: .1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: [
              // 左侧 accent 竖条（选中态），复用 library _category 动画语言
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: 3,
                height: 20,
                decoration: BoxDecoration(
                  color: isSel ? context.colors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                isSel ? activeIcon : icon,
                size: 22,
                color: isSel ? context.colors.primary : context.muted,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                  color: isSel ? context.colors.onSurface : context.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
