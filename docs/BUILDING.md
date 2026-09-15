# 开发与构建

本文描述当前 Flutter 工程的实际构建方式。使用介绍见 [README](../README.md)，人工验收见 [Android 验收清单](04_Android首版验收清单.md)和 [Windows 验收清单](05_Windows验收清单.md)。

## 环境

建议固定使用 Flutter **3.41.9 stable**，对应 Dart **3.11.5**。`pubspec.yaml` 要求 Dart 3.11 或更高的兼容版本，提交的 `pubspec.lock` 用于锁定应用依赖。

| 工具 | 当前配置 |
| --- | --- |
| Java | JDK 17 |
| Android compile / target SDK | 36，由 Flutter SDK 提供默认值 |
| Android 最低版本 | API 24 / Android 7.0 |
| Android NDK | 28.2.13676358，由 Flutter SDK 提供默认值 |
| Android Gradle Plugin | 8.11.1 |
| Kotlin | 2.2.20 |
| Gradle | 8.14，使用仓库内的 wrapper |

需要接受 Android SDK licenses，并允许构建期间下载 Dart/Maven 依赖、Gradle 和 `media_kit` 使用的原生媒体库。应用无需 Go、Node.js 或外部 FFmpeg 可执行文件。

Windows x64 构建需要 Windows 10/11、Visual Studio 2022 或更新版本，以及「使用 C++ 的桌面开发」工作负载（包含 MSVC、CMake 和 Windows SDK）。先用 `flutter doctor -v` 确认 Windows 和 Visual Studio 检查通过。Windows 构建不依赖 Android SDK。

## 获取与运行

```sh
git clone https://github.com/Minireel/minireel.git
cd minireel
flutter pub get --enforce-lockfile
flutter devices
flutter run -d <设备ID>
```

Android debug 构建禁用 Impeller，使用 Skia/OpenGL，以避开部分模拟器的 MESA/Vulkan `VkFence` 问题。该配置不影响 release 构建。修改原生 Manifest 后需要停止应用并重新运行，热重载不能切换渲染后端。

## 检查与打包

```sh
flutter analyze --no-pub
flutter test test --no-pub
flutter build apk --release --flavor phone --split-per-abi
flutter build apk --release --flavor tv --split-per-abi
```

Flutter 3.41.9 的 Release 打包命令需要保留默认的 Pub 步骤，以按发布模式重新生成插件注册文件、排除仅用于开发的 `integration_test` 插件。这里不要添加 `--no-pub`，否则前面的依赖获取或测试可能留下包含测试插件的注册文件，导致 Java 编译报 `IntegrationTestPlugin` 找不到。静态检查和单元测试可以继续使用 `--no-pub`。

安装包位于 `build/app/outputs/flutter-apk/`，文件名为 `app-<abi>-<flavor>-release.apk`。`phone` 和 `tv` 各面向 `arm64-v8a`、`armeabi-v7a` 和 `x86_64`。不加 `--split-per-abi` 可为指定 flavor 生成单个通用 APK。Android 运行时也需指定 `--flavor phone` 或 `--flavor tv`。

**Android Release 构建必须配置正式签名，缺少时会直接失败。** CI 从 GitHub Secrets 还原签名文件，本地可设置 `ANDROID_KEYSTORE_PATH`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS` 和 `ANDROID_KEY_PASSWORD`，或在被 Git 忽略的 `android/key.properties` 中填写 `storeFile`、`storePassword`、`keyAlias`、`keyPassword`。`storeFile` 的相对路径以 `android/` 为基准。Debug 构建继续使用开发签名。

应用版本由 `pubspec.yaml` 的 `version` 控制，也可通过 Flutter 的 `--build-name` / `--build-number` 覆盖。

## Windows 运行与打包

```sh
flutter pub get --enforce-lockfile
flutter run -d windows
flutter build windows --release
```

可执行文件位于 `build/windows/x64/runner/Release/minireel.exe`。分发时需要压缩 **整个 `Release/` 目录**，包括 `data/` 和旁边的 DLL，不能只分发 `.exe`。`media_kit_libs_windows_video` 提供视频原生库；SQLite 3 由 Dart build hooks 构建并随目录打包，无需用户单独安装 SQLite 或 FFmpeg。

Windows 同样先执行静态检查和 `flutter test test --no-pub`，再执行带默认 Pub 步骤的 Release 构建。安装 Inno Setup 6.3 或更新版本后，可执行 `./tool/build_windows_installer.ps1 -Version 0.1.0 -BuildNumber 1`，在 `output/release/` 生成安装程序。安装程序按当前用户安装，包含 Flutter、视频、SQLite 和 MSVC 运行库。

数据库和窗口位置保存在 `path_provider` 返回的应用支持目录，独立于安装目录。Windows 图标已包含在原生工程中，常规构建不需要重新生成。

## GitHub Actions 自动发布

[Release workflow](../.github/workflows/release.yml) 在推送 `v` 开头的版本 tag 时运行，例如 `v0.1.0` 或 `v0.2.0-beta.1`。普通分支推送不会发布。应用版本来自 tag，构建号来自该工作流的 `github.run_number`；预发布 tag 自动标记为 prerelease。

在仓库 Settings → Secrets and variables → Actions 添加四项 Repository Secrets：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 完整签名 keystore 文件的 Base64 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 签名 key alias |
| `ANDROID_KEY_PASSWORD` | 签名 key 密码 |

后续版本应继续使用同一签名。首次从开发签名包切换到正式签名包时，需要卸载原开发包再安装。

工作流并行构建 Windows x64 安装程序、Android 手机版和 TV 版；两个 Android flavor 各构建三种 ABI APK，使用相同的签名 Secrets，并逐个验证签名。全部成功后，发布任务创建草稿 Release、上传七个安装文件和 `SHA256SUMS.txt`，最后公开 Release。手机版沿用 `MiniReel-<版本>-android-<abi>.apk`，TV 版使用 `MiniReel-<版本>-android-tv-<abi>.apk`，产物收集和校验均要求两个版本齐全。无需额外配置发布 token，任务使用仅在发布 job 授予写权限的 `GITHUB_TOKEN`。

```sh
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

已公开的同名 Release 不会被覆盖；新版本使用新 tag。未完成的草稿可通过重新运行失败任务续传。`ANDROID_SIGNING_SECRETS.txt`、`android/.signing/` 和本地 `key.properties` 均被 Git 忽略，临时 txt 填写完 Secrets 后删除。

`integration_test/` 中已有的 Android 测试需要设备和真实网络/片源。它们应作为单独的人工或设备验收步骤，不宜作为每次打包的固定前置条件。Windows 键盘、导航、播放生命周期和 SQLite 持久化回归包含在 `test/` 中。

## 仓库完整性

以下文件是工程的一部分，必须保留在版本控制中：

- `lib/`、`pubspec.yaml`、`pubspec.lock`、`.metadata` 和 `analysis_options.yaml`。
- `License`：项目的 PolyForm Noncommercial 1.0.0 完整许可及 Required Notice，作为 Flutter 资源随两端应用分发；Windows 安装程序也直接读取它。
- `assets/logo.png` 与 **`assets/config/sources.json`**。
- `android/` 的 Manifest、Kotlin 入口、Gradle 配置、图标和启动页资源。
- `android/gradlew`、`android/gradlew.bat`、`android/gradle/wrapper/gradle-wrapper.jar` 和对应 `.properties`。
- `windows/` 的 CMake、runner 源码、Manifest、资源定义和 `runner/resources/app_icon.ico`；Flutter 生成的插件注册文件与 `ephemeral/` 目录保持忽略。
- `test/`，包括 `test/fixtures/playback_codec.json`；以及 `integration_test/`、`tool/`。

`.gitattributes` 保证 Unix wrapper 的 LF 换行，Git 中的 `android/gradlew` 保留可执行权限，便于 Linux runner 使用。

`android/local.properties`、SDK 路径、构建缓存和插件注册文件由本机 Flutter 工具生成，不应提交。`build/`、`.tmp/`、`output/` 和签名材料同样忽略。

本地的 `api-example/`、`ui.ux-example/` 以及最初的三份迁移规划资料属于参考材料，已在 `.gitignore` 中排除。当前应用运行和打包不读取这些目录。后续维护以现有代码、本文和当前验收清单为准。

## 数据源配置

`assets/config/sources.json` 已包含当前使用的数据源默认配置，并由 `pubspec.yaml` 声明为必需资源。它必须随代码提交；正常构建和运行不需要额外的私有配置文件。

可选编译覆盖项：

| 参数 | 作用 |
| --- | --- |
| `MINIREEL_BASE_URL` | 覆盖剧库网页地址，同时调整网页 Referer |
| `MINIREEL_APP_BASE_URL` | 覆盖原生 App API 地址 |
| `MINIREEL_PLAYBACK_ENDPOINT` | 覆盖备用播放接口 |

这些地址不等于账号凭据；未来若接入需要 token 的服务，应另外设计凭据管理。现有临时视频 URL 和每集内容密钥只在运行时内存中使用，不写入应用数据库。

数据流为 `SourceAdapter → DramaRepository → PlaybackSession → media_kit`。红果剧库与详情优先使用 App API，失败时回退网页；播放依次尝试 App、网页和旧备用接口。实际媒体加载失败也会沿此顺序恢复并保留进度，App 路径最多自动恢复三次，网页与旧备用路径最多两次。下一集预解析命中后若媒体失效，会先额外重新解析当前路径一次，再进入上述回退流程。

App 的地址、User-Agent、版本及通用参数分别由 `appBaseUrl`、`appUserAgent`、`appParameters` 和 `appHeaders` 配置。缺少 App 地址时保留网页模式。设备标识在首次请求时生成并保存在 SQLite；各分类的 App 游标与网页页码独立维护，和剧库数据一起事务写入。刷新扫描最多三页头部并保留历史续拉位置，清理剧库缓存会清除游标与详情缓存，保留设备标识、收藏和观看记录。默认 App 分类为真人剧、漫剧与 AI 剧，动漫来自网页兜底或已有缓存。

设置中的「更新剧库」在检查头部新内容后，每个分类从保存的位置继续加载最多三页历史目录；到末页或该分类请求失败时停止续拉。新增内容和分页位置逐页保存，下一次手动更新接着加载，并提示本次新增数量。启动时仍只做轻量刷新。目录已加载完、返回内容重复或请求失败时，数量不保证增长。

P1 的联网搜索与榜单通过可选 `RemoteSearchSource`、`RankingSource` 能力接入。两者使用网页数据，缓存五分钟，并合并相同请求；搜索词限制为 1–80 字符。榜单同时解析内联与后续脚本属性中的内容，校验榜单、页码和真实名次，不补造连续排名。搜索与榜单结果合并进 SQLite 剧库，缺失字段不会抹掉已有封面、集数和元数据。

评分、播放量、热度与上线日期保存在现有 JSON 数据列中，兼容旧缓存，无需改表。排序只针对已加载数据，缺失值排末尾，不启动批量详情补全。弹幕和批量元数据补全仍属 P2。

播放稳定 800 毫秒后，会解析下一集并用一个暂停、静音的 media_kit 播放器预加载媒体、初始化解码器与画面。备用播放器的媒体缓冲上限为 8 MiB，预读目标为 12 秒；当前播放器前向缓冲上限为 32 MiB，回看缓冲为 8 MiB。命中时直接接替播放，不重新打开同一地址。普通媒体、HLS 和 CENC 共用原生解码链路，分别设置每集请求头和解密参数。缓存只在内存中保留，不写入媒体文件或应用数据库。

只预加载下一集，不批量下载。预解析信息三分钟过期，当前集仍在播放时会更新；切画质、跳集、后台、内存压力和退出会释放失效的预加载。当前集缓冲时先取消备用加载，优先保障当前播放。预加载失败仍可正常解析、播放，命中后媒体失效则先重新解析当前路径，再沿三级链路回退。短于 180 毫秒的切换不显示加载圈。

Android 竖屏使用纵向 `PageView`，画面随手指滚动，页面停稳后才切换播放；自动连播和选集会同步滚动位置。单击、长按与翻页通过 Flutter 手势识别器共同仲裁，长按识别后保持控制权，横向拖动只预览进度，松手提交。锁屏、弹层、长按拖动进度时禁用翻页。Android 横屏与 Windows 保留常规播放控件，不接入滚动切集，但共享媒体预加载。Android 两种方向均移除上下滑动调亮度、音量，亮度改用播放菜单滑块，音量使用系统音量键或菜单滑块。

## 辅助工具

```sh
# 只读检查剧库、详情和前两集播放解析
dart run tool/probe_source.dart
dart run tool/probe_source.dart --fallback

# 替换 logo 后重新生成 Windows 和 Android 图标
dart run tool/generate_icons.dart

# 仅重新生成 Windows 图标
dart run tool/generate_icons.dart --windows-only

# 修改协议解码测试样本时使用；常规构建无需 Node.js
node tool/generate_codec_vectors.cjs
```

协议测试样本为合成数据，不包含真实播放密钥。图标和测试样本的现有输出已提交，无需在 CI 中重新生成。

## 平台范围

当前包含 Android 和 Windows x64 runner，两端共用数据源、播放会话和收藏/历史模型。Windows 使用独立的桌面播放控制、窗口管理和 SQLite FFI backend；Android 继续使用触屏手势和原生 SQLite 插件。当前不提供 macOS / iOS 工程。
