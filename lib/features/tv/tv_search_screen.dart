import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../domain/models/drama.dart';
import '../shared/widgets.dart';
import 'tv_focus.dart';

/// TV 版搜索页。
/// 复用 SearchScreen 逻辑，输入框调起系统 IME，结果列表用 TVFocusable。
class TVSearchScreen extends StatefulWidget {
  const TVSearchScreen({super.key, required this.onPlay});
  final void Function(Drama, [int?]) onPlay;
  @override
  State<TVSearchScreen> createState() => _TVSearchScreenState();
}

class _TVSearchScreenState extends State<TVSearchScreen> {
  final _query = TextEditingController();
  final _focusNode = FocusNode();
  final _resultsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _setQuery(String text) => setState(() {
    _query.text = text;
    _query.selection = TextSelection.collapsed(offset: text.length);
  });

  /// 焦点跳到结果区首个可遍历子节点。
  void _focusResults() {
    final ctx = _resultsKey.currentContext;
    if (ctx == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scope = FocusScope.of(ctx);
      scope.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) scope.traversalChildren.firstOrNull?.requestFocus();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.watch(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Focus(
                      focusNode: _focusNode,
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey ==
                                LogicalKeyboardKey.arrowDown) {
                          _focusNode.unfocus();
                          _focusResults();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                      controller: _query,
                      textInputAction: TextInputAction.search,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (v) {
                        app.addSearch(v);
                        _focusNode.unfocus();
                        _focusResults();
                      },
                      style: const TextStyle(fontSize: 16),
                      decoration: InputDecoration(
                        hintText: '搜索剧名、题材或标签',
                        filled: true,
                        fillColor: context.chipColor,
                        hintStyle: TextStyle(color: context.muted),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 22,
                          color: context.muted,
                        ),
                        suffixIcon: _query.text.isNotEmpty
                            ? IconButton(
                                tooltip: '清空搜索',
                                onPressed: () => _setQuery(''),
                                icon: const Icon(
                                  Icons.cancel_rounded,
                                  size: 20,
                                ),
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TVFocusable(
                    radius: 14,
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(
                        '取消',
                        style: TextStyle(fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FocusTraversalGroup(
                key: _resultsKey,
                policy: OrderedTraversalPolicy(),
                child: ListenableBuilder(
                listenable: app.repository,
                builder: (context, _) {
                  final query = _query.text.trim();
                  final results = app.repository.catalog
                      .where((drama) => drama.matches(query))
                      .toList();
                  if (query.isEmpty) {
                    final tags = app.repository.catalog
                        .expand((drama) => drama.tags)
                        .toSet()
                        .take(12)
                        .toList();
                    return ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Text(
                          '热门题材',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.muted,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 12,
                          children: [
                            for (final tag in tags)
                              TVFocusable(
                                radius: 30,
                                onTap: () => _setQuery(tag),
                                child: TagPill(tag),
                              ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Text(
                              '搜索历史',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: context.muted,
                              ),
                            ),
                            const Spacer(),
                            if (app.searches.isNotEmpty)
                              TVFocusable(
                                radius: 12,
                                onTap: app.clearSearches,
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 20,
                                    color: context.muted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 12,
                          children: [
                            for (final text in app.searches)
                              TVFocusable(
                                radius: 30,
                                onTap: () => _setQuery(text),
                                child: TagPill(text),
                              ),
                          ],
                        ),
                      ],
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
                    children: [
                      Text(
                        '已加载剧库中找到 ${results.length} 部',
                        style: TextStyle(color: context.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      for (final drama in results)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TVFocusable(
                            radius: 14,
                            onTap: () {
                              app.addSearch(query);
                              FocusScope.of(context).unfocus();
                              Navigator.of(context).pop();
                              widget.onPlay(drama);
                            },
                            child: Material(
                              color: context.colors.surface,
                              borderRadius: BorderRadius.circular(14),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: SizedBox(
                                        width: 52,
                                        height: 72,
                                        child: CoverImage(drama: drama),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            drama.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            drama.subtitle,
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
                          ),
                        ),
                      if (results.isEmpty)
                        EmptyState(
                          icon: Icons.search_off_rounded,
                          title: '还没找到「$query」',
                          subtitle: '试试更短的剧名，或加载更多短剧后再搜索',
                        ),
                      if (app.repository.hasMore)
                        Center(
                          child: TVFocusable(
                            radius: 14,
                            onTap: app.repository.loadingMore ||
                                    app.repository.refreshing
                                ? null
                                : app.repository.loadMore,
                            child: TextButton(
                              onPressed: null,
                              child: Text(
                                app.repository.loadingMore
                                    ? '正在加载更多短剧…'
                                    : '加载更多短剧继续搜索',
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
          ],
        ),
      ),
    );
  }
}
