import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool get isWindowsDesktop =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

bool _tvMode = false;

/// 调试用：强制 TV 模式（仅 debug 生效）。在电脑上按 F9 切换，
/// 用于用键盘方向键模拟遥控器调试 TV UI。release 构建中永远为 false。
/// 也可启动时用 --dart-define=FORCE_TV=true 直接开启（同样仅 debug 生效）。
bool _debugForceTv = false;

/// 是否处于调试强制 TV 模式（仅 debug）。
bool get debugForceTvMode => kDebugMode && _debugForceTv;

/// 切换调试强制 TV 模式（仅 debug 生效）。
void toggleDebugTvMode() {
  if (!kDebugMode) return;
  _debugForceTv = !_debugForceTv;
}

/// 启动时调用：读取 --dart-define=FORCE_TV=true 初始化调试强制 TV。
/// 仅 debug 生效；release 构建忽略。
void initDebugTvFromEnv() {
  if (!kDebugMode) return;
  const forced = String.fromEnvironment('FORCE_TV', defaultValue: '');
  if (forced == 'true' || forced == '1') {
    _debugForceTv = true;
  }
}

/// 实际是否走 TV UI 分支：真机 TV 检测命中，或调试强制开启。
bool get isAndroidTV => _tvMode || debugForceTvMode;

/// 启动时调用，通过原生 MethodChannel 判定是否运行在 Android TV / 盒子上。
/// 判定依据（原生侧 MainActivity）：FEATURE_LEANBACK / FEATURE_LEANBACK_ONLY
/// 或 UI mode == UI_MODE_TYPE_TELEVISION。覆盖电视、盒子、TV 模拟器。
Future<void> detectAndroidTv() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  const channel = MethodChannel('minireel/device');
  try {
    _tvMode = await channel.invokeMethod<bool>('isTv') ?? false;
  } on PlatformException {
    _tvMode = false;
  } on MissingPluginException {
    _tvMode = false;
  }
}
