import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';

/// TV 版焦点高亮系统。
///
/// 设计约束：绝对继承现有设计语言（ReelTheme）。
/// - 焦点环颜色：accent（#FF3D6B / dark #FF4D74）
/// - 圆角：跟随子元素，默认 16（与 DramaCard 一致）
/// - 动画曲线：Curves.easeOutCubic，200ms（与 library _category 一致）
/// - scale：1.0 → 1.04（轻微放大，TV 10 尺距离可感知）
/// - 阴影：焦点时 accent 色辉光
///
/// 用法：TVFocusable(onTap: ..., child: ...)
/// D-pad 方向键自动移动焦点（依赖 FocusTraversalGroup 分区），
/// OK/ENTER 激活 onTap，BACK 由外层 TVBackHandler 处理。

/// 包装任意可点击元素，赋予 D-pad 焦点能力与高亮视觉。
class TVFocusable extends StatefulWidget {
  const TVFocusable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.autofocus = false,
    this.radius = 16,
    this.scale = 1.04,
    this.borderWidth = 2.5,
    this.enableGlow = true,
    this.focusNode,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final double radius;
  final double scale;
  final double borderWidth;
  final bool enableGlow;
  final FocusNode? focusNode;
  final String? semanticLabel;

  @override
  State<TVFocusable> createState() => _TVFocusableState();
}

class _TVFocusableState extends State<TVFocusable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final FocusNode _node;
  bool _ownsNode = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    if (widget.focusNode != null) {
      _node = widget.focusNode!;
    } else {
      _node = FocusNode(debugLabel: widget.semanticLabel ?? 'tv-focusable');
      _ownsNode = true;
    }
    if (widget.autofocus) _node.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    if (_ownsNode) _node.dispose();
    super.dispose();
  }

  bool get _canActivate => widget.onTap != null || widget.onLongPress != null;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space) {
      widget.onTap?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.primary;
    return Actions(
      actions: _canActivate
          ? {ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) => widget.onTap?.call(),
            )}
          : const <Type, Action<Intent>>{},
      child: Focus(
        focusNode: _node,
        onKeyEvent: _canActivate ? _onKey : null,
        child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final focused = _node.hasFocus;
          if (focused && _controller.status != AnimationStatus.forward) {
            _controller.forward();
          } else if (!focused && _controller.status != AnimationStatus.reverse) {
            _controller.reverse();
          }
          final t = Curves.easeOutCubic.transform(_controller.value);
          return GestureDetector(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: Transform.scale(
              scale: 1 + (widget.scale - 1) * t,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.radius),
                  border: focused
                      ? Border.all(
                          color: accent,
                          width: widget.borderWidth,
                        )
                      : Border.all(
                          color: Colors.transparent,
                          width: widget.borderWidth,
                        ),
                  boxShadow: focused && widget.enableGlow
                      ? [
                          BoxShadow(
                            color: accent.withValues(alpha: .28),
                            blurRadius: 18 * t,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: widget.child,
              ),
            ),
          );
        },
      ),
    ),
    );
  }
}

/// 焦点作用域：封装 FocusTraversalGroup，限定 D-pad 方向键在组内移动。
/// 用于划分"导航区 / 内容区 / 详情区"，避免焦点跨区乱跳。
class TVFocusScope extends StatelessWidget {
  const TVFocusScope({
    super.key,
    required this.child,
    this.direction = AxisDirection.down,
    this.autofocusFirst = false,
  });
  final Widget child;
  final AxisDirection direction;
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    policy: OrderedTraversalPolicy(),
    child: _AutofocusScope(
      autofocus: autofocusFirst,
      child: child,
    ),
  );
}

class _AutofocusScope extends StatefulWidget {
  const _AutofocusScope({required this.child, required this.autofocus});
  final Widget child;
  final bool autofocus;
  @override
  State<_AutofocusScope> createState() => _AutofocusScopeState();
}

class _AutofocusScopeState extends State<_AutofocusScope> {
  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final scope = FocusScope.of(context);
          scope.traversalChildren.firstOrNull?.requestFocus();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 遥控器按键工具：捕获 BACK/MENU/媒体键，分发到回调。
/// 通常放在页面根部，处理系统级按键。
class TVKeyHandler extends StatelessWidget {
  const TVKeyHandler({
    super.key,
    required this.child,
    this.onBack,
    this.onMenu,
    this.onMediaRewind,
    this.onMediaFastForward,
    this.onMediaPlayPause,
  });
  final Widget child;
  final VoidCallback? onBack;
  final VoidCallback? onMenu;
  final VoidCallback? onMediaRewind;
  final VoidCallback? onMediaFastForward;
  final VoidCallback? onMediaPlayPause;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      onBack?.call();
      return onBack != null ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.contextMenu ||
        key == LogicalKeyboardKey.f1) {
      onMenu?.call();
      return onMenu != null ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.mediaRewind) {
      onMediaRewind?.call();
      return onMediaRewind != null
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.mediaFastForward) {
      onMediaFastForward?.call();
      return onMediaFastForward != null
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      onMediaPlayPause?.call();
      return onMediaPlayPause != null
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: _onKey,
    autofocus: true,
    child: child,
  );
}
