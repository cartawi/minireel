import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../domain/models/remote_key_map.dart';
import '../shared/widgets.dart';
import 'tv_focus.dart';

/// 遥控器按键学习页：逐个引导用户为 7 个动作绑定物理按键。
///
/// 流程：
/// 1. 进入后从第一个动作开始，提示「请按【上】键」
/// 2. 用户按下任意键，捕获 logicalKey.keyId，追加到该动作的绑定
/// 3. 自动跳到下一个动作，直到 7 个全部完成
/// 4. 保存到 Preferences，关闭页面
///
/// 每个动作可按多次（追加多个键），按 OK/Enter 确认进入下一个。
/// 按 BACK 取消整个流程。
class RemoteKeyLearningSheet extends StatefulWidget {
  const RemoteKeyLearningSheet({super.key});
  @override
  State<RemoteKeyLearningSheet> createState() => _RemoteKeyLearningSheetState();
}

class _RemoteKeyLearningSheetState extends State<RemoteKeyLearningSheet> {
  /// 学习顺序：方向键 → OK → 返回 → 菜单。
  static const _order = [
    RemoteAction.up,
    RemoteAction.down,
    RemoteAction.left,
    RemoteAction.right,
    RemoteAction.ok,
    RemoteAction.back,
    RemoteAction.menu,
  ];

  int _index = 0;
  late RemoteKeyMap _map;
  /// 当前动作已捕获的按键（本次学习会话内）。
  final Map<RemoteAction, List<int>> _captured = {};

  @override
  void initState() {
    super.initState();
    _map = AppScope.read(context).remoteKeyMap;
  }

  RemoteAction get _current => _order[_index];
  bool get _isLast => _index >= _order.length - 1;

  /// 处理用户按键。
  /// - 任意方向/OK/菜单/返回键：记录为当前动作的绑定
  /// - 不拦截系统返回（让 Dialog 自己关闭）——但这里我们用 Focus 拦截，
  ///   BACK 键本身也是要学习的动作之一，所以学习 back 动作时按 BACK
  ///   会被记录而非退出。
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyId = event.logicalKey.keyId;
    // 忽略修饰键单独按下（Shift/Ctrl/Alt/Meta），避免误触
    if (event.logicalKey == LogicalKeyboardKey.shift ||
        event.logicalKey == LogicalKeyboardKey.control ||
        event.logicalKey == LogicalKeyboardKey.alt ||
        event.logicalKey == LogicalKeyboardKey.meta) {
      return KeyEventResult.ignored;
    }
    setState(() {
      final list = _captured.putIfAbsent(_current, () => []);
      if (!list.contains(keyId)) list.add(keyId);
      _map = _map.addKey(_current, keyId);
    });
    // 短暂展示捕获反馈后自动进入下一个
    Future.delayed(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      if (_isLast) {
        _finish();
      } else {
        setState(() => _index++);
      }
    });
    return KeyEventResult.handled;
  }

  void _finish() {
    final app = AppScope.read(context);
    app.setPreferences(app.preferences.copyWith(remoteKeyMap: _map));
    Navigator.of(context).pop(true);
  }

  void _skip() {
    if (_isLast) {
      _finish();
    } else {
      setState(() => _index++);
    }
  }

  void _cancel() {
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.primary;
    final captured = _captured[_current] ?? const <int>[];
    return Dialog(
      backgroundColor: const Color(0xFF171A22),
      constraints: const BoxConstraints(maxWidth: 520),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: ReelTheme.make(Brightness.dark),
        child: Focus(
          onKeyEvent: _onKey,
          autofocus: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 进度指示
                Row(
                  children: [
                    Text(
                      '遥控器按键学习',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: context.colors.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_index + 1} / ${_order.length}',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // 进度条
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (_index + (captured.isNotEmpty ? 0.5 : 0)) /
                        _order.length,
                    minHeight: 4,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
                const SizedBox(height: 28),
                // 当前动作提示
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: .12),
                          border: Border.all(color: accent, width: 2),
                        ),
                        child: Icon(
                          _iconFor(_current),
                          size: 44,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '请按下遥控器的',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '「${_current.hint}」',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // 已捕获的按键
                if (captured.isNotEmpty)
                  Center(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final keyId in captured)
                          _chip(_keyName(keyId), accent),
                      ],
                    ),
                  )
                else
                  Center(
                    child: Text(
                      '可连续按多个键绑定到该动作',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.muted,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                // 操作按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _cancel,
                      child: const Text('取消'),
                    ),
                    TVFocusable(
                      radius: 10,
                      onTap: _skip,
                      child: FilledButton.icon(
                        onPressed: null,
                        icon: Icon(
                          _isLast
                              ? Icons.check_rounded
                              : Icons.skip_next_rounded,
                          size: 18,
                        ),
                        label: Text(_isLast ? '完成' : '跳过'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color accent) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: .4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: accent,
          ),
        ),
      );

  IconData _iconFor(RemoteAction action) => switch (action) {
        RemoteAction.up => Icons.arrow_upward_rounded,
        RemoteAction.down => Icons.arrow_downward_rounded,
        RemoteAction.left => Icons.arrow_back_rounded,
        RemoteAction.right => Icons.arrow_forward_rounded,
        RemoteAction.ok => Icons.adjust_rounded,
        RemoteAction.back => Icons.undo_rounded,
        RemoteAction.menu => Icons.menu_rounded,
      };

  String _keyName(int keyId) {
    final key = LogicalKeyboardKey.findKeyByKeyId(keyId);
    if (key == null) return '键 0x${keyId.toRadixString(16)}';
    var label = key.keyLabel.trim();
    if (label.isEmpty) return '键 0x${keyId.toRadixString(16)}';
    label = label
        .replaceFirst('Game Button ', '')
        .replaceFirst('TV ', '')
        .replaceFirst('Media ', '');
    return label;
  }
}

/// 遥控器映射设置入口：展示当前 7 个动作的绑定，可进入学习或重置。
Future<void> showRemoteKeySettings(BuildContext context) async {
  final app = AppScope.read(context);
  await showReelSheet<void>(
    context,
    dark: true,
    builder: (context) => _RemoteKeySettingsSheet(app: app),
  );
}

class _RemoteKeySettingsSheet extends StatefulWidget {
  const _RemoteKeySettingsSheet({required this.app});
  final AppController app;

  @override
  State<_RemoteKeySettingsSheet> createState() =>
      _RemoteKeySettingsSheetState();
}

class _RemoteKeySettingsSheetState extends State<_RemoteKeySettingsSheet> {
  late RemoteKeyMap _map;

  @override
  void initState() {
    super.initState();
    _map = widget.app.remoteKeyMap;
  }

  void _save(RemoteKeyMap next) {
    _map = next;
    widget.app.setPreferences(
      widget.app.preferences.copyWith(remoteKeyMap: next),
    );
    setState(() {});
  }

  Future<void> _startLearning() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const RemoteKeyLearningSheet(),
    );
    if (result == true && mounted) {
      // 学习完成，刷新本地展示
      setState(() => _map = widget.app.remoteKeyMap);
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复默认映射'),
        content: const Text('将清除所有自定义按键绑定，恢复出厂默认。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _save(RemoteKeyMap.reset());
    }
  }

  Future<void> _clearAction(RemoteAction action) async {
    _save(_map.clearAction(action));
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.primary;
    return SheetFrame(
      title: '遥控器按键映射',
      subtitle: '部分遥控器按键可能无法识别，可在此重新绑定',
      footer: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Expanded(
              child: TVFocusable(
                radius: 12,
                onTap: _startLearning,
                child: FilledButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.school_rounded, size: 19),
                  label: const Text('开始学习'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            TVFocusable(
              radius: 12,
              onTap: _reset,
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.restart_alt_rounded, size: 19),
                label: const Text('恢复默认'),
              ),
            ),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in RemoteAction.values) ...[
            _actionRow(context, action, accent),
            if (action != RemoteAction.menu)
              Divider(height: 1, color: Colors.white10),
          ],
        ],
      ),
    );
  }

  Widget _actionRow(
    BuildContext context,
    RemoteAction action,
    Color accent,
  ) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Icon(_iconFor(action), size: 20, color: Colors.white70),
            const SizedBox(width: 12),
            SizedBox(
              width: 64,
              child: Text(
                action.label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _map.labelOf(action),
                style: TextStyle(
                  fontSize: 13.5,
                  color: _map.countOf(action) == 0
                      ? accent
                      : Colors.white60,
                ),
              ),
            ),
            if (_map.countOf(action) > 0)
              TVFocusable(
                radius: 8,
                onTap: () => _clearAction(action),
                child: IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(Icons.close_rounded, color: context.muted),
                  onPressed: null,
                ),
              ),
          ],
        ),
      );

  IconData _iconFor(RemoteAction action) => switch (action) {
        RemoteAction.up => Icons.arrow_upward_rounded,
        RemoteAction.down => Icons.arrow_downward_rounded,
        RemoteAction.left => Icons.arrow_back_rounded,
        RemoteAction.right => Icons.arrow_forward_rounded,
        RemoteAction.ok => Icons.adjust_rounded,
        RemoteAction.back => Icons.undo_rounded,
        RemoteAction.menu => Icons.menu_rounded,
      };
}
