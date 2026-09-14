import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../domain/models/drama.dart';
import '../../domain/models/catalog_order.dart';
import '../detail/detail_sheet.dart';
import '../shared/widgets.dart';
import 'tv_focus.dart';
import 'tv_search_screen.dart';

/// TV 版短剧库页面。
/// 复用 LibraryScreen 的数据逻辑（channel/tag/filter/order），
/// UI 改为 TV 适配：所有可交互元素用 TVFocusable 包裹，D-pad 可操作。
class TVLibraryScreen extends StatefulWidget {
  const TVLibraryScreen({super.key, required this.onPlay});
  final void Function(Drama drama, [int? episode]) onPlay;
  @override
  State<TVLibraryScreen> createState() => _TVLibraryScreenState();
}

class _TVLibraryScreenState extends State<TVLibraryScreen> {
  DramaChannel? _channel;
  Set<String> _tags = {};
  ReleaseStatus? _status;
  bool _shortOnly = false;
  CatalogOrder _order = CatalogOrder.recommended;
  final _scroll = ScrollController();
  /// 内容网格区的焦点节点：用于检测焦点是否进入网格，从而折叠顶部分类/标签行。
  final _contentFocus = FocusNode(debugLabel: 'tv-library-content');
  /// 焦点是否在下方网格区（true 时折叠二级分类 + 热门标签行，腾出高度给网格）。
  bool _gridFocused = false;
  bool get _filtered =>
      _tags.isNotEmpty ||
      _status != null ||
      _shortOnly ||
      _order != CatalogOrder.recommended;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 700) {
        final repo = AppScope.read(context).repository;
        if (repo.errors.isEmpty) unawaited(repo.loadMore(channel: _channel));
      }
    });
    _contentFocus.addListener(_onContentFocusChanged);
  }

  void _onContentFocusChanged() {
    final focused = _contentFocus.hasFocus;
    if (focused != _gridFocused) {
      setState(() => _gridFocused = focused);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _contentFocus.removeListener(_onContentFocusChanged);
    _contentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.watch(context);
    return ListenableBuilder(
      listenable: app.repository,
      builder: (context, _) {
        final repo = app.repository;
        final available = repo.catalog
            .where((drama) => _channel == null || drama.channel == _channel)
            .toList();
        final items = available
            .where(
              (drama) =>
                  (_tags.isEmpty || _tags.any((tag) => drama.matches(tag))) &&
                  (_status == null || drama.releaseStatus == _status) &&
                  (!_shortOnly ||
                      drama.episodeCount > 0 && drama.episodeCount <= 60),
            )
            .toList();
        if (_order == CatalogOrder.title) {
          items.sort((a, b) => a.title.compareTo(b.title));
        }
        if (_order == CatalogOrder.short) {
          items.sort((a, b) => a.episodeCount.compareTo(b.episodeCount));
        }
        final popularTags = <String>{..._tags};
        for (final drama in available) {
          popularTags.addAll(drama.tags.where((tag) => tag.length <= 6));
          if (popularTags.length >= 12) break;
        }
        if (popularTags.isEmpty) {
          popularTags.addAll(['甜宠', '逆袭', '复仇', '穿越', '热血', '治愈', '玄幻']);
        }
        return Column(
          children: [
            // 顶部栏：搜索 + 分类 + 筛选（独立焦点区，与瀑布流隔离）
            FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border(
                    bottom: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TVFocusable(
                          radius: 28,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  TVSearchScreen(onPlay: widget.onPlay),
                            ),
                          ),
                          autofocus: true,
                          semanticLabel: '搜索',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: context.chipColor,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_rounded, size: 20, color: context.muted),
                                const SizedBox(width: 10),
                                Text(
                                  '搜索剧名、题材或标签',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: context.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        const BrandMark(size: 36),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // 二级分类 + 热门标签：焦点进入下方网格时折叠，腾出高度
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _gridFocused
                          ? const SizedBox.shrink()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 分类 + 筛选行
                                Row(
                                  children: [
                                    Expanded(
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: [
                                            _category(null, '综合'),
                                            for (final channel
                                                in DramaChannel.values)
                                              _category(channel, channel.label),
                                          ],
                                        ),
                                      ),
                                    ),
                                    TVFocusable(
                                      radius: 20,
                                      onTap: () =>
                                          _openFilters(popularTags.toList()),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.filter_list_rounded,
                                              size: 18,
                                              color: _filtered
                                                  ? context.colors.primary
                                                  : context.muted,
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              '筛选',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: _filtered
                                                    ? FontWeight.w600
                                                    : FontWeight.w400,
                                                color: _filtered
                                                    ? context.colors.primary
                                                    : context.muted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // 热门标签（靠左对齐）
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        for (final tag in popularTags.take(12))
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(right: 8),
                                            child: _TVTagPill(
                                              tag,
                                              selected: _tags.contains(tag),
                                              onTap: () => setState(() {
                                                if (!_tags.add(tag)) {
                                                  _tags.remove(tag);
                                                }
                                              }),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
            if (repo.refreshing && repo.catalog.isNotEmpty)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: Focus(
                focusNode: _contentFocus,
                canRequestFocus: false,
                descendantsAreFocusable: true,
                child: FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (repo.catalog.isEmpty && repo.refreshing) {
                      return _skeleton(constraints.maxWidth);
                    }
                  if (items.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        EmptyState(
                          icon: repo.errors.isEmpty
                              ? Icons.movie_outlined
                              : Icons.wifi_off_rounded,
                          title: _filtered ? '没有符合筛选的短剧' : '这里还没有短剧',
                          subtitle: _filtered
                              ? '试试其他题材，或者清空筛选'
                              : '正在加载，发现下一部好剧',
                          action: _filtered ? '清空筛选' : '刷新剧库',
                          onAction: () {
                            if (_filtered) {
                              setState(_resetFilters);
                            } else {
                              unawaited(repo.refresh());
                            }
                          },
                        ),
                      ],
                    );
                  }
                  final columns = dramaColumns(constraints.maxWidth);
                  return CustomScrollView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (app.history.isNotEmpty &&
                          !_filtered &&
                          _channel == null)
                        SliverToBoxAdapter(child: _continueWatching(app)),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        sliver: SliverMasonryGrid.count(
                          crossAxisCount: columns,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childCount: items.length,
                          itemBuilder: (context, index) {
                            final drama = items[index];
                            return TVFocusable(
                              radius: 16,
                              onTap: () => widget.onPlay(drama),
                              onLongPress: () => showDramaDetail(
                                context,
                                drama,
                                widget.onPlay,
                              ),
                              child: DramaCard(
                                drama: drama,
                                favorite: app.isFavorite(drama.id),
                                aspectRatio: [
                                  0.66,
                                  0.72,
                                  0.70,
                                  0.64,
                                ][index % 4],
                                onTap: () => widget.onPlay(drama),
                                onLongPress: () => showDramaDetail(
                                  context,
                                  drama,
                                  widget.onPlay,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 30),
                          child: Center(
                            child: repo.loadingMore
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : repo.hasMoreFor(_channel)
                                ? TextButton(
                                    onPressed: () =>
                                        repo.loadMore(channel: _channel),
                                    child: const Text('加载更多'),
                                  )
                                : Text(
                                    '· 已加载 ${items.length} 部短剧 ·',
                                    style: TextStyle(
                                      color: context.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _category(DramaChannel? value, String label) {
    final selected = _channel == value;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TVFocusable(
        radius: 8,
        onTap: () => setState(() {
          _channel = value;
          _tags.clear();
          if (_scroll.hasClients) _scroll.jumpTo(0);
        }),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? context.colors.onSurface : context.muted,
                ),
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 3,
                width: selected ? 20 : 0,
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _continueWatching(AppController app) {
    final record = app.history.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: TVFocusable(
        radius: 16,
        onTap: () => widget.onPlay(record.drama),
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
                    width: 48,
                    height: 62,
                    child: CoverImage(drama: record.drama),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                      const SizedBox(height: 5),
                      Text(
                        '上次看到第 ${record.episodeIndex} 集 · ${formatTime(record.position)}',
                        style: TextStyle(color: context.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.play_circle_fill_rounded,
                  color: context.colors.primary,
                  size: 38,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _skeleton(double width) => GridView.builder(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(20),
    itemCount: 8,
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: dramaColumns(width),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: .59,
    ),
    itemBuilder: (_, _) => Container(
      decoration: BoxDecoration(
        color: context.chipColor,
        borderRadius: BorderRadius.circular(16),
      ),
    ),
  );

  void _resetFilters() {
    _tags = {};
    _status = null;
    _shortOnly = false;
    _order = CatalogOrder.recommended;
  }

  Future<void> _openFilters(List<String> tags) async {
    final draftTags = Set<String>.of(_tags);
    var status = _status;
    var shortOnly = _shortOnly;
    var order = _order;
    await showReelSheet<void>(
      context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SheetFrame(
          title: '轻量筛选',
          footer: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => update(() {
                    draftTags.clear();
                    status = null;
                    shortOnly = false;
                    order = CatalogOrder.recommended;
                  }),
                  child: const Text('重置'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () {
                    setState(() {
                      _tags = draftTags;
                      _status = status;
                      _shortOnly = shortOnly;
                      _order = order;
                    });
                    Navigator.of(context).pop();
                  },
                  child: const Text('确定'),
                ),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _filterLabel(context, '题材'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in tags)
                    _TVTagPill(
                      tag,
                      selected: draftTags.contains(tag),
                      onTap: () => update(() {
                        if (!draftTags.add(tag)) draftTags.remove(tag);
                      }),
                    ),
                ],
              ),
              _filterLabel(context, '状态 / 篇幅'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TVTagPill(
                    '连载中',
                    selected: status == ReleaseStatus.ongoing,
                    onTap: () => update(
                      () => status = status == ReleaseStatus.ongoing
                          ? null
                          : ReleaseStatus.ongoing,
                    ),
                  ),
                  _TVTagPill(
                    '已完结',
                    selected: status == ReleaseStatus.completed,
                    onTap: () => update(
                      () => status = status == ReleaseStatus.completed
                          ? null
                          : ReleaseStatus.completed,
                    ),
                  ),
                  _TVTagPill(
                    '60 集内',
                    selected: shortOnly,
                    onTap: () => update(() => shortOnly = !shortOnly),
                  ),
                ],
              ),
              _filterLabel(context, '排序'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in {
                    CatalogOrder.recommended: '推荐',
                    CatalogOrder.title: '剧名',
                    CatalogOrder.short: '集数少优先',
                  }.entries)
                    _TVTagPill(
                      entry.value,
                      selected: order == entry.key,
                      onTap: () => update(() => order = entry.key),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterLabel(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 12),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: context.muted,
      ),
    ),
  );
}

/// TV 版 TagPill：复用 TagPill 视觉，外层包 TVFocusable。
class _TVTagPill extends StatelessWidget {
  const _TVTagPill(this.label, {required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => TVFocusable(
    radius: 30,
    onTap: onTap,
    child: TagPill(label, selected: selected),
  );
}
