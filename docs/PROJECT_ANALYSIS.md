# MiniReel 项目分析

> 本文档为本地项目分析笔记，不纳入版本控制（见 `.gitignore`）。
> 生成时间：2026-09-14 · 分析对象：`main` 分支（commit `1cc888d`）

## 一、项目概览

**MiniReel** 是一款支持 **Android 7.0+** 和 **Windows 10/11 x64** 的沉浸式短剧播放器，定位为"好故事，随时开场"。无需注册账号，收藏、观看记录和设置全部保存在设备本地。

| 维度 | 内容 |
| --- | --- |
| 技术栈 | Flutter (Dart SDK ^3.11.0) |
| 播放内核 | `media_kit`（基于 mpv） |
| 本地存储 | SQLite（Android 用 `sqflite`，Windows 用 `sqflite_common_ffi`） |
| 网络 | `dio` |
| 加密 | `pointycastle`（AES-CBC，解析片源加密响应） |
| 代码规模 | lib/ 约 2063 行 Dart，test/ 约 1519 行 |
| Git 历史 | 2 个提交（Android 首版 + Windows 端实现），早期阶段 |
| 许可证 | MIT |

## 二、架构设计（分层清晰）

项目采用经典的**分层架构**，目录结构规范：

```
lib/
├── main.dart              # 启动引导 (MiniReelBootstrap)
├── app/                   # 应用层
│   ├── app.dart           # MaterialApp + 平台分发壳
│   ├── app_controller.dart# 全局状态 (收藏/历史/偏好) + AppScope
│   ├── theme.dart         # 主题
│   └── platform.dart      # 平台判断
├── core/                  # 基础设施
│   ├── config/            # SourceConfig (sources.json)
│   ├── network/           # AppHttpClient
│   └── errors/            # AppException
├── data/                  # 数据层
│   ├── local/             # AppStore 接口 + SqliteAppStore
│   ├── repositories/      # DramaRepository
│   └── sources/hongguo/   # 红果片源适配器
├── domain/                # 领域模型
│   └── models/            # Drama, Episode, WatchRecord, Preferences, PlaybackSource
├── features/              # 功能页面
│   ├── library/ search/ detail/ mine/ settings/ player/
├── desktop/               # Windows 桌面壳 (导航/标题栏/窗口管理)
└── playback/              # 播放引擎
    ├── playback_engine.dart     # 引擎接口
    ├── media_kit_engine.dart    # media_kit 实现
    ├── playback_session.dart    # 会话控制器
    └── native_error_guard.dart  # 原生错误守卫
```

### 关键设计亮点

**1. 可插拔片源（SourceAdapter 模式）**
`DramaSourceAdapter` 接口 + `SourceRegistry` 让片源可扩展。目前只接入了"红果剧库"一个源，但架构上支持多源并存。`DramaRepository` 用 `Future.wait` 并发拉取所有源的各频道分页。

**2. 播放引擎抽象**
`PlaybackEngine` 接口隔离了 `MediaKitEngine` 实现，`EngineSnapshot` 作为不可变状态快照。这让播放层可测试、可替换。

**3. PlaybackSession 会话控制器**（最复杂的类）
- **代际取消**（`_generation` + `CancelToken`）：用户快速切集时旧请求被作废，避免竞态
- **恢复阶梯**（`_recoveryStep` 上限 2）：主源失败 → 备用片源 → 降清晰度 → 最终报错
- **暂停原因集合**（`_pauseReasons`）：锁屏/最小化/切清晰度等各自记原因，互不覆盖
- **30 秒加载超时** + **5 秒进度落盘**
- **自动播放下一集**

**4. 加密片源解码**（`HongguoPlaybackCodec`）
从上游 Go 代码（`provider_hongguo_playback.go`）逐字节移植的 AES-CBC 解密器，处理 `v2.*` 格式的响应信封和每集 CENC 内容密钥。密钥**绝不持久化**，每次播放重新解析。代码注释解释了每一步的反混淆逻辑。

**5. 本地存储**
单文件 SQLite（`minireel.db`），5 张表全部用 `payload` JSON blob 存储，schema 极简（version 1）。巧妙处理了 Android 7 自带 SQLite 的兼容性（`INSERT OR IGNORE + UPDATE` 保序）。

## 三、双端适配

- **Android**：竖屏沉浸式（侧栏进度条从上向下前进）+ 横屏底部控制栏，丰富的手势（亮度/音量/进度/临时倍速/锁屏）
- **Windows**：窄图标侧栏导航、自定义标题栏、键盘快捷键、全屏、迷你置顶、窗口置顶、适应视频窗口

`isWindowsDesktop` 在 `app.dart`、`main.dart` 等处做平台分发，桌面端用 `window_manager` + `screen_retriever` 管理窗口。

## 四、测试与工程化

- **测试**：11 个测试文件覆盖播放会话、手势、控件、仓库、HTTP 客户端、原生错误守卫、Windows 持久化等，有 `fixtures` 和 `support` 目录
- **集成测试**：`integration_test/` 目录
- **工具脚本**：`tool/` 下有 Windows 安装包构建、Android 签名、图标生成、片源探测、发布脚本（含 `release.test.cjs`）
- **文档**：`docs/` 下有构建说明和双端验收清单
- **CI**：`.github/workflows/release.yml` 在 `v*` 标签推送时构建 Windows 安装包 + Android 分架构 APK 并发布 Release

## 五、核心模块详解

### 5.1 启动流程（`main.dart`）

`main()` → 初始化 WidgetsBinding → Windows 下初始化桌面窗口 → `MediaKit.ensureInitialized()` → Android 设为 edge-to-edge → `MiniReelBootstrap`。

`MiniReelBootstrap` 用 `FutureBuilder` 承载启动异步链：
1. 读取 `assets/config/sources.json` → 构造 `SourceConfig`
2. 创建 `AppHttpClient`、打开 `SqliteAppStore`
3. 注册 `HongguoAdapter` 到 `SourceRegistry`（仅当 `config.enabled`）
4. 构造 `DramaRepository` + `AppController`，调用 `app.initialize()`
5. Windows 下注册 `onAppClose` 回调做优雅关闭（flush → dispose → close）

启动失败时显示"本地数据暂时无法读取"并提供重试按钮。

### 5.2 全局状态（`app_controller.dart`）

`AppController extends ChangeNotifier`，持有 `preferences / favorites / history / searches`，通过 `AppScope`（`InheritedNotifier`）向整棵树提供。写入采用串行队列 `_writes`，避免并发写竞争；任何写入失败会设置 `persistenceError` 横幅提示用户。历史记录上限 200 条。

### 5.3 数据仓库（`drama_repository.dart`）

`DramaRepository` 负责剧库的刷新、分页加载、详情获取、播放解析：
- **并发拉取**：`refresh()` 对所有源 × 所有频道第 1 页并发请求
- **分页合并**：`loadMore()` 按 `_exhausted` 标记跳过已耗尽的频道
- **重复页检测**：`_previousPageIds` 防止源返回相同内容时无限翻页
- **缓存优先**：`getDetail` 失败时回退到本地缓存
- **代际保护**：`_generation` + `CancelToken` 防止旧请求污染新状态

### 5.4 播放会话（`playback_session.dart`）

这是全项目最复杂、也最关键的类，管理一次观看的完整生命周期：

| 机制 | 作用 |
| --- | --- |
| `_generation` + `CancelToken` | 快速切集/退出时作废旧请求，杜绝竞态 |
| `_recoveryStep`（上限 2） | 主源失败 → 备用片源 → 降清晰度 → 报错 |
| `_pauseReasons` Set | 锁屏/最小化/切清晰度等各自记原因，互不覆盖 |
| `_wantPlaying` | 用户意图（想播放），与引擎实际状态分离 |
| `_acceptEvents` | 加载期间屏蔽引擎事件，避免误触发恢复 |
| 30s `_loadTimer` | 加载卡住超时自动进入恢复 |
| 5s `_recordTimer` | 周期性落盘观看进度 |
| `autoNext` | 播完自动下一集（可在设置关闭） |

### 5.5 加密解码（`hongguo_playback_codec.dart`）

逐字节移植自上游 Go 的 `provider_hongguo_playback.go`：
- `decodeResponse`：处理 `v2.*` 信封，用 20 字节掩码表 + 前字节异或 + 位旋转还原密钥材料，再 AES-CBC 解密
- `decodeContentKey`：解析每集 CENC 内容密钥，含 tag 校验、奇偶前字节追踪、popcount 计数
- 所有失败统一抛 `AppException(kind: FailureKind.parsing)`，错误信息面向用户

### 5.6 本地存储（`sqlite_app_store.dart`）

5 张表：`catalog / details / favorites / history / settings`，全部 `payload` JSON blob。Windows 用 `sqflite_common_ffi`，Android 用 `sqflite`。`saveCatalog` 用 `INSERT OR IGNORE + UPDATE` 兼容 Android 7 自带 SQLite 且保序。历史上限 200 行（写入时裁剪）。

## 六、值得关注

### 优点
- 架构分层干净，关注点分离到位
- 播放会话的并发/竞态处理非常成熟（代际取消、恢复阶梯、暂停原因集合）
- 加密解码逻辑移植严谨，注释解释"为什么"而不只是"是什么"
- 错误处理面向用户友好（"网络连接失败，请重试"而非堆栈）
- 本地优先、无账号、隐私友好
- 测试覆盖较全（11 个测试文件 + 集成测试）

### 潜在改进方向
1. **片源单一**：目前只有红果一个源，`SourceRegistry` 架构已就绪，可扩展更多源提升内容覆盖
2. **Schema 演进**：DB version 固定为 1，未来加字段需要 `onUpgrade` 迁移路径，目前没有
3. **`payload` JSON blob**：查询/索引能力弱，但对此应用规模够用
4. **Git 历史只有 2 个提交**：建议后续细化提交粒度，便于回溯
5. **无离线下载**：README 明确说暂不支持，是产品边界而非缺陷

## 七、构建与发布

- **CI 触发**：推送 `v*` 标签 → `release.yml` 并行构建 Windows + Android
- **Android 产物**：`flutter build apk --release --split-per-abi`，产出 `arm64-v8a / armeabi-v7a / x86_64` 三个 APK，用 apksigner 验证签名一致性
- **Windows 产物**：`flutter build windows --release` + Inno Setup 打包 `windows-x64-setup.exe`
- **签名**：Android 通过 `tool/release.cjs restore-keystore` 从 GitHub secrets 还原 keystore；本地构建可用 `tool/create_android_signing.ps1` 生成
- **Flutter 版本**：CI 锁定 `3.41.9 stable`

---

整体来看，这是一个**架构成熟度远超其 Git 历史所暗示的早期项目**——播放会话的并发控制、加密解码、双端适配都做得很扎实，代码注释质量高，测试覆盖也到位。
