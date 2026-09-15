import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/platform.dart';
import 'tv_focus.dart';

/// TV 模式下的调试用虚拟遥控器悬浮面板（仅 debug 生效）。
///
/// 用途：在安卓模拟器（如 MuMuPlayer）或桌面调试 TV UI 时，不依赖模拟器
/// 键盘映射，直接在 app 内点方向键移动焦点、OK 激活当前焦点。
/// 同时提供"强制 TV 模式"开关，一键切换 TV/非 TV UI 分支。
///
/// 显示：右下角悬浮，可拖动。面板含 ↑↓←→ + OK + TV 开关 + 关闭。
/// 焦点移动：调用 FocusTraversalPolicy.inDirection(primaryFocus, dir)。
/// 激活：向当前焦点节点发送合成的 Enter KeyDownEvent。
class TVDebugPad extends StatefulWidget {
  const TVDebugPad({super.key, required this.child});
  final Widget child;

  @override
  State<TVDebugPad> createState() => _TVDebugPadState();
}

class _TVDebugPadState extends State<TVDebugPad> {
  bool _visible = false;
  Offset _position = const Offset(0, 0);
  Size? _screenSize;

  @override
  Widget build(BuildContext context) {
    // 仅 TV 调试界面显示遥控器，普通桌面和手机版不显示。
    if (!kDebugMode || !isAndroidTV) return widget.child;

    final media = MediaQuery.of(context);
    _screenSize = media.size;
    // 首次定位到右下角
    if (_position == Offset.zero && _screenSize != null) {
      _position = Offset(
        _screenSize!.width - 200,
        _screenSize!.height - 260,
      );
    }

    return Stack(
      children: [
        widget.child,
        // 触发器（小圆点），面板隐藏时显示
        if (!_visible) _trigger(),
        if (_visible) _panel(),
      ],
    );
  }

  /// 隐藏时右下角的小触发按钮。
  Widget _trigger() => Positioned(
    left: _position.dx,
    top: _position.dy,
    child: GestureDetector(
      onPanUpdate: (d) => setState(() => _position += d.delta),
      child: _DebugButton(
        icon: Icons.gamepad_rounded,
        onTap: () => setState(() => _visible = true),
        color: const Color(0xFF6B4EFF),
      ),
    ),
  );

  /// 显示时的方向键面板。
  Widget _panel() => Positioned(
    left: _position.dx,
    top: _position.dy,
    child: GestureDetector(
      onPanUpdate: (d) => setState(() => _position += d.delta),
      onPanCancel: () {},
      child: Container(
        width: 176,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xCF12151C),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶栏：TV 开关 + 关闭
            Row(
              children: [
                _DebugButton(
                  icon: Icons.tv_rounded,
                  label: 'TV',
                  active: debugForceTvMode,
                  onTap: () {
                    toggleDebugTvMode();
                    setState(() {});
                    // 切换后重建整个 app 树
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() {});
                    });
                  },
                  color: debugForceTvMode
                      ? const Color(0xFFFF3D6B)
                      : const Color(0xFF3A3F4B),
                  size: 34,
                ),
                const Spacer(),
                _DebugButton(
                  icon: Icons.close_rounded,
                  onTap: () => setState(() => _visible = false),
                  color: const Color(0xFF3A3F4B),
                  size: 34,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 方向键十字
            SizedBox(
              width: 130,
              height: 130,
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 43,
                    child: _DebugButton(
                      icon: Icons.arrow_drop_up_rounded,
                      onTap: () => _move(TraversalDirection.up),
                      size: 44,
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 43,
                    child: _DebugButton(
                      icon: Icons.arrow_drop_down_rounded,
                      onTap: () => _move(TraversalDirection.down),
                      size: 44,
                    ),
                  ),
                  Positioned(
                    top: 43,
                    left: 0,
                    child: _DebugButton(
                      icon: Icons.arrow_left_rounded,
                      onTap: () => _move(TraversalDirection.left),
                      size: 44,
                    ),
                  ),
                  Positioned(
                    top: 43,
                    right: 0,
                    child: _DebugButton(
                      icon: Icons.arrow_right_rounded,
                      onTap: () => _move(TraversalDirection.right),
                      size: 44,
                    ),
                  ),
                  // 中心 OK
                  Positioned(
                    top: 43,
                    left: 43,
                    child: _DebugButton(
                      label: 'OK',
                      onTap: _activate,
                      color: const Color(0xFFFF3D6B),
                      size: 44,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// 编程式移动焦点到指定方向。
  ///
  /// 优先检查 [tvPlayerDebugActions]：播放页注册时，方向键直接走播放页的
  /// seek/切集逻辑（播放页不用焦点导航）。否则走当前焦点所在 group 的
  /// [FocusTraversalPolicy.inDirection]（TVFocusTraversalPolicy 几何查找）。
  void _move(TraversalDirection direction) {
    final player = tvPlayerDebugActions;
    if (player != null) {
      switch (direction) {
        case TraversalDirection.up:
          player.onUp();
          return;
        case TraversalDirection.down:
          player.onDown();
          return;
        case TraversalDirection.left:
          player.onLeft();
          return;
        case TraversalDirection.right:
          player.onRight();
          return;
      }
    }
    final current = FocusManager.instance.primaryFocus;
    if (current == null) return;
    final policy = FocusTraversalGroup.of(current.context!);
    policy.inDirection(current, direction);
  }

  /// 激活当前焦点节点（模拟遥控器 OK / Enter）。
  ///
  /// 播放页注册了 [tvPlayerDebugActions] 时，OK 直接走播放页的播放/暂停。
  /// 否则用全局 [tvActivateSignal]：当前有焦点的 TVFocusable 监听并执行
  /// onTap（合成按键注入在部分平台不可靠，改用信号驱动）。
  void _activate() {
    final player = tvPlayerDebugActions;
    if (player != null) {
      player.onOk();
      return;
    }
    tvActivateSignal.value++;
  }
}

/// 调试面板里的小按钮。
class _DebugButton extends StatelessWidget {
  const _DebugButton({
    required this.onTap,
    this.icon,
    this.label,
    this.color = const Color(0xFF3A3F4B),
    this.active = false,
    this.size = 40,
  });
  final VoidCallback onTap;
  final IconData? icon;
  final String? label;
  final Color color;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: active
            ? Border.all(color: Colors.white70, width: 1.5)
            : null,
      ),
      child: label != null
          ? Center(
              child: Text(
                label!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : Icon(icon, color: Colors.white, size: size * 0.6),
    ),
  );
}
