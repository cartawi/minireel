import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../domain/models/drama.dart';
import '../shared/widgets.dart';
import 'tv_focus.dart';
import 'tv_library_screen.dart';
import 'tv_mine_screen.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(AppScope.read(context).repository.refresh());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Row(
          children: [
            // 导航栏独立焦点区：D-pad 在导航项间上下移动，右键进入内容区
            FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: _TVNavigation(
                selected: _tab,
                onSelect: (tab) => setState(() => _tab = tab),
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                // 内容区独立焦点区
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      TVLibraryScreen(onPlay: _play),
                      TVMineScreen(
                        onPlay: _play,
                        onExplore: () => setState(() => _tab = 0),
                      ),
                      TVSettingsScreen(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// TV 侧边导航栏。图标 + 文字标签（TV 10 尺距离需文字辅助）。
class _TVNavigation extends StatelessWidget {
  const _TVNavigation({required this.selected, required this.onSelect});
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
        _destination(context, 1, '我的', Icons.person_outline_rounded, Icons.person_rounded),
        const Spacer(),
        _destination(context, 2, '设置', Icons.tune_rounded, Icons.tune_rounded),
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
        autofocus: index == 0,
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
