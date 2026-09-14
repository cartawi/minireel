import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/platform.dart';
import '../../domain/models/drama.dart';
import '../tv/tv_focus.dart';

int dramaColumns(double width) => isWindowsDesktop
    ? ((width - 28) / 190).floor().clamp(2, 10)
    : isAndroidTV
    ? ((width - 28) / 175).floor().clamp(4, 8)
    : width >= 1100
    ? 5
    : width >= 800
    ? 4
    : width >= 600
    ? 3
    : 2;

String formatTime(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 359999);
  final minutes = seconds ~/ 60;
  return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

String relativeTime(DateTime time) {
  final elapsed = DateTime.now().difference(time);
  if (elapsed.inMinutes < 1) return '刚刚';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} 分钟前';
  if (elapsed.inDays < 1) return '${elapsed.inHours} 小时前';
  if (elapsed.inDays < 7) return '${elapsed.inDays} 天前';
  return '${time.month}月${time.day}日';
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 38});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: EdgeInsets.all(size * .13),
    decoration: BoxDecoration(
      color: const Color(0xFF101318),
      borderRadius: BorderRadius.circular(size * .3),
    ),
    child: Image.asset(
      'assets/logo.png',
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    ),
  );
}

class CoverImage extends StatelessWidget {
  const CoverImage({super.key, required this.drama, this.fit = BoxFit.cover});
  final Drama drama;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) {
    Widget placeholder() => ColoredBox(
      color: context.colors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          size: 32,
          color: context.muted.withValues(alpha: .45),
        ),
      ),
    );
    if (drama.coverUrl.isEmpty) return placeholder();
    // TV/低端设备性能优化：按显示尺寸解码，避免把原图(可达 800×1200)整张
    // 解码进内存。卡片显示宽约 175 逻辑像素，按 2x DPR 给 350 像素足够清晰，
    // 内存占用降一个数量级，解码也更快。
    return Image.network(
      drama.coverUrl,
      fit: fit,
      cacheWidth: 350,
      excludeFromSemantics: true,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => placeholder(),
      frameBuilder: (context, child, frame, synchronous) =>
          synchronous || frame != null ? child : placeholder(),
    );
  }
}

class DramaCard extends StatelessWidget {
  const DramaCard({
    super.key,
    required this.drama,
    required this.onTap,
    this.onLongPress,
    this.favorite = false,
    this.aspectRatio = .68,
    this.selected = false,
    this.selecting = false,
    this.footer,
    this.interactive = true,
  });
  final Drama drama;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool favorite;
  final double aspectRatio;
  final bool selected;
  final bool selecting;
  final Widget? footer;
  /// 是否响应触摸点击。TV 版由外层 TVFocusable 接管点击时设为 false，
  /// InkWell 仅保留水波纹视觉，不再独立触发 onTap（避免双重点击）。
  final bool interactive;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${drama.title}，${drama.episodeLabel}',
    child: Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: interactive ? onTap : null,
        onLongPress: interactive ? onLongPress : null,
        onSecondaryTap: interactive && isWindowsDesktop ? onLongPress : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CoverImage(drama: drama),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 72,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0x99000000)],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 7,
                    bottom: 7,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 142),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: drama.releaseStatus == ReleaseStatus.ongoing
                            ? context.colors.primary
                            : Colors.white.withValues(alpha: .23),
                      ),
                      child: Text(
                        drama.episodeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (favorite || selecting)
                    Positioned(
                      right: 7,
                      top: 7,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: selected
                              ? context.colors.primary
                              : Colors.black38,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          selecting
                              ? (selected
                                    ? Icons.check_rounded
                                    : Icons.circle_outlined)
                              : Icons.favorite_rounded,
                          color: selecting
                              ? Colors.white
                              : context.colors.primary,
                          size: 14,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drama.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    drama.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: context.muted),
                  ),
                  if (footer != null) ...[const SizedBox(height: 7), footer!],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class TagPill extends StatelessWidget {
  const TagPill(this.label, {super.key, this.selected = false, this.onTap});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? context.colors.primary.withValues(alpha: .12)
        : context.chipColor,
    borderRadius: BorderRadius.circular(30),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? context.colors.primary : context.muted,
          ),
        ),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.onAction,
    this.actionBuilder,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget Function(String action, VoidCallback? onAction)? actionBuilder;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: context.chipColor,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Icon(
              icon,
              size: 30,
              color: context.muted.withValues(alpha: .6),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.muted,
                fontSize: 12.5,
                height: 1.6,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 20),
            actionBuilder?.call(action!, onAction) ??
                FilledButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    ),
  );
}

Future<T?> showReelSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dark = false,
}) {
  // TV 与桌面都走居中 Dialog（横屏大屏，底部 sheet 体验差）
  if (isWindowsDesktop || isAndroidTV) {
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .5),
      builder: (dialogContext) => Dialog(
        backgroundColor: dark ? const Color(0xFF171A22) : null,
        constraints: const BoxConstraints(maxWidth: 540),
        clipBehavior: Clip.antiAlias,
        child: FocusTraversalGroup(
          policy: TVFocusTraversalPolicy(),
          child: dark
              ? Theme(
                  data: ReelTheme.make(Brightness.dark),
                  child: Builder(builder: builder),
                )
              : Builder(builder: builder),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: dark ? const Color(0xFF171A22) : null,
    barrierColor: Colors.black.withValues(alpha: .55),
    builder: (sheetContext) => dark
        ? Theme(
            data: ReelTheme.make(Brightness.dark),
            child: Builder(builder: builder),
          )
        : builder(sheetContext),
  );
}

class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
    this.maxHeight = .86,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final double maxHeight;
  @override
  Widget build(BuildContext context) => _SheetAutofocus(
    child: SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * maxHeight,
        ),
        child: Padding(
          padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isWindowsDesktop) const SizedBox(height: 18),
            if (!isWindowsDesktop)
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 10),
                  decoration: BoxDecoration(
                    color: context.muted.withValues(alpha: .28),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: context.muted,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _CloseButton(),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: child,
              ),
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: footer,
              ),
          ],
        ),
      ),
    ),
    ),
  );
}

/// Sheet 右上角关闭按钮：TV 上用 TVFocusable 提供红框焦点 + 辉光，
/// 手机/桌面上退化为普通 IconButton。
class _CloseButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (isAndroidTV) {
      return TVFocusable(
        radius: 10,
        borderWidth: 2,
        focusRole: 'sheetClose',
        autofocus: true,
        onTap: () => Navigator.of(context).pop(),
        semanticLabel: '关闭',
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            Icons.close_rounded,
            size: 20,
            color: context.muted,
          ),
        ),
      );
    }
    return IconButton(
      tooltip: '关闭',
      onPressed: () => Navigator.of(context).pop(),
      icon: Icon(
        Icons.close_rounded,
        size: 20,
        color: context.muted,
      ),
    );
  }
}

/// TV 上 sheet 打开时自动聚焦首个可遍历子节点（TVFocusable）。
/// 手机/桌面无副作用。
class _SheetAutofocus extends StatefulWidget {
  const _SheetAutofocus({required this.child});
  final Widget child;
  @override
  State<_SheetAutofocus> createState() => _SheetAutofocusState();
}

class _SheetAutofocusState extends State<_SheetAutofocus> {
  @override
  void initState() {
    super.initState();
    if (isAndroidTV) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final scope = FocusScope.of(context);
          scope.requestFocus();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            // 若已有节点持焦点（如某个 TVFocusable 设了 autofocus），保留它；
            // 否则聚焦首个可遍历子节点。
            final primary = FocusManager.instance.primaryFocus;
            if (primary == null ||
                primary == scope ||
                !scope.children.any((n) => n.hasFocus)) {
              scope.traversalChildren.firstOrNull?.requestFocus();
            }
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<T?> pickOption<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required T value,
  required Map<T, String> options,
  bool dark = false,
}) => showReelSheet<T>(
  context,
  dark: dark,
  builder: (context) => SheetFrame(
    title: title,
    subtitle: subtitle,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in options.entries)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 3),
            title: Text(
              option.value,
              style: TextStyle(
                fontSize: 15,
                color: option.key == value ? context.colors.primary : null,
              ),
            ),
            trailing: option.key == value
                ? Icon(
                    Icons.check_rounded,
                    color: context.colors.primary,
                    size: 20,
                  )
                : null,
            onTap: () => Navigator.of(context).pop(option.key),
          ),
      ],
    ),
  ),
);
