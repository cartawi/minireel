import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../domain/models/drama.dart';
import '../shared/widgets.dart';
import 'tv_focus.dart';

/// TV 版我的页面。
/// 复用 MineScreen 逻辑（收藏/历史），列表项用 TVFocusable 包裹。
/// TV 上省略"管理/多选"模式（遥控器多选体验差），改为长按弹删除确认。
class TVMineScreen extends StatefulWidget {
  const TVMineScreen({super.key, required this.onPlay, required this.onExplore});
  final void Function(Drama, [int?]) onPlay;
  final VoidCallback onExplore;
  @override
  State<TVMineScreen> createState() => _TVMineScreenState();
}

class _TVMineScreenState extends State<TVMineScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.watch(context);
    final list = _tab == 0 ? app.favorites : app.history;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
          child: Row(
            children: [
              Text(
                '我的',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: FocusTraversalGroup(
            policy: TVFocusTraversalPolicy(),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: context.chipColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _segment('收藏${app.favorites.isEmpty ? '' : ' ${app.favorites.length}'}', 0),
                  _segment('历史${app.history.isEmpty ? '' : ' ${app.history.length}'}', 1),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: FocusTraversalGroup(
            policy: TVFocusTraversalPolicy(),
            child: list.isEmpty
              ? EmptyState(
                  icon: _tab == 0
                      ? Icons.favorite_border_rounded
                      : Icons.history_rounded,
                  title: _tab == 0 ? '把喜欢的故事留在这里' : '从一部好剧开始',
                  subtitle: _tab == 0 ? '收藏短剧，下次打开就能接着看' : '观看记录会自动保存，精彩随时继续',
                  action: '去发现短剧',
                  onAction: widget.onExplore,
                )
              : _tab == 0
              ? LayoutBuilder(
                  builder: (context, constraints) => MasonryGridView.count(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 28),
                    crossAxisCount: dramaColumns(constraints.maxWidth),
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    itemCount: app.favorites.length,
                    itemBuilder: (context, index) {
                      final drama = app.favorites[index];
                      final record = app.historyOf(drama.id);
                      return TVFocusable(
                        radius: 16,
                        onTap: () => widget.onPlay(drama),
                        onLongPress: () => _confirmRemove(
                          app,
                          {drama.id},
                          _tab == 0,
                        ),
                        child: DramaCard(
                          drama: drama,
                          favorite: true,
                          aspectRatio: [0.66, 0.72, 0.70, 0.64][index % 4],
                          onTap: () => widget.onPlay(drama),
                          onLongPress: () => _confirmRemove(
                            app,
                            {drama.id},
                            _tab == 0,
                          ),
                          interactive: false,
                          footer: record == null
                              ? null
                              : Text(
                                  '看到第 ${record.episodeIndex} 集',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.colors.primary,
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 28),
                  itemCount: app.history.length,
                  itemBuilder: (context, index) {
                    final record = app.history[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TVFocusable(
                        radius: 16,
                        onTap: () => widget.onPlay(record.drama),
                        onLongPress: () => _confirmRemove(
                          app,
                          {record.drama.id},
                          false,
                        ),
                        child: Material(
                          color: context.colors.surface,
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 64,
                                    height: 88,
                                    child: CoverImage(drama: record.drama),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        record.drama.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '第 ${record.episodeIndex} 集 · ${formatTime(record.position)} / ${formatTime(record.duration)}',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: context.muted,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(2),
                                        child: LinearProgressIndicator(
                                          value: record.progress,
                                          minHeight: 3,
                                          backgroundColor: context.chipColor,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        relativeTime(record.updatedAt),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: context.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.play_circle_outline_rounded,
                                  size: 32,
                                  color: context.colors.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
          ),
        ),
      ],
    );
  }

  Widget _segment(String label, int tab) => Expanded(
    child: TVFocusable(
      radius: 11,
      onTap: () => setState(() => _tab = tab),
      autofocus: tab == 0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: _tab == tab ? context.colors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: _tab == tab ? context.colors.onSurface : context.muted,
              fontWeight: _tab == tab ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _confirmRemove(
    AppController app,
    Set<String> ids,
    bool isFavorite,
  ) async {
    final confirmed = await showReelSheet<bool>(
      context,
      builder: (context) => SheetFrame(
        title: isFavorite ? '取消收藏' : '删除观看记录',
        footer: FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('确认删除'),
        ),
        child: Text(
          isFavorite
              ? '将从收藏中移除这部短剧。'
              : '删除这条记录后，将不再记忆这部短剧的观看进度。',
          style: TextStyle(color: context.muted, height: 1.6),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    if (isFavorite) {
      app.removeFavorites(ids);
    } else {
      app.removeHistory(ids);
    }
  }
}
