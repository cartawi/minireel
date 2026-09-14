import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/platform.dart';
import '../../app/theme.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/models/drama.dart';
import '../shared/widgets.dart';
import '../shared/drama_metadata.dart';
import '../tv/tv_focus.dart';

Future<void> showDramaDetail(
  BuildContext context,
  Drama drama,
  void Function(Drama, [int?]) onPlay,
) => showReelSheet<void>(
  context,
  builder: (_) => _DetailSheet(drama: drama, onPlay: onPlay),
);

class _DetailSheet extends StatefulWidget {
  const _DetailSheet({required this.drama, required this.onPlay});
  final Drama drama;
  final void Function(Drama, [int?]) onPlay;
  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  final _token = CancelToken();
  DramaDetail? _detail;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _token.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_loading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final app = AppScope.read(context);
    final cached = await app.store.readDetail(widget.drama.id);
    if (!mounted) return;
    if (cached != null) setState(() => _detail = cached);
    try {
      final detail = await app.repository.getDetail(
        widget.drama,
        cancelToken: _token,
      );
      if (mounted) {
        setState(() {
          _detail = detail;
          _loading = false;
        });
      }
    } on AppException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    } on DioException catch (error) {
      if (!CancelToken.isCancel(error) && mounted) {
        setState(() {
          _error = '网络连接失败，请重试';
          _loading = false;
        });
      }
    }
  }

  void _play([int? episode]) {
    Navigator.of(context).pop();
    widget.onPlay(_detail?.drama ?? widget.drama, episode);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.watch(context);
    final drama = _detail?.drama ?? widget.drama;
    final favorite = app.isFavorite(drama.id);
    final record = app.historyOf(drama.id);
    return SheetFrame(
      title: '短剧详情',
      footer: Row(
        children: [
          Expanded(
            child: isAndroidTV
                ? TVFocusable(
                    radius: 14,
                    onTap: () => app.toggleFavorite(drama),
                    child: OutlinedButton.icon(
                      onPressed: null,
                      icon: Icon(
                        favorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 19,
                      ),
                      label: Text(favorite ? '已收藏' : '收藏'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 50)),
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: () => app.toggleFavorite(drama),
                    icon: Icon(
                      favorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 19,
                    ),
                    label: Text(favorite ? '已收藏' : '收藏'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 50)),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: isAndroidTV
                ? TVFocusable(
                    radius: 14,
                    autofocus: true,
                    onTap: _play,
                    child: FilledButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(
                        record == null ? '立即播放' : '继续第 ${record.episodeIndex} 集',
                      ),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: _play,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      record == null ? '立即播放' : '继续第 ${record.episodeIndex} 集',
                    ),
                  ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: SizedBox(
                  width: 93,
                  height: 133,
                  child: CoverImage(drama: drama),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      drama.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${drama.channel.label} · ${drama.episodeLabel}',
                      style: TextStyle(color: context.muted, fontSize: 12.5),
                    ),
                    const SizedBox(height: 11),
                    Wrap(
                      spacing: 5,
                      runSpacing: 6,
                      children: [
                        for (final tag in drama.tags.take(4)) TagPill(tag),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 19),
          if (dramaMetadata(drama).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  for (final text in dramaMetadata(drama))
                    Text(
                      text,
                      style: TextStyle(color: context.muted, fontSize: 12),
                    ),
                ],
              ),
            ),
          Text(
            drama.intro.isEmpty ? '精彩故事，等你开启。' : drama.intro,
            style: TextStyle(fontSize: 13.5, color: context.muted, height: 1.8),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Text(
                '选集',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '共 ${_detail?.episodes.length ?? drama.episodeCount} 集',
                style: TextStyle(color: context.muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_detail != null)
            EpisodeGrid(
              episodes: _detail!.episodes,
              current: record?.episodeIndex,
              onSelect: (episode) => _play(episode.index),
            )
          else if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_error != null)
            Column(
              children: [
                Text(_error!, style: TextStyle(color: context.muted)),
                TextButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
        ],
      ),
    );
  }
}

class EpisodeGrid extends StatelessWidget {
  const EpisodeGrid({
    super.key,
    required this.episodes,
    required this.onSelect,
    this.current,
  });
  final List<Episode> episodes;
  final ValueChanged<Episode> onSelect;
  final int? current;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final columns = (constraints.maxWidth / (scale > 1.25 ? 64 : 51))
          .floor()
          .clamp(3, 8);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: episodes.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: 46,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemBuilder: (context, index) {
          final episode = episodes[index];
          final selected = current == episode.index;
          if (isAndroidTV) {
            return TVFocusable(
              radius: 12,
              onTap: () => onSelect(episode),
              autofocus: selected,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? context.colors.primary : context.chipColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '${episode.index}',
                    style: TextStyle(
                      fontSize: 14,
                      color: selected ? Colors.white : context.colors.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }
          return Semantics(
            label: episode.title,
            selected: selected,
            button: true,
            child: Material(
              color: selected ? context.colors.primary : context.chipColor,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelect(episode),
                child: Center(
                  child: Text(
                    '${episode.index}',
                    style: TextStyle(
                      fontSize: 14,
                      color: selected ? Colors.white : context.colors.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
