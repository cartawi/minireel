import 'dart:math' show sin, pi;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';

/// 全局抖动信号：当焦点无法在某个方向移动（已到边界）时递增，
/// 当前有焦点的 TVFocusable 监听它并触发抖动动画，给用户“无法移动”的反馈。
final ValueNotifier<int> tvShakeSignal = ValueNotifier<int>(0);

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
/// D-pad 方向键由 [TVFocusTraversalPolicy] 做几何方向查找移动焦点，
/// OK/ENTER 激活 onTap，BACK 由外层 TVKeyHandler 处理。
///
/// 焦点遍历：所有 TV 页面的 FocusTraversalGroup 必须用
/// [TVFocusTraversalPolicy]（见文件末尾），它基于 FocusNode.rect 做精确的
/// 二维方向查找，不依赖 widget 树顺序，是 TV 遥控器适配的可靠方案。

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
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _shakeController;
  late final FocusNode _node;
  bool _ownsNode = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    if (widget.focusNode != null) {
      _node = widget.focusNode!;
    } else {
      _node = FocusNode(debugLabel: widget.semanticLabel ?? 'tv-focusable');
      _ownsNode = true;
    }
    if (widget.autofocus) _node.requestFocus();
    // 监听全局抖动信号：本节点有焦点时触发抖动
    tvShakeSignal.addListener(_onShakeSignal);
  }

  void _onShakeSignal() {
    if (!mounted) return;
    if (_node.hasFocus && !_shakeController.isAnimating) {
      _shakeController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    tvShakeSignal.removeListener(_onShakeSignal);
    _controller.dispose();
    _shakeController.dispose();
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
    // 方向键交给 FocusTraversalPolicy.inDirection 处理（不拦截）
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
        listenable: Listenable.merge([_node, _controller, _shakeController]),
        builder: (context, _) {
          final focused = _node.hasFocus;
          if (focused && _controller.status != AnimationStatus.forward) {
            _controller.forward();
          } else if (!focused && _controller.status != AnimationStatus.reverse) {
            _controller.reverse();
          }
          final t = Curves.easeOutCubic.transform(_controller.value);
          // 抖动：正弦波衰减，左右晃 3 次
          final shakeT = _shakeController.value;
          final shakeX = sin(shakeT * pi * 6) * (1 - shakeT) * 8;
          return GestureDetector(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: Transform.translate(
              offset: Offset(shakeX, 0),
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
///
/// 内部用 [TVFocusTraversalPolicy]（几何方向感知），比 Flutter 默认的
/// OrderedTraversalPolicy/ReadingOrderTraversalPolicy 更可靠：
/// 按方向键时基于 FocusNode.rect 找几何上该方向最近的节点，
/// 而非 widget 树顺序，适合 TV 遥控器的二维导航。
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
    policy: TVFocusTraversalPolicy(),
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

/// TV 专用焦点遍历策略：基于 FocusNode.rect 做精确的二维几何方向查找。
///
/// 替代 Flutter 默认的 ReadingOrderTraversalPolicy/OrderedTraversalPolicy。
/// 默认 policy 依赖 widget 树顺序或阅读顺序，在 SliverMasonryGrid、
/// 嵌套 Column/Row、跨 FocusTraversalGroup 等复杂布局下遍历不可靠，
/// 导致遥控器方向键不移动焦点或乱跳。
///
/// 本策略的 inDirection 实现：
/// 1. 收集当前 group 内所有可聚焦节点（rect 有效）
/// 2. 按方向过滤：只保留在该方向上的节点（如 down → node.top >= current.bottom）
/// 3. 按主轴距离 + 正交轴偏移排序，选最近的
/// 4. 若当前 group 内无候选，向上冒泡到父 group 继续查找
///
/// 这样无论 widget 嵌套多深，只要节点有屏幕坐标，方向键就能准确跳转。
class TVFocusTraversalPolicy extends FocusTraversalPolicy {
  @override
  FocusNode findFirstFocus(FocusNode currentNode, {bool ignoreCurrentFocus = false}) {
    return _collectFocusable(currentNode).firstOrNull ?? currentNode;
  }

  @override
  FocusNode findLastFocus(FocusNode currentNode, {bool ignoreCurrentFocus = false}) {
    final nodes = _collectFocusable(currentNode);
    return nodes.isEmpty ? currentNode : nodes.last;
  }

  @override
  FocusNode? findFirstFocusInDirection(FocusNode currentNode, TraversalDirection direction) {
    return _findInDirection(currentNode, direction);
  }

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final next = _findInDirection(currentNode, direction);
    if (next != null) {
      next.requestFocus();
      // 确保焦点节点滚动到可视区（TV 遥控器移动焦点后必须自动跟随）
      final ctx = next.context;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.1, duration: const Duration(milliseconds: 200));
      }
      return true;
    }
    // 无法移动：发抖动信号，当前焦点节点会抖动反馈
    tvShakeSignal.value++;
    return false;
  }

  @override
  Iterable<FocusNode> sortDescendants(Iterable<FocusNode> descendants, FocusNode currentNode) {
    final list = descendants.toList();
    list.sort((a, b) {
      final ra = a.rect;
      final rb = b.rect;
      if ((ra.top - rb.top).abs() > 5) return ra.top.compareTo(rb.top);
      return ra.left.compareTo(rb.left);
    });
    return list;
  }

  /// 在 currentNode 的方向上找最近的可聚焦节点。
  ///
  /// 策略：直接从根 scope 收集所有 TV 可聚焦节点做全局几何查找。
  /// 不依赖 FocusTraversalGroup 层级，避免跨兄弟 group（如内容区→导航栏）
  /// 时冒泡失败的问题。所有 TVFocusable 节点在同一个候选池里比较，
  /// 几何方向最准。
  FocusNode? _findInDirection(FocusNode currentNode, TraversalDirection direction) {
    final root = FocusManager.instance.rootScope;
    final candidates = _collectFocusableInScope(root);
    candidates.remove(currentNode);
    final currentRect = currentNode.rect;
    if (currentRect.isEmpty) return null;

    FocusNode? best;
    double bestScore = double.infinity;

    for (final node in candidates) {
      final r = node.rect;
      if (r.isEmpty) continue;
      final score = _directionScore(currentRect, r, direction);
      if (score == null) continue;
      if (score < bestScore) {
        bestScore = score;
        best = node;
      }
    }
    return best;
  }

  /// 计算从 current 到 candidate 在指定方向上的距离评分。
  /// 返回 null 表示 candidate 不在该方向上。
  ///
  /// TV 焦点标准算法（参考 Android TvView/Flutter tv_focus_agent）：
  /// 1. 优先选正交轴有投影重叠的节点（同一行/列），按主轴距离排序
  /// 2. 没有重叠节点时，才选斜向节点，正交偏移给重惩罚（×3）
  /// 这样按↓优先跳到正下方，不会乱跳到斜远方。
  double? _directionScore(Rect current, Rect candidate, TraversalDirection direction) {
    double mainAxis;
    double crossAxis;
    bool overlap;
    double reversePenalty = 0; // 反向偏移惩罚（如 right 时 candidate 在上方）
    switch (direction) {
      case TraversalDirection.down:
        if (candidate.top < current.bottom - 2) return null;
        mainAxis = candidate.top - current.bottom;
        crossAxis = _crossDistance(current, candidate, horizontal: true);
        overlap = candidate.right > current.left && candidate.left < current.right;
      case TraversalDirection.up:
        if (candidate.bottom > current.top + 2) return null;
        mainAxis = current.top - candidate.bottom;
        crossAxis = _crossDistance(current, candidate, horizontal: true);
        overlap = candidate.right > current.left && candidate.left < current.right;
      case TraversalDirection.right:
        if (candidate.left < current.right - 2) return null;
        mainAxis = candidate.left - current.right;
        crossAxis = _crossDistance(current, candidate, horizontal: false);
        overlap = candidate.bottom > current.top && candidate.top < current.bottom;
        // 瀑布流防上跳：candidate 中心在 current 上方时重惩罚
        final candidateCenterY = candidate.top + candidate.height / 2;
        final currentCenterY = current.top + current.height / 2;
        if (candidateCenterY < currentCenterY - 20) {
          reversePenalty = (currentCenterY - candidateCenterY) * 5;
        }
      case TraversalDirection.left:
        if (candidate.right > current.left + 2) return null;
        mainAxis = current.left - candidate.right;
        crossAxis = _crossDistance(current, candidate, horizontal: false);
        overlap = candidate.bottom > current.top && candidate.top < current.bottom;
        final candidateCenterY = candidate.top + candidate.height / 2;
        final currentCenterY = current.top + current.height / 2;
        if (candidateCenterY < currentCenterY - 20) {
          reversePenalty = (currentCenterY - candidateCenterY) * 5;
        }
    }
    // 有重叠：只看主轴距离
    // 无重叠：正交偏移重惩罚（×3）+ 反向偏移惩罚（×5），避免跳到斜远方/反方向
    return overlap ? mainAxis : mainAxis + crossAxis * 3 + reversePenalty;
  }

  /// 计算正交轴上的距离（两矩形中心点间距）。
  double _crossDistance(Rect a, Rect b, {required bool horizontal}) {
    if (horizontal) {
      // 水平方向移动时，正交轴是垂直，用中心 y 差
      return ((a.top + a.height / 2) - (b.top + b.height / 2)).abs();
    } else {
      return ((a.left + a.width / 2) - (b.left + b.width / 2)).abs();
    }
  }

  /// 向上查找最近的 FocusTraversalGroup 对应的 FocusNode。
  /// 收集所有可聚焦节点（全局，用于 findFirst/findLast）。
  List<FocusNode> _collectFocusable(FocusNode currentNode) {
    return _collectFocusableInScope(FocusManager.instance.rootScope);
  }

  /// 收集 scope 下所有可聚焦、有有效 rect 的叶子节点。
  List<FocusNode> _collectFocusableInScope(FocusNode scope) {
    final result = <FocusNode>[];
    void visit(FocusNode n) {
      if (n != scope && n.canRequestFocus && !n.rect.isEmpty) {
        result.add(n);
      }
      for (final child in n.children) {
        visit(child);
      }
    }
    for (final child in scope.children) {
      visit(child);
    }
    return result;
  }
}

/// 全局 D-pad 方向键拦截器：拦截真实遥控器/键盘方向键，
/// 强制走 [TVFocusTraversalPolicy.inDirection] 移动焦点，
/// 阻止 Scrollable/ListView 消费方向键做滚动。
///
/// 用法：包在 TV 页面根部（TVAppShell 顶层）。
/// 仅拦截方向键，其他键（OK/Enter/Back/媒体键）不受影响。
class TVDpadInterceptor extends StatelessWidget {
  const TVDpadInterceptor({super.key, required this.child});
  final Widget child;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    TraversalDirection? direction;
    if (key == LogicalKeyboardKey.arrowUp) {
      direction = TraversalDirection.up;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      direction = TraversalDirection.down;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      direction = TraversalDirection.left;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      direction = TraversalDirection.right;
    }
    if (direction == null) return KeyEventResult.ignored;
    final current = FocusManager.instance.primaryFocus;
    if (current == null) return KeyEventResult.ignored;
    // 走当前 group 的 TVFocusTraversalPolicy
    final policy = FocusTraversalGroup.of(current.context!);
    if (policy is TVFocusTraversalPolicy) {
      if (policy.inDirection(current, direction)) {
        return KeyEventResult.handled;
      }
    } else {
      // 兑底：用 Flutter 默认 inDirection
      if (current.focusInDirection(direction)) {
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: _onKey,
    // 不抢焦点，只拦截事件冒泡
    canRequestFocus: false,
    descendantsAreFocusable: true,
    child: child,
  );
}
