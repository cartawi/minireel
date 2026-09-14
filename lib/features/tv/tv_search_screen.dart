import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/models/discovery.dart';
import '../../domain/models/drama.dart';
import '../shared/widgets.dart';
import 'tv_focus.dart';

/// TV 版搜索页。
/// 支持远程搜索（repository.searchRemote）+ 本地剧库补充，结果列表用 TVFocusable。
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
  CancelToken? _token;
  int _generation = 0;
  bool _loading = false;
  SearchResult? _remote;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _token?.cancel();
    _query.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 输入变化：取消进行中的远程搜索，清空远程结果。
  void _changed() {
    _token?.cancel();
    ++_generation;
    setState(() {
      _remote = null;
      _error = null;
      _loading = false;
    });
  }

  void _setQuery(String text) {
    _query.text = text;
    _query.selection = TextSelection.collapsed(offset: text.length);
    _changed();
  }

  Future<void> _search([String? value]) async {
    final keyword = _query.text.trim();
    if (_loading || keyword.isEmpty) return;
    final app = AppScope.read(context);
    _focusNode.unfocus();
    _token?.cancel();
    final token = _token = CancelToken();
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _remote = null;
      _error = null;
    });
    try {
      final result = await app.repository.searchRemote(
        keyword,
        cancelToken: token,
      );
      if (!mounted || generation != _generation) return;
      app.addSearch(keyword);
      setState(() => _remote = result);
      _focusResults();
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

  void _play(Drama drama) {
    AppScope.read(context).addSearch(_query.text.trim());
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();
    widget.onPlay(drama);
  }

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
    final canRemote = app.repository.canSearchRemote;
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
                      onChanged: (_) => _changed(),
                      onSubmitted: canRemote ? _search : app.addSearch,
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
                  if (canRemote)
                    TVFocusable(
                      radius: 14,
                      onTap: _loading || _query.text.trim().isEmpty
                          ? null
                          : _search,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        child: Text(
                          '搜索',
                          style: TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
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
                policy: TVFocusTraversalPolicy(),
                child: ListenableBuilder(
                listenable: app.repository,
                builder: (context, _) {
                  final query = _query.text.trim();
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
                                onTap: () {
                                  _setQuery(text);
                                  _search();
                                },
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
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(color: context.muted),
                                ),
                              ),
                              TVFocusable(
                                radius: 10,
                                onTap: _search,
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
                        ),
                      if (_remote case final result?) ...[
                        Text(
                          '联网搜索：找到 ${result.total} 部，返回 ${result.items.length} 部',
                          style: TextStyle(color: context.muted, fontSize: 13),
                        ),
                        for (final warning in result.warnings)
                          Text(
                            warning,
                            style: TextStyle(
                              color: context.muted,
                              fontSize: 12,
                            ),
                          ),
                        const SizedBox(height: 14),
                        for (final drama in result.items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _dramaTile(drama),
                          ),
                        if (result.items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('没有找到相关短剧，试试其他关键词'),
                          ),
                      ],
                      if (_remote == null && !_loading && _error == null)
                        EmptyState(
                          icon: Icons.search_rounded,
                          title: '搜索「$query」',
                          subtitle: canRemote
                              ? '按回车或点击搜索，联网查找短剧'
                              : '当前数据源不支持远程搜索',
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

  /// 搜索结果剧集卡片（TV 焦点可点）。
  Widget _dramaTile(Drama drama) {
    return TVFocusable(
      radius: 14,
      onTap: () => _play(drama),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
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
    );
  }
}
