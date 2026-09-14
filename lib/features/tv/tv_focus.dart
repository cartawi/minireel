import 'dart:math' show sin, pi;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../domain/models/remote_key_map.dart';

/// 全局抖动信号：当焦点无法在某个方向移动（已到边界）时递增，
/// 当前有焦点的 TVFocusable 监听它并触发抖动动画，给用户“无法移动”的反馈。
final ValueNotifier<int> tvShakeSignal = ValueNotifier<int>(0);

/// 全局激活信号：递增时，当前有焦点的 [TVFocusable] 执行其 onTap。
/// 供调试悬浮面板的 OK 键使用（合成按键注入不可靠，改用信号驱动）。
final ValueNotifier<int> tvActivateSignal = ValueNotifier<int>(0);

/// TV 播放页调试动作 holder。
///
/// 播放页的交互模型与其它 TV 页面不同：方向键直接 seek/切集，而非在
/// [TVFocusable] 之间移动焦点。调试悬浮面板（[TVDebugPad]）默认走焦点
/// 遍历，在播放页里无效（播放页没有可移动焦点的 TVFocusable）。
///
/// 播放页在 [initState] 注册本 holder，把方向键/OK 映射到自身的
/// seek/切集/播放暂停逻辑；[dispose] 注销。悬浮面板的 [_move] /
/// [_activate] 优先检查本 holder，激活时直接调用对应回调，否则回退到
/// 焦点遍历路径。
TVPlayerDebugActions? tvPlayerDebugActions;

/// 播放页提供给调试悬浮面板的动作集合。
class TVPlayerDebugActions {
  TVPlayerDebugActions({
    required this.onUp,
    required this.onDown,
    required this.onLeft,
    required this.onRight,
    required this.onOk,
  });
  final void Function() onUp;
  final void Function() onDown;
  final void Function() onLeft;
  final void Function() onRight;
  final void Function() onOk;
}

/// TV 焦点导航全局注册表：解决几何查找无法覆盖的跨区导航场景。
///
/// 1) [navRegionKey]：导航栏区域的 Key。从导航栏按→进入内容区时，
///    统一落到 [searchFocusNode]（顶部搜索框），而非几何查找选中的网格卡片。
///    原因：搜索框 x 起点在导航栏 x 范围内，几何上“不在右方”，
///    纯几何查找会跳到网格中间的卡片。
/// 2) [searchFocusNode]：顶部搜索框节点，供导航栏→内容区、初始焦点使用。
final GlobalKey navRegionKey = GlobalKey(debugLabel: 'tv-nav-region');
FocusNode? searchFocusNode;

/// 焦点角色注册表：[TVFocusable] 可通过 [TVFocusable.focusRole] 注册一个
/// 角色名，[TVFocusTraversalPolicy] 据此做显式跨区落点特判。
///
/// 已用角色：
/// - `firstCategory`：分类行第一个（“综合”），搜索框↓落到它。
/// - `filter`：筛选按钮，分类行最右→落到它。
/// - `firstTag`：第一个热门标签，分类行任意↓落到它。
final class TVFocusRegistry {
  TVFocusRegistry._();
  /// 单角色单节点（如 firstCategory / filter / firstTag）。
  static final Map<String, FocusNode> _nodes = {};
  /// 单角色多节点（如 category：所有分类项）。
  static final Map<String, List<FocusNode>> _multi = {};
  /// 多节点角色名集合：注册时走 registerMulti。
  static const _multiRoles = {'category', 'searchHistory'};

  static bool isMultiRole(String role) => _multiRoles.contains(role);

  static void register(String role, FocusNode node) {
    if (_multi.containsKey(role)) {
      _multi[role]!.add(node);
    } else {
      _nodes[role] = node;
    }
  }

  static void registerMulti(String role, FocusNode node) {
    _multi.putIfAbsent(role, () => []).add(node);
    _nodes.remove(role);
  }

  static void unregister(String role, FocusNode node) {
    _nodes.remove(role);
    _multi[role]?.remove(node);
  }

  static FocusNode? get(String role) => _nodes[role];
  static List<FocusNode> getMulti(String role) => _multi[role] ?? const [];

  /// 反查节点所属角色。
  static String? roleOf(FocusNode node) {
    for (final e in _nodes.entries) {
      if (e.value == node) return e.key;
    }
    for (final e in _multi.entries) {
      if (e.value.contains(node)) return e.key;
    }
    return null;
  }
}

/// 内容区入口节点：由 [TVAppShell] 在切 tab 时更新，指向当前 tab 内容区的
/// 首选焦点节点（短剧库→搜索框，我的→第一个 segment，设置→第一个设置项）。
///
/// 供 [TVFocusTraversalPolicy] 的「导航栏→内容区」特判使用：从导航栏按→
/// 时落到此节点。比硬编码到 [searchFocusNode] 更通用——后者只在短剧库
/// tab 可见，在「我的/设置」tab 会落到 IndexedStack 隐藏的不可见节点。
FocusNode? contentEntryFocusNode;

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
///
/// [focusRole] 可选：给节点打一个角色标签，供 [TVFocusTraversalPolicy]
/// 做显式落点特判（如“搜索框↓→第一个分类”）。注册到静态
/// [TVFocusRegistry]，dispose 时注销。
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
    this.focusRole,
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
  final String? focusRole;

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
    if (widget.focusRole != null) {
      if (TVFocusRegistry.isMultiRole(widget.focusRole!)) {
        TVFocusRegistry.registerMulti(widget.focusRole!, _node);
      } else {
        TVFocusRegistry.register(widget.focusRole!, _node);
      }
    }
    // 监听全局抖动信号：本节点有焦点时触发抖动
    tvShakeSignal.addListener(_onShakeSignal);
    // 监听全局激活信号：本节点有焦点时执行 onTap（调试面板 OK 键）
    tvActivateSignal.addListener(_onActivateSignal);
  }

  void _onShakeSignal() {
    if (!mounted) return;
    if (_node.hasFocus && !_shakeController.isAnimating) {
      _shakeController.forward(from: 0);
    }
  }

  void _onActivateSignal() {
    if (!mounted) return;
    if (_node.hasFocus && widget.onTap != null) {
      widget.onTap!();
    }
  }

  @override
  void dispose() {
    tvShakeSignal.removeListener(_onShakeSignal);
    tvActivateSignal.removeListener(_onActivateSignal);
    if (widget.focusRole != null) TVFocusRegistry.unregister(widget.focusRole!, _node);
    _controller.dispose();
    _shakeController.dispose();
    if (_ownsNode) _node.dispose();
    super.dispose();
  }

  bool get _canActivate => widget.onTap != null || widget.onLongPress != null;

  /// 从 context 取当前生效的遥控器按键映射。
  RemoteKeyMap _keyMap(BuildContext context) =>
      AppScope.read(context).remoteKeyMap;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_keyMap(context).matches(RemoteAction.ok, key)) {
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

  KeyEventResult _onKey(FocusNode node, KeyEvent event, BuildContext context) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keyMap = AppScope.read(context).remoteKeyMap;
    if (keyMap.matches(RemoteAction.back, key)) {
      onBack?.call();
      return onBack != null ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (keyMap.matches(RemoteAction.menu, key)) {
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
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) => _onKey(node, event, context),
      autofocus: true,
      child: child,
    );
  }
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
  /// 屏幕高度，用于排除完全滚出屏幕的候选节点。
  /// 取 WidgetsBinding 窗口尺寸（不依赖 BuildContext，policy 内可用）。
  double get _screenHeight {
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    if (view == null) return 720;
    return view.physicalSize.height / (view.devicePixelRatio == 0 ? 1 : view.devicePixelRatio);
  }

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
      // 确保焦点节点滚动到可视区（TV 遥控器移动焦点后必须自动跟随）。
      // 用即时跳转而非动画：焦点本身已有 200ms 缩放/边框动画做反馈，
      // 滚动再动画会与网格重布局叠加导致掉帧（低端盒子尤甚）。
      final ctx = next.context;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.1);
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
    // 特判：从导航栏按→进入内容区，落到当前 tab 的内容区入口节点。
    // 由 [TVAppShell] 在切 tab 时更新 [contentEntryFocusNode]，短剧库指向
    // 搜索框，我的/设置指向各自首个可聚焦节点。避免硬编码到搜索框——
    // 后者只在短剧库 tab 可见，其它 tab 会落到 IndexedStack 隐藏节点。
    if (direction == TraversalDirection.right &&
        _isInNavRegion(currentNode) &&
        contentEntryFocusNode != null &&
        contentEntryFocusNode!.rect.width > 0) {
      return contentEntryFocusNode;
    }
    final currentRole = TVFocusRegistry.roleOf(currentNode);
    // 特判：搜索框↓ → 分类行第一个（“综合”）。
    if (direction == TraversalDirection.down &&
        currentNode == searchFocusNode) {
      final first = TVFocusRegistry.get('firstCategory');
      if (first != null && first.rect.width > 0) return first;
    }
    // 特判：分类行最右→ → “筛选”。几何上筛选在同行右侧，但
    // SingleChildScrollView 内的分类可能 rect 干扰，显式落点更稳。
    if (direction == TraversalDirection.right &&
        currentRole == 'category') {
      final cats = TVFocusRegistry.getMulti('category');
      if (cats.isNotEmpty && currentNode == cats.last) {
        final filter = TVFocusRegistry.get('filter');
        if (filter != null && filter.rect.width > 0) return filter;
      }
    }
    // 特判：筛选← → 分类行最右（“动漫”）。几何查找会落到下方标签行，
    // 用户期望落回二级分类。
    if (direction == TraversalDirection.left &&
        currentRole == 'filter') {
      final cats = TVFocusRegistry.getMulti('category');
      if (cats.isNotEmpty && cats.last.rect.width > 0) return cats.last;
    }
    // 特判：sheet 关闭按钮↓ → 弹窗内第一个标签（题材区第一个）。
    // 几何查找会跳到底部确定按钮，用户期望落到内容区。
    if (direction == TraversalDirection.down &&
        currentRole == 'sheetClose') {
      final first = TVFocusRegistry.get('filterFirstTag');
      if (first != null && first.rect.width > 0) return first;
    }
    // 特判：搜索框↓ → 搜索历史第一个（最左）。
    // TextField 的 onKeyEvent 可能被内部覆盖，在 policy 层兏底。
    if (direction == TraversalDirection.down &&
        currentRole == 'searchField') {
      final first = TVFocusRegistry.get('searchHistoryFirst');
      if (first != null && first.rect.width > 0) return first;
    }
    // 特判：搜索历史标签↑ → 回到搜索框。
    if (direction == TraversalDirection.up &&
        (currentRole == 'searchHistory' ||
            currentRole == 'searchHistoryFirst')) {
      final field = TVFocusRegistry.get('searchField');
      if (field != null && field.rect.width > 0) return field;
    }
    // 特判：搜索历史标签→/↓ 到边界 → 抖动（不跨出到顶部按钮）。
    // 判断“最后一个历史”：searchHistoryFirst + searchHistory 列表的最后一个。
    if ((direction == TraversalDirection.right ||
            direction == TraversalDirection.down) &&
        (currentRole == 'searchHistory' ||
            currentRole == 'searchHistoryFirst')) {
      final first = TVFocusRegistry.get('searchHistoryFirst');
      final rest = TVFocusRegistry.getMulti('searchHistory');
      final all = [...(first != null ? [first] : <FocusNode>[]), ...rest];
      print('[TV-History] dir=$direction role=$currentRole all=${all.length} cur=${currentNode.debugLabel} last=${all.lastOrNull?.debugLabel} isLast=${currentNode == all.lastOrNull}');
      if (all.isNotEmpty && currentNode == all.last) {
        return null; // 触发抖动
      }
    }
    // 特判：分类行任意↓ → 第一个热门标签（最左）。
    // 几何查找会选当前分类正下方的标签，但用户期望统一落到第一个。
    if (direction == TraversalDirection.down &&
        currentRole == 'category') {
      final firstTag = TVFocusRegistry.get('firstTag');
      if (firstTag != null && firstTag.rect.width > 0) return firstTag;
    }
    // 特判：标签行任意↓ / 继续观看↓ → 网格第一行最左第一个卡片。
    // 几何查找会选 y 最近的中间卡片，用户期望统一落到左上角第一个。
    if (direction == TraversalDirection.down &&
        (currentRole == 'firstTag' ||
            currentRole == 'tag' ||
            currentRole == 'continueWatching')) {
      final firstCard = TVFocusRegistry.get('firstGridCard');
      if (firstCard != null && firstCard.rect.width > 0) return firstCard;
    }
    // 特判：「我的」页 segment（收藏/历史）↓ → 首个卡片或空状态按钮。
    // segment 行与内容区是两个独立 FocusTraversalGroup（FocusScopeNode），
    // _enclosingTraversalScope 限定候选在 segment 行 scope 内，几何查找
    // 看不到下方内容区的节点。显式跨 group 落点：列表非空落首个卡片，
    // 空状态落「去发现短剧」按钮。
    if (direction == TraversalDirection.down &&
        (currentRole == 'mineEntry' || currentRole == 'mineEntry2')) {
      final firstCard = TVFocusRegistry.get('mineFirstCard');
      if (firstCard != null && firstCard.rect.width > 0) return firstCard;
      final action = TVFocusRegistry.get('mineEmptyAction');
      if (action != null && action.rect.width > 0) return action;
    }
    final root = FocusManager.instance.rootScope;
    // 找当前焦点所在的最近 FocusTraversalGroup scope。若非根 scope（如弹窗），
    // 只在该 scope 内查找候选，避免焦点跨出弹窗跑到背景页面。
    final scope = _enclosingTraversalScope(currentNode) ?? root;
    final candidates = _collectFocusableInScope(scope);
    candidates.remove(currentNode);
    final currentRect = currentNode.rect;
    if (currentRect.isEmpty) return null;

    // 特判：导航栏内上下移动不跨出导航栏（避免跳到网格卡片）。
    // 导航栏是一个垂直列表，上下应在导航项之间循环。
    final inNav = _isInNavRegion(currentNode);
    if (inNav &&
        (direction == TraversalDirection.up ||
            direction == TraversalDirection.down)) {
      candidates.removeWhere((n) => !_isInNavRegion(n));
    }

    FocusNode? best;
    double bestScore = double.infinity;

    for (final node in candidates) {
      final r = node.rect;
      if (r.isEmpty) continue;
      // 排除完全在屏幕外的候选（瀑布流滚动后顶部/底部不可见卡片仍有效 rect，
      // 会干扰几何查找——如上方滚出的卡片 y 为负，与当前卡片 beam 重叠且
      // 主轴距离相同，被误选导致“跳到上面”）
      if (r.bottom < 0 || r.top > _screenHeight) continue;
      final score = _directionScore(currentRect, r, direction);
      if (score == null) continue;
      if (score < bestScore) {
        bestScore = score;
        best = node;
      }
    }
    return best;
  }

  /// 计算从 current 到 candidate 在指定方向上的距离评分（beam-based，
  /// 参考 Android Leanback FocusFinder）。
  /// 返回 null 表示 candidate 不在该方向上。
  ///
  /// Beam 算法核心：
  /// 1. 候选必须严格在方向前方（如 down → candidate.top >= current.bottom）
  /// 2. 正交轴投影重叠（beam 对齐）→ "正前方"，评分 = 主轴距离（最近者胜）
  /// 3. 无 beam 重叠 → 斜向候选，评分 = 主轴距离 + 正交逃逸距离 × 权重
  ///    逃逸距离 = candidate 近边到 current 投影的偏离量（贴 beam 边缘的优先）
  ///
  /// 这比纯中心点距离更符合 TV 直觉：同行/同列卡片优先，斜向选偏离最小的。
  /// 瀑布流左右移动时，相邻列 y 投影重叠的卡片（同行）按水平距离选最近，
  /// 不会跳过；y 不重叠的错位卡片按逃逸距离选 y 最贴近的，不乱窜。
  double? _directionScore(Rect current, Rect candidate, TraversalDirection direction) {
    double mainAxis;
    bool beamOverlap;
    double escape; // 正交逃逸距离（无 beam 重叠时）
    double crossCenterDelta; // 正交轴中心差（beam 对齐时做 tie-breaker）
    switch (direction) {
      case TraversalDirection.down:
        if (candidate.top < current.bottom - 2) return null;
        mainAxis = candidate.top - current.bottom;
        beamOverlap = candidate.right > current.left && candidate.left < current.right;
        escape = _escapeDistance(
          current.left, current.right, candidate.left, candidate.right,
        );
        crossCenterDelta = ((current.left + current.right) / 2 - (candidate.left + candidate.right) / 2).abs();
      case TraversalDirection.up:
        if (candidate.bottom > current.top + 2) return null;
        mainAxis = current.top - candidate.bottom;
        beamOverlap = candidate.right > current.left && candidate.left < current.right;
        escape = _escapeDistance(
          current.left, current.right, candidate.left, candidate.right,
        );
        crossCenterDelta = ((current.left + current.right) / 2 - (candidate.left + candidate.right) / 2).abs();
      case TraversalDirection.right:
        if (candidate.left < current.right - 2) return null;
        mainAxis = candidate.left - current.right;
        beamOverlap = candidate.bottom > current.top && candidate.top < current.bottom;
        escape = _escapeDistance(
          current.top, current.bottom, candidate.top, candidate.bottom,
        );
        crossCenterDelta = ((current.top + current.bottom) / 2 - (candidate.top + candidate.bottom) / 2).abs();
      case TraversalDirection.left:
        if (candidate.right > current.left + 2) return null;
        mainAxis = current.left - candidate.right;
        beamOverlap = candidate.bottom > current.top && candidate.top < current.bottom;
        escape = _escapeDistance(
          current.top, current.bottom, candidate.top, candidate.bottom,
        );
        crossCenterDelta = ((current.top + current.bottom) / 2 - (candidate.top + candidate.bottom) / 2).abs();
    }
    // beam 对齐：主轴距离 + 正交中心差 ×0.3（tie-breaker，避免主轴距离
    //   相同时选到 y/x 偏离大的卡片——瀑布流上下两个卡片主轴距离常相同）
    // 无 beam 重叠：主轴 + 逃逸距离 ×5（斜向候选，选偏离 beam 最小的）
    return beamOverlap ? mainAxis + crossCenterDelta * 0.3 : mainAxis + escape * 5;
  }

  /// 计算正交轴上 candidate 投影偏离 current 投影的距离（逃逸距离）。
  /// [curStart, curEnd] 是 current 在正交轴的投影区间，
  /// [candStart, candEnd] 是 candidate 的。返回 candidate 偏离 current 的最小距离。
  /// 投影重叠时返回 0（不应被调用，beamOverlap 已过滤）。
  double _escapeDistance(
    double curStart, double curEnd,
    double candStart, double candEnd,
  ) {
    if (candEnd <= curStart) return curStart - candEnd; // candidate 完全在 current 起点侧
    if (candStart >= curEnd) return candStart - curEnd; // candidate 完全在 current 终点侧
    return 0; // 有重叠
  }

  /// 判断节点是否在导航栏 region 内（通过 navRegionKey 标识的 widget 树）。
  /// 找当前节点所在的最近 [FocusScope] 边界节点。
  /// 弹窗（Dialog）会创建独立 FocusScope，用它作为隔离边界，
  /// 避免弹窗内焦点移动跨出到背景页面。
  /// 返回 null 表示在根 scope（无隔离）。
  FocusNode? _enclosingTraversalScope(FocusNode node) {
    var n = node.parent;
    while (n != null) {
      if (n is FocusScopeNode) return n;
      n = n.parent;
    }
    return null;
  }

  bool _isInNavRegion(FocusNode node) {
    // 导航栏在屏幕左侧 x∈[0,200]，节点 x 在此范围内视为导航栏内
    final nodeRect = node.rect;
    return nodeRect.left < 200 && nodeRect.right <= 200;
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

  KeyEventResult _onKey(FocusNode node, KeyEvent event, BuildContext context) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keyMap = AppScope.read(context).remoteKeyMap;
    TraversalDirection? direction;
    if (keyMap.matches(RemoteAction.up, key)) {
      direction = TraversalDirection.up;
    } else if (keyMap.matches(RemoteAction.down, key)) {
      direction = TraversalDirection.down;
    } else if (keyMap.matches(RemoteAction.left, key)) {
      direction = TraversalDirection.left;
    } else if (keyMap.matches(RemoteAction.right, key)) {
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
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) => _onKey(node, event, context),
      // 不抢焦点，只拦截事件冒泡
      canRequestFocus: false,
      descendantsAreFocusable: true,
      child: child,
    );
  }
}
