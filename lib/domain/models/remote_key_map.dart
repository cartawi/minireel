import 'package:flutter/services.dart';

/// 遥控器逻辑动作。
///
/// 所有 TV 遥控器交互都归约到这 7 个动作，物理按键到动作的映射
/// 由 [RemoteKeyMap] 配置，可在设置页由用户重新学习绑定，
/// 解决部分遥控器按键映射不上的问题。
enum RemoteAction {
  up,
  down,
  left,
  right,
  ok,
  back,
  menu;

  /// 用户可见的动作名称。
  String get label => switch (this) {
        RemoteAction.up => '上',
        RemoteAction.down => '下',
        RemoteAction.left => '左',
        RemoteAction.right => '右',
        RemoteAction.ok => '确认',
        RemoteAction.back => '返回',
        RemoteAction.menu => '菜单',
      };

  /// 动作说明（学习页提示用）。
  String get hint => switch (this) {
        RemoteAction.up => '方向键上',
        RemoteAction.down => '方向键下',
        RemoteAction.left => '方向键左',
        RemoteAction.right => '方向键右',
        RemoteAction.ok => '中间 OK 键',
        RemoteAction.back => '返回键',
        RemoteAction.menu => '三条横键（菜单键）',
      };
}

/// 遥控器按键映射：[RemoteAction] → 一组 [LogicalKeyboardKey]。
///
/// 一个动作可绑定多个物理键（兼容不同遥控器 + 键盘）。
/// 默认映射覆盖常见遥控器与 Android TV 标准键码。
/// 通过 [Preferences] 持久化，用户可在设置页重新学习。
final class RemoteKeyMap {
  const RemoteKeyMap(this._bindings);

  /// action → keyId 集合。存 keyId（int）而非 LogicalKeyboardKey，
  /// 因为 LogicalKeyboardKey 的序列化（keyLabel/usbHidUsage）在不同
  /// Flutter 版本/平台间不稳定，keyId 是稳定的 32 位标识。
  final Map<RemoteAction, Set<int>> _bindings;

  /// 默认映射：覆盖 Android TV 标准键 + 常见遥控器变体 + 键盘。
  /// keyId 取自 Flutter keyboard_key.g.dart 的 LogicalKeyboardKey 定义。
  factory RemoteKeyMap.defaults() => const RemoteKeyMap({
        RemoteAction.up: {
          0x00100000304, // arrowUp
        },
        RemoteAction.down: {
          0x00100000301, // arrowDown
        },
        RemoteAction.left: {
          0x00100000302, // arrowLeft
        },
        RemoteAction.right: {
          0x00100000303, // arrowRight
        },
        RemoteAction.ok: {
          0x0010000050c, // select (DPad center)
          0x0010000000d, // enter
          0x00200000311, // gameButtonA
          0x00000000020, // space
        },
        RemoteAction.back: {
          0x0010000001b, // escape
          0x00100001005, // goBack
        },
        RemoteAction.menu: {
          0x00100000505, // contextMenu
          0x00100000801, // f1
          0x00100000508, // help
          0x00100001106, // tvContentsMenu
          0x00100000d55, // mediaTopMenu
        },
      });

  /// 该动作绑定的所有物理键。
  Set<LogicalKeyboardKey> keysOf(RemoteAction action) =>
      (_bindings[action] ?? const {})
          .map((id) => LogicalKeyboardKey.findKeyByKeyId(id))
          .whereType<LogicalKeyboardKey>()
          .toSet();

  /// 判断 [key] 是否触发 [action]。
  bool matches(RemoteAction action, LogicalKeyboardKey key) {
    final ids = _bindings[action];
    return ids != null && ids.contains(key.keyId);
  }

  /// 给 [action] 追加一个物理键（去重）。返回新映射。
  RemoteKeyMap addKey(RemoteAction action, int keyId) {
    final next = Map<RemoteAction, Set<int>>.from(_bindings);
    final set = Set<int>.from(next[action] ?? const {});
    set.add(keyId);
    next[action] = set;
    return RemoteKeyMap(next);
  }

  /// 清空 [action] 的所有绑定。返回新映射。
  RemoteKeyMap clearAction(RemoteAction action) {
    final next = Map<RemoteAction, Set<int>>.from(_bindings);
    next[action] = const {};
    return RemoteKeyMap(next);
  }

  /// 重置为默认映射。
  factory RemoteKeyMap.reset() => RemoteKeyMap.defaults();

  /// 该动作当前绑定的按键数量。
  int countOf(RemoteAction action) => _bindings[action]?.length ?? 0;

  /// 该动作绑定的按键可读名称（用于设置页展示）。
  /// 多个键用「/」分隔，无绑定显示「未设置」。
  String labelOf(RemoteAction action) {
    final keys = keysOf(action);
    if (keys.isEmpty) return '未设置';
    return keys.map((k) => _keyLabel(k)).join(' / ');
  }

  /// 生成可读按键名：优先用 keyLabel，去掉冗余前缀，未知键显示 keyId。
  static String _keyLabel(LogicalKeyboardKey k) {
    var label = k.keyLabel.trim();
    if (label.isEmpty) return '键 0x${k.keyId.toRadixString(16)}';
    // 去掉 "Game Button" / "TV " 等冗余前缀，更简洁
    label = label
        .replaceFirst('Game Button ', '')
        .replaceFirst('TV ', '')
        .replaceFirst('Media ', '');
    return label;
  }

  Map<String, dynamic> toJson() => {
        for (final entry in _bindings.entries)
          entry.key.name: entry.value.toList()..sort(),
      };

  factory RemoteKeyMap.fromJson(Map<String, dynamic> json) {
    final bindings = <RemoteAction, Set<int>>{};
    for (final action in RemoteAction.values) {
      final raw = json[action.name];
      if (raw is List) {
        bindings[action] = raw
            .whereType<num>()
            .map((n) => n.toInt())
            .where((id) => id != 0)
            .toSet();
      } else {
        bindings[action] = const {};
      }
    }
    return RemoteKeyMap(bindings);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteKeyMap &&
          _deepEquals(_bindings, other._bindings);

  @override
  int get hashCode => Object.hashAll(_bindings.entries.map((e) => Object.hash(e.key, Object.hashAll(e.value))));

  static bool _deepEquals(Map<RemoteAction, Set<int>> a, Map<RemoteAction, Set<int>> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      final av = a[key], bv = b[key];
      if (av == null || bv == null || av.length != bv.length || !av.containsAll(bv)) {
        return false;
      }
    }
    return true;
  }
}
