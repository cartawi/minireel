import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/models/discovery.dart';
import '../../domain/models/drama.dart';
import '../detail/detail_sheet.dart';
import '../shared/widgets.dart';
import 'tv_focus.dart';

/// TV 版热播榜页面。
///
/// 复用 repository.getRanking 拉取榜单数据（总热播/真人剧/漫剧/AI剧），
/// UI 改为 TV 适配：左侧榜单类型切换，右侧排名列表，全部 TVFocusable 可聚焦。
/// 数据层与手机版 RankingsScreen 共享，仅交互层重写。
class TVRankingsScreen extends StatefulWidget {
  const TVRankingsScreen({super.key, required this.onPlay});
  final void Function(Drama drama, [int? episode]) onPlay;
  @override
  State<TVRankingsScreen> createState() => _TVRankingsScreenState();
}

class _TVRankingsScreenState extends State<TVRankingsScreen> {
  RankingType _type = RankingType.hot;
  final _items = <RankingItem>[];
  CancelToken? _token;
  int _generation = 0;
  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;
  String _updated = '';
  String? _error;
  bool _retryRefresh = false;

  /// 右侧列表滚动控制器，加载更多时滚到底部触发。
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_load());
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _token?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (_scroll.position.pixels >= max - 200 && !_loading && _hasMore) {
      unawaited(_load());
    }
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading && !refresh) return;
    final generation = ++_generation;
    _token?.cancel();
    final token = _token = CancelToken();
    final page = refresh ? 1 : _page + 1;
    _retryRefresh = refresh;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AppScope.read(context).repository.getRanking(
        _type,
        page: page,
        refresh: refresh,
        cancelToken: token,
      );
      if (!mounted || generation != _generation) return;
      if (!refresh &&
          _items.any(
            (old) => result.items.any((item) => old.drama.id == item.drama.id),
          )) {
        _retryRefresh = true;
        throw const AppException('榜单分页返回重复内容，请刷新榜单');
      }
      setState(() {
        if (refresh) _items.clear();
        _items.addAll(result.items);
        _page = page;
        _hasMore = result.hasMore;
        _updated = result.updatedText;
      });
      if (refresh && mounted && generation == _generation) {
        showToast(
          context,
          _items.isEmpty ? '榜单暂无内容' : '榜单已刷新',
        );
      }
    } on DioException catch (error) {
      if (!CancelToken.isCancel(error) &&
          mounted &&
          generation == _generation) {
        setState(() => _error = '网络连接失败，请重试');
      }
    } on Exception catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = readableError(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _select(RankingType type) {
    if (type == _type) return;
    _token?.cancel();
    setState(() {
      _type = type;
      _items.clear();
      _page = 0;
      _hasMore = true;
      _updated = '';
      _loading = false;
    });
    unawaited(_load());
  }

  void _play(Drama drama, [int? episode]) {
    widget.onPlay(drama, episode);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Row(
        children: [
          // 左侧榜单类型栏：总热播/真人剧/漫剧/AI剧
          FocusTraversalGroup(
            policy: TVFocusTraversalPolicy(),
            child: Container(
              width: 180,
              decoration: BoxDecoration(
                color: context.colors.surface,
                border: Border(
                  right: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.emoji_events_rounded,
                        color: context.colors.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '热播榜',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  for (int i = 0; i < RankingType.values.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _typeChip(RankingType.values[i],
                          role: i == 0 ? 'rankingsTypeFirst' : null),
                    ),
                  const Spacer(),
                  // 刷新按钮
                  _refreshButton(),
                ],
              ),
            ),
          ),
          // 右侧排名列表
          Expanded(
            child: FocusTraversalGroup(
              policy: TVFocusTraversalPolicy(),
              child: Column(
                children: [
                  if (_updated.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _updated,
                          style: TextStyle(
                            color: context.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: _items.isEmpty && !_loading && _error == null
                        ? const EmptyState(
                            icon: Icons.emoji_events_outlined,
                            title: '暂无榜单内容',
                            subtitle: '稍后刷新再看看',
                          )
                        : ListView.builder(
                            controller: _scroll,
                            // TV 焦点需要视口外的项也 build 出 FocusNode，
                            // 否则方向键找不到下一个可聚焦节点会卡住。
                            // 2000px ≈ 视口外 20 项预构建，焦点连续移动顺畅。
                            cacheExtent: 2000,
                            padding:
                                const EdgeInsets.fromLTRB(24, 12, 24, 36),
                            itemCount: _items.length + 1,
                            itemBuilder: (context, index) {
                              if (index < _items.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _rankTile(_items[index]),
                                );
                              }
                              // 尾部状态区：错误/加载中/加载更多/已全部
                              if (_error != null) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _error!,
                                          style: TextStyle(
                                            color: context.muted,
                                          ),
                                        ),
                                      ),
                                      TVFocusable(
                                        radius: 10,
                                        onTap: () => _load(
                                          refresh: _retryRefresh ||
                                              _page == 0 ||
                                              !_hasMore,
                                        ),
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          child: Text('重试'),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              if (_loading) {
                                return const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              if (_items.isEmpty) return const SizedBox.shrink();
                              return Center(
                                child: _hasMore
                                    ? TVFocusable(
                                        radius: 10,
                                        onTap: _load,
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                          child: Text('加载更多'),
                                        ),
                                      )
                                    : Padding(
                                        padding: const EdgeInsets.all(18),
                                        child: Text(
                                          '已显示全部榜单',
                                          style: TextStyle(
                                            color: context.muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  /// 左侧榜单类型项。
  Widget _typeChip(RankingType type, {String? role}) {
    final isSel = type == _type;
    return TVFocusable(
      radius: 13,
      focusRole: role,
      onTap: () => _select(type),
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
            Text(
              type.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                color: isSel ? context.colors.primary : context.colors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 刷新按钮。
  Widget _refreshButton() => TVFocusable(
        radius: 13,
        focusRole: 'rankingsRefresh',
        onTap: _loading ? null : () => _load(refresh: true),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: context.muted.withValues(alpha: .3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.refresh_rounded,
                size: 18,
                color: _loading ? context.muted : context.colors.onSurface,
              ),
              const SizedBox(width: 8),
              Text(
                '刷新榜单',
                style: TextStyle(
                  fontSize: 13,
                  color: _loading ? context.muted : context.colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      );

  /// 排名列表项：名次 + 封面 + 标题/副标题/指标。
  Widget _rankTile(RankingItem item) {
    final rank = item.rank;
    return TVFocusable(
      radius: 14,
      onTap: () => _play(item.drama),
      onLongPress: () => showDramaDetail(context, item.drama, _play),
      child: Material(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 名次
              SizedBox(
                width: 44,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: rank <= 3
                        ? context.colors.primary
                        : context.muted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 封面
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 52,
                  height: 72,
                  child: CoverImage(drama: item.drama),
                ),
              ),
              const SizedBox(width: 14),
              // 标题 + 副标题 + 指标
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.drama.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        item.drama.subtitle,
                        if (item.metric.isNotEmpty) item.metric,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: context.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
