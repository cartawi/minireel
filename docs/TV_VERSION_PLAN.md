# MiniReel TV 版执行方案

> 本文档是 TV 版开发的唯一权威执行手册。任何模型/会话读取本文档后应能无缝接手开发。
> 最后更新：见 git log。每完成一个阶段，更新对应章节的 ✅ 状态。

## 完成状态总览

| 阶段                        | 状态 | 说明                                                |
| --------------------------- | ---- | --------------------------------------------------- |
| A. Gradle Flavor + 原生骨架 | ✅   | phone/tv 双 APK 构建成功，签名复用                  |
| B. Dart TV 判定 + 分发骨架  | ✅   | platform.dart isAndroidTV + app.dart 三分支         |
| C. TV 焦点系统              | ✅   | tv_focus.dart TVFocusable/TVFocusScope/TVKeyHandler |
| D. TV 主界面                | ✅   | shell/library/search/mine/settings 五页             |
| E. TV 播放器                | ✅   | 遥控器全功能，复用 PlaybackSession                  |
| F. 测试与验证               | ⏳   | 代码+构建已验证，待真机/模拟器测试                  |

**当前可交付**：phone + tv 两个 release APK 均构建成功，全项目 flutter analyze 零问题。待 TV 真机/模拟器验证遥控器交互。

## 0. 项目背景速查（接手必读）

- **项目**：MiniReel，Flutter 短剧播放器，已支持 Android 手机 + Windows 桌面。
- **路径**：`/Users/herren/Downloads/Code/flutter-hg`
- **架构**：分层 `lib/app` `lib/core` `lib/data` `lib/domain` `lib/features` `lib/playback` `lib/desktop`。业务/数据/播放层与 UI 解耦，TV 版零改动复用。
- **平台分发模式**：`lib/app/platform.dart` 的 `isWindowsDesktop` → `lib/app/app.dart` 的 `_AppShell` 和 `_play()` 用三元切换 UI shell 和播放器。TV 版新增第三分支 `isAndroidTV`。
- **设计系统**：见 `lib/app/theme.dart`（ReelTheme）+ `lib/features/shared/widgets.dart`。accent 玫红 #FF3D6B，深色背景 #0B0D12，圆角 16/28/30，InkSparkle 水波纹。核心组件：DramaCard、TagPill、BrandMark、CoverImage、EmptyState、showReelSheet+SheetFrame、pickOption、PlayerGlass、PlayerControlButton。
- **签名**：见 memory #56。keystore 在 `android/.signing/minireel-release.jks`，需 4 个环境变量。TV flavor 复用同一 keystore。
- **构建环境**：Flutter 3.41.9 @ /Users/herren/development/flutter；JDK 17；Android SDK @ ~/Library/Android/sdk。系统代理 127.0.0.1:7897。

## 1. 总体目标

新增 Android TV/盒子版本，**绝对继承现有 UI 设计**，支持遥控器操作，横屏，不破坏手机版。用 Product Flavor 区分 phone/tv 两个 APK。

## 2. 阶段分解（按顺序执行）

### 阶段 A：Gradle Flavor + 原生骨架 ✅ 已完成

**目标**：能打出 phone 和 tv 两个 APK（TV 版 UI 暂时复用手机版，先跑通管道）。

**A1. 修改 `android/app/build.gradle.kts`**

- 在 `android {}` 块内、`defaultConfig` 之后新增：

```kotlin
flavorDimensions += "device"
productFlavors {
    create("phone") { dimension = "device" }
    create("tv") {
        dimension = "device"
        applicationIdSuffix = ".tv"
    }
}
```

- 签名逻辑（现有 `localSigning`/`signingValue`/`hasReleaseSigning`/`releaseRequested`）保持不变，两个 flavor 共用。

**A2. 拆分 AndroidManifest**

- `src/main/AndroidManifest.xml`：只保留共享权限（INTERNET、MODIFY_AUDIO_SETTINGS）+ `<queries>` + flutterEmbedding meta-data。**移除** application/activity/intent-filter（下放到 flavor）。
- `src/phone/AndroidManifest.xml`：完整 application + activity + LAUNCHER intent-filter（即原 main 的内容）。
- `src/tv/AndroidManifest.xml`：

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>
    <uses-feature android:name="android.software.leanback" android:required="true"/>
    <application
        android:label="MiniReel TV"
        android:name="${applicationName}"
        android:usesCleartextTraffic="true"
        android:enableOnBackInvokedCallback="true"
        android:icon="@mipmap/ic_launcher"
        android:banner="@drawable/tv_banner">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:screenOrientation="landscape"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true">
            <meta-data android:name="io.flutter.embedding.android.NormalTheme" android:resource="@style/NormalTheme"/>
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data android:name="flutterEmbedding" android:value="2"/>
    </application>
</manifest>
```

**A3. TV 资源**

- `src/tv/res/drawable/tv_banner.xml`：320×180 横幅（Leanback 桌面图标）。可用纯色 + logo，或生成 PNG 放 `drawable-nodpi/`。
- `src/tv/res/values/themes.xml`：Leanback 兼容主题（复用 NormalTheme 即可，或继承 `Theme.Leanback`）。
- TV launcher 图标：复用 main 的 `mipmap-anydpi-v26/ic_launcher.xml`（通过 src main 共享），或 TV 专属。

**A4. TV MainActivity（MethodChannel 判定）**

- `src/tv/kotlin/app/minireel/minireel/MainActivity.kt`：

```kotlin
package app.minireel.minireel

import android.content.pm.PackageManager
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "minireel/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTv" -> result.success(isTvDevice())
                    else -> result.notImplemented()
                }
            }
    }
    private fun isTvDevice(): Boolean {
        val pm = packageManager
        if (pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK_ONLY)) return true
        val uiMode = resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK
        return uiMode == Configuration.UI_MODE_TYPE_TELEVISION
    }
}
```

- `src/phone/kotlin/.../MainActivity.kt`：保持原样（`class MainActivity : FlutterActivity()`），但可加同名 MethodChannel 返回 `isTv=false`，或让 main 的 MainActivity 处理。**注意**：flavor 的 kotlin 会覆盖 main 的，所以 phone flavor 也要放一份。

**A5. 验证构建**

```bash
# 手机版
flutter build apk --release --flavor phone --split-per-abi
# TV 版（此时 UI 还是手机版，但能装到 TV 上）
flutter build apk --release --flavor tv --split-per-abi
```

两个 APK 都应成功签名产出。TV APK 装到 Android TV 模拟器应能从桌面启动（Leanback launcher）。

**A 阶段完成标志**：两个 flavor 都能构建出签名 APK，TV APK 能在 TV 模拟器启动。

**实际验证结果（2024）**：

- phone debug/release + tv debug/release 均构建成功。
- TV APK: package=`app.minireel.minireel.tv`, label=`MiniReel TV`, LEANBACK_LAUNCHER + leanback uses-feature + banner + landscape。
- Phone APK: package=`app.minireel.minireel`, label=`MiniReel`, LAUNCHER。
- 签名复用 `android/.signing/minireel-release.jks`，两 flavor 共用，正常。
- 产物：`build/app/outputs/flutter-apk/app-{abi}-{flavor}-release.apk`。

---

### 阶段 B：Dart 侧 TV 判定 + 分发骨架 ✅ 已完成

**目标**：`isAndroidTV` 可用，`app.dart` 能分发到 TV shell（暂时占位）。

**B1. 扩展 `lib/app/platform.dart`**

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool get isWindowsDesktop =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

bool _tvMode = false;
bool get isAndroidTV => _tvMode;

Future<void> detectAndroidTv() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  const channel = MethodChannel('minireel/device');
  try {
    _tvMode = await channel.invokeMethod<bool>('isTv') ?? false;
  } on PlatformException {
    _tvMode = false;
  }
}
```

**B2. `lib/main.dart` 启动时调用**

- 在 `main()` 的 `MediaKit.ensureInitialized()` 之后加 `await detectAndroidTv();`。

**B3. `lib/app/app.dart` 分发**

- `_AppShell.build` 的 shell 分支：`isAndroidTV ? const TVAppShell() : (isWindowsDesktop ? DesktopShell : PhoneShell)`
- `_play` 的播放器分支：`isAndroidTV ? TVPlayerScreen(...) : (isWindowsDesktop ? DesktopPlayerScreen : PlayerScreen)`
- 先建占位 `lib/features/tv/tv_shell.dart`（临时返回手机版 LibraryScreen）和 `tv_player_screen.dart`（临时返回 PlayerScreen），让 B 阶段可验证。

**B 阶段完成标志**：TV APK 启动后 `isAndroidTV==true`，进入 TV shell（占位）。

**实际完成**：platform.dart 新增 isAndroidTV + detectAndroidTv()（MethodChannel 'minireel/device'）；main.dart 启动调用；app.dart \_AppShell + \_play 增加 isAndroidTV 分支；占位 tv_shell.dart + tv_player_screen.dart。TV debug 构建通过。

---

### 阶段 C：TV 焦点系统 ✅ 已完成

**目标**：可复用的 D-pad 焦点高亮组件。

**C1. 新建 `lib/features/tv/tv_focus.dart`**

- `TVFocusable` widget：包装任意可点击元素，管理 FocusNode，焦点时显示 accent 边框环 + scale。
- 焦点环：accent 色 2px 边框，圆角跟随子元素（默认 16），`Curves.easeOutCubic` 200ms。
- scale：1.0 → 1.04，用 `Transform.scale` + `AnimatedContainer`。
- 阴影：焦点时 `BoxShadow(color: accent.withAlpha(.3), blurRadius: 16)`。
- 提供 `TVFocusScope`（封装 `FocusTraversalGroup`，限定方向键在组内移动）。
- 提供 `TVFocusNode` 便捷工厂（autofocus 首项）。

**C2. 遥控器按键映射工具 `lib/features/tv/tv_key_bindings.dart`**

- `TVKeyHandler`：`KeyboardListener`/`Focus` 的 onKeyEvent，映射：
  - DPAD_UP/DOWN/LEFT/RIGHT → 焦点移动（交给 FocusTraversal）
  - DPAD_CENTER/ENTER → 激活（调用 onTap）
  - BACK/ESCAPE → Navigator.pop
  - MEDIA_REWIND/MEDIA_FAST_FORWARD → 播放器快退/快进
  - MENU → 弹出面板回调

**C 阶段完成标志**：`TVFocusable` 包裹的按钮能用方向键聚焦、高亮、确认。

**实际完成**：`lib/features/tv/tv_focus.dart` 含 TVFocusable（焦点环 accent + scale 1.04 + 辉光阴影 + easeOutCubic 200ms）、TVFocusScope（FocusTraversalGroup 分区 + autofocus 首项）、TVKeyHandler（BACK/MENU/媒体键捕获）。编译通过。

---

### 阶段 D：TV 主界面 ✅ 已完成

**目标**：完整 TV 版首页（库/我的/设置），D-pad 全程可操作。

**D1. `lib/features/tv/tv_shell.dart`（TVAppShell）**

- 横屏布局：左侧导航栏（~180 宽，图标+文字）+ 右侧内容区。
- 导航项复用 `DesktopNavigation` 的图标语言，但加文字标签（TV 10 尺距离需文字）。
- 选中项：accent 半透明背景 + 左侧 3px accent 竖条（复用 library `_category` 动画竖条）。
- 导航项用 `TVFocusable` 包裹，D-pad 上下切换。
- 内容区 `IndexedStack` 切换三个页面。

**D2. TV 库页面 `lib/features/tv/tv_library_screen.dart`**

- 复用 `LibraryScreen` 的数据逻辑（channel/tag/filter），但 UI 改为 TV 适配：
  - 顶部搜索栏：复用圆角 28 样式，`TVFocusable` 包裹，确认进入 TV 搜索页。
  - 分类/标签：横向滚动，`TVFocusable` 包裹每个 `TagPill`/分类项。
  - 网格：`dramaColumns` 对 TV 优化（横屏大屏 5-7 列），`DramaCard` 外层包 `TVFocusable`。
  - 筛选：走 `showReelSheet`（TV 自动 dialog 分支），内部选项 `TVFocusable` 包裹。
- `dramaColumns` 扩展：加 `isAndroidTV` 分支返回更大列数。

**D3. TV 搜索页 `lib/features/tv/tv_search_screen.dart`**

- 复用 `SearchScreen` 逻辑，输入框需调起软键盘（TV 上是系统 IME）。
- 结果网格同 D2。
- 搜索历史项 `TVFocusable` 包裹。

**D4. TV 我的页 `lib/features/tv/tv_mine_screen.dart`**

- 复用 `MineScreen` 逻辑（收藏/历史），列表项 `TVFocusable` 包裹。
- 横屏布局：可双列展示。

**D5. TV 设置页 `lib/features/tv/tv_settings_screen.dart`**

- 复用 `SettingsScreen` 逻辑，所有开关/选项 `TVFocusable` 包裹。
- 横屏居中约束宽度（同桌面版 900 约束）。

**D 阶段完成标志**：TV 版首页三 tab 全程 D-pad 可操作，视觉与手机版统一。

**实际完成**：tv_shell.dart（TVAppShell 侧边导航 200 宽 + 内容区）、tv_library_screen.dart（库页，复用 LibraryScreen 逻辑 + TVFocusable）、tv_search_screen.dart、tv_mine_screen.dart（省略多选模式，改长按删除）、tv_settings_screen.dart（省略手势灵敏度，横屏居中 760 宽）。dramaColumns 增加 isAndroidTV 分支。全部编译通过，TV debug 构建成功。

---

### 阶段 E：TV 播放器 ✅ 已完成

**目标**：完整 TV 版播放器，遥控器全功能操作。

**实际完成**：tv_player_screen.dart 复用 PlaybackSession+MediaKitEngine+DeviceControls，UI 全新横屏固定。遥控器映射：OK=播放暂停，左右=快进快退10s（防抖800ms），上下=显示控件，BACK=退出，MENU=菜单面板。控件栏复用 PlayerGlass 玻璃风格 + accent 进度条。选集/倍速/画质面板走 showReelSheet dialog 分支。TV release 构建成功。

**E1. `lib/features/tv/tv_player_screen.dart`（TVPlayerScreen）**

- 基于 `PlayerScreen` 的横屏逻辑改造，**禁用全部手势**（不创建 `PlayerGestureController`）。
- 横屏锁定（TV 本就横屏，`SystemChrome.setPreferredOrientations([landscapeLeft, landscapeRight])`）。
- 复用 `MediaKitEngine` + `PlaybackSession` + `DeviceControls`（零改动）。
- 控件栏复用 `LandscapePlayerControls` 的视觉（`PlayerGlass` + `PlayerControlButton`），但：
  - 所有按钮 `TVFocusable` 包裹，D-pad 左右切换。
  - 进度条：D-pad 上下 seek（上 +10s，下 -10s），或左右长按。
  - OK 键：无焦点时播放/暂停，有焦点时激活按钮。
  - BACK：退出播放器（先关控件栏，再退出）。
  - MENU/选集按钮：弹出选集面板。
- 选集面板：`showReelSheet` dialog 分支 + `SheetFrame`，每集 `TVFocusable`。
- 画质/倍速面板：同上。

**E2. 遥控器媒体键**

- `TVKeyHandler` 捕获 MEDIA_REWIND/MEDIA_FAST_FORWARD → seek ±10s。
- MEDIA_PLAY_PAUSE → togglePlay（部分遥控器有专用键）。

**E 阶段完成标志**：TV 版播放器能用遥控器完成播放/暂停/seek/切集/退出全流程。

---

### 阶段 F：打磨与测试 ✅ 待开始

**目标**：impeccable 级别打磨 + 全设备验证。

**F1. 视觉打磨**

- 焦点环动画曲线、阴影、scale 微调。
- TV 大屏字号整体放大（`textScaler` 或 TV 专属字号）。
- 空状态/加载态/错误态在 TV 大屏的视觉（复用 `EmptyState`，放大图标）。

**F2. 测试矩阵**

- Android TV 模拟器（AVD: Android TV 1080p）。
- 真机：如有 TV 盒子/电视，装 TV APK 实测遥控器。
- 手机版回归：phone APK 在手机上功能不变。

**F3. 边界情况**

- 焦点丢失恢复（每页 autofocus 首项）。
- 低端盒子解码性能（必要时降画质提示）。
- 不同厂商遥控器按键差异。

**F 阶段完成标志**：TV 版在模拟器+真机流畅可用，手机版无回归。

---

## 3. 关键复用清单（TV 版直接复用，零改动）

| 层   | 文件                                      | 说明                                                  |
| ---- | ----------------------------------------- | ----------------------------------------------------- |
| 数据 | `data/local/sqlite_app_store.dart`        | SQLite 存储，TV/手机共用                              |
| 数据 | `data/repositories/drama_repository.dart` | 剧库仓库                                              |
| 数据 | `data/sources/hongguo/*`                  | 红果数据源 + CENC 解密                                |
| 播放 | `playback/playback_session.dart`          | 播放会话控制器                                        |
| 播放 | `playback/media_kit_engine.dart`          | media_kit 引擎                                        |
| 播放 | `playback/device_controls.dart`           | 亮度/音量/唤醒                                        |
| 播放 | `playback/native_error_guard.dart`        | 原生错误防护                                          |
| 领域 | `domain/models/*`                         | 数据模型                                              |
| 应用 | `app/app_controller.dart`                 | 全局状态                                              |
| 应用 | `app/theme.dart`                          | 主题（TV 版零改动）                                   |
| 组件 | `features/shared/widgets.dart`            | DramaCard/TagPill/SheetFrame 等（外层包 TVFocusable） |
| 组件 | `features/player/player_controls.dart`    | PlayerGlass/PlayerControlButton（TV 播放器复用）      |

## 4. TV 版新增文件清单

```
lib/features/tv/
├── tv_focus.dart              # TVFocusable + TVFocusScope（焦点系统）
├── tv_key_bindings.dart       # 遥控器按键映射
├── tv_shell.dart              # TVAppShell 主界面
├── tv_library_screen.dart     # TV 库页面
├── tv_search_screen.dart      # TV 搜索页
├── tv_mine_screen.dart        # TV 我的页
├── tv_settings_screen.dart    # TV 设置页
└── tv_player_screen.dart      # TV 播放器

android/app/src/
├── phone/
│   ├── AndroidManifest.xml
│   └── kotlin/app/minireel/minireel/MainActivity.kt
└── tv/
    ├── AndroidManifest.xml
    ├── kotlin/app/minireel/minireel/MainActivity.kt
    └── res/
        ├── drawable/tv_banner.xml
        └── values/themes.xml
```

## 5. 修改的现有文件清单

| 文件                                       | 改动                                               |
| ------------------------------------------ | -------------------------------------------------- |
| `android/app/build.gradle.kts`             | +flavorDimensions +productFlavors                  |
| `android/app/src/main/AndroidManifest.xml` | 精简为共享权限（application/activity 下放 flavor） |
| `lib/app/platform.dart`                    | +isAndroidTV +detectAndroidTv()                    |
| `lib/main.dart`                            | main() 调用 detectAndroidTv()                      |
| `lib/app/app.dart`                         | \_AppShell + \_play 增加 isAndroidTV 分支          |
| `lib/features/shared/widgets.dart`         | dramaColumns() 增加 isAndroidTV 分支               |

## 6. 构建命令速查

```bash
# 设置签名环境变量（见 memory #56）
export ANDROID_KEYSTORE_PATH=/Users/herren/Downloads/Code/flutter-hg/android/.signing/minireel-release.jks
export ANDROID_KEYSTORE_PASSWORD=<见 ANDROID_SIGNING_SECRETS.txt>
export ANDROID_KEY_ALIAS=<见 ANDROID_SIGNING_SECRETS.txt>
export ANDROID_KEY_PASSWORD=<见 ANDROID_SIGNING_SECRETS.txt>

# 手机版
flutter build apk --release --flavor phone --split-per-abi

# TV 版
flutter build apk --release --flavor tv --split-per-abi

# 产物：build/app/outputs/flutter-apk/
#   app-phone-release.apk / app-phone-arm64-v8a-release.apk 等
#   app-tv-release.apk / app-tv-arm64-v8a-release.apk 等
```

## 7. 接手指引（给下一个模型）

1. 读本文档了解全局。
2. 查看各阶段 ✅ 状态，找到第一个"待开始"或"进行中"的阶段。
3. 读该阶段的详细步骤，执行。
4. 完成后更新本文档状态为 ✅。
5. 用 `git log --oneline -5` 了解最近改动。
6. 关键设计约束：**TV 版绝对继承现有 UI 设计**（theme.dart + widgets.dart），不引入新色彩/新圆角/新字体。唯一新增视觉是焦点高亮环，用现有 accent 色表达。
7. 如遇上下文不足，用 `ctx_search` 搜索本会话历史，或读本文档 + 对应源文件。

MuMu 已经通过 ADB 连上了（127.0.0.1:5555）。调试命令是：
flutter run -d 127.0.0.1:5555 --flavor tv --dart-define=FORCE_TV=true
