import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../app/platform.dart';
import '../../domain/models/preferences.dart';
import '../shared/widgets.dart';
import '../player/desktop_player_input.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<int>? _cache;
  late final Future<PackageInfo?> _packageInfo = PackageInfo.fromPlatform()
      .then<PackageInfo?>((value) => value)
      .catchError((Object _) => null);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cache ??= AppScope.read(context).store.cacheBytes();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.watch(context);
    final prefs = app.preferences;
    const appearances = {
      AppAppearance.system: '跟随系统',
      AppAppearance.light: '浅色',
      AppAppearance.dark: '深色',
    };
    const sensitivities = {
      GestureSensitivity.low: '低',
      GestureSensitivity.medium: '中',
      GestureSensitivity.high: '高',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Text(
            '设置',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            children: [
              _group('主题', [
                _row(
                  Icons.dark_mode_outlined,
                  '外观',
                  value: appearances[prefs.appearance],
                  onTap: () async {
                    final result = await pickOption(
                      context,
                      title: '外观',
                      value: prefs.appearance,
                      options: appearances,
                    );
                    if (result != null) {
                      app.setPreferences(
                        app.preferences.copyWith(appearance: result),
                      );
                    }
                  },
                ),
                _toggle(
                  Icons.text_fields_rounded,
                  '大字模式',
                  prefs.largeText,
                  (v) => app.setPreferences(prefs.copyWith(largeText: v)),
                ),
              ]),
              _group('播放', [
                _row(
                  Icons.speed_rounded,
                  '默认倍速',
                  value: '${prefs.speed}x',
                  onTap: () async {
                    final value = await pickOption(
                      context,
                      title: '默认倍速',
                      value: prefs.speed,
                      options: {
                        for (final speed in playbackSpeeds) speed: '${speed}x',
                      },
                    );
                    if (value != null) {
                      app.setPreferences(
                        app.preferences.copyWith(speed: value),
                      );
                    }
                  },
                ),
                _row(
                  Icons.high_quality_outlined,
                  '优先画质',
                  value: prefs.quality,
                  onTap: () async {
                    final value = await pickOption(
                      context,
                      title: '优先画质',
                      subtitle: '播放时以该剧实际提供的画质为准',
                      value: prefs.quality,
                      options: {
                        '自动': '自动 · 优先最高画质',
                        '1080P': '1080P 高清',
                        '720P': '720P 流畅',
                        '480P': '480P 省流',
                      },
                    );
                    if (value != null) {
                      app.setPreferences(
                        app.preferences.copyWith(quality: value),
                      );
                    }
                  },
                ),
                _toggle(
                  Icons.skip_next_outlined,
                  '自动播放下一集',
                  prefs.autoNext,
                  (v) => app.setPreferences(prefs.copyWith(autoNext: v)),
                ),
                _toggle(
                  Icons.history_rounded,
                  '记忆播放进度',
                  prefs.rememberProgress,
                  (v) =>
                      app.setPreferences(prefs.copyWith(rememberProgress: v)),
                ),
              ]),
              if (isWindowsDesktop)
                _group('播放 · 桌面控制', [
                  _toggle(
                    Icons.minimize_rounded,
                    '最小化时暂停',
                    prefs.pauseWhenMinimized,
                    (value) => app.setPreferences(
                      prefs.copyWith(pauseWhenMinimized: value),
                    ),
                  ),
                  _row(
                    Icons.keyboard_outlined,
                    '鼠标与快捷键',
                    onTap: () => showReelSheet<void>(
                      context,
                      builder: (_) => const SheetFrame(
                        title: '鼠标与快捷键',
                        child: DesktopShortcutGuide(),
                      ),
                    ),
                  ),
                ]),
              if (!isWindowsDesktop)
                _group('播放 · 手势与控制', [
                  _row(
                    Icons.view_sidebar_outlined,
                    '控制栏位置',
                    value: prefs.railSide == RailSide.right ? '右侧' : '左侧',
                    onTap: () async {
                      final value = await pickOption(
                        context,
                        title: '控制栏位置',
                        subtitle: '点击屏幕边缘的小胶囊，呼出竖向播放控制栏',
                        value: prefs.railSide,
                        options: {RailSide.right: '右侧', RailSide.left: '左侧'},
                      );
                      if (value != null) {
                        app.setPreferences(
                          app.preferences.copyWith(railSide: value),
                        );
                      }
                    },
                  ),
                  _row(
                    Icons.tune_rounded,
                    '手势灵敏度',
                    value: sensitivities[prefs.sensitivity],
                    onTap: () async {
                      final value = await pickOption(
                        context,
                        title: '手势灵敏度',
                        subtitle: '低灵敏度需要滑动更远，适合减少误触',
                        value: prefs.sensitivity,
                        options: sensitivities,
                      );
                      if (value != null) {
                        app.setPreferences(
                          app.preferences.copyWith(sensitivity: value),
                        );
                      }
                    },
                  ),
                  _toggle(
                    Icons.vibration_rounded,
                    '触感反馈',
                    prefs.haptics,
                    (v) => app.setPreferences(prefs.copyWith(haptics: v)),
                  ),
                  _row(
                    Icons.touch_app_outlined,
                    '手势操作说明',
                    onTap: () => showReelSheet<void>(
                      context,
                      builder: (context) => const SheetFrame(
                        title: '手势操作说明',
                        child: GestureGuide(),
                      ),
                    ),
                  ),
                ]),
              _group('剧库与存储', [
                ListenableBuilder(
                  listenable: app.repository,
                  builder: (context, _) => _row(
                    Icons.sync_rounded,
                    '更新剧库',
                    value: app.repository.refreshing
                        ? '更新中…'
                        : '${app.repository.catalog.length} 部',
                    onTap: app.repository.refreshing
                        ? null
                        : () async {
                            final before = app.repository.catalog.length;
                            await app.repository.updateCatalog();
                            if (context.mounted) {
                              final added =
                                  app.repository.catalog.length - before;
                              final result = added > 0
                                  ? '本次新增 $added 部短剧'
                                  : '本次未发现新增短剧';
                              showToast(
                                context,
                                app.repository.errors.isEmpty
                                    ? result
                                    : '$result，部分内容未能更新，已保留原有短剧',
                              );
                            }
                          },
                  ),
                ),
                FutureBuilder<int>(
                  future: _cache,
                  builder: (context, snapshot) => _row(
                    Icons.cleaning_services_outlined,
                    '清理剧库缓存',
                    value: snapshot.hasData ? _size(snapshot.data!) : '—',
                    onTap: () => _clearCache(app),
                  ),
                ),
              ]),
              _group('关于', [
                FutureBuilder<PackageInfo?>(
                  future: _packageInfo,
                  builder: (context, snapshot) => _row(
                    Icons.info_outline_rounded,
                    '版本',
                    value: snapshot.data == null
                        ? '—'
                        : '${snapshot.data!.version} (${snapshot.data!.buildNumber})',
                  ),
                ),
                _row(
                  Icons.article_outlined,
                  '使用许可',
                  value: '仅限非商业用途',
                  onTap: () async {
                    final info = await _packageInfo;
                    if (!context.mounted) return;
                    showLicensePage(
                      context: context,
                      applicationName: 'MiniReel',
                      applicationVersion: info?.version,
                      applicationLegalese:
                          'MiniReel · PolyForm Noncommercial 1.0.0\n'
                          '仅限许可条款允许的非商业用途。\n'
                          '第三方组件适用各自的许可证。',
                    );
                  },
                ),
              ]),
              const SizedBox(height: 8),
              const Center(child: BrandMark(size: 46)),
              const SizedBox(height: 10),
              const Center(
                child: Text(
                  'MiniReel',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Center(
                child: Text(
                  '好故事，随时开场',
                  style: TextStyle(color: context.muted, fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(0)} KB'
      : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  Future<void> _clearCache(AppController app) async {
    final clear = await showReelSheet<bool>(
      context,
      builder: (context) => SheetFrame(
        title: '清理剧库缓存',
        footer: FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('清理缓存'),
        ),
        child: Text(
          '清理已加载的短剧与分集资料。收藏、观看记录和设置会保留，下次可重新刷新剧库。',
          style: TextStyle(color: context.muted, height: 1.7),
        ),
      ),
    );
    if (clear != true || !mounted) return;
    await app.repository.clearCache();
    if (!mounted) return;
    setState(() => _cache = app.store.cacheBytes());
    showToast(context, '剧库缓存已清理');
  }

  Widget _group(String label, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(5, 7, 5, 10),
          child: Text(
            label,
            style: TextStyle(
              color: context.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Material(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(19),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, thickness: .6, indent: 16, endIndent: 16),
                children[i],
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _row(
    IconData icon,
    String title, {
    String? value,
    Widget? trailing,
    VoidCallback? onTap,
  }) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.muted),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 14.5))),
          if (value != null)
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(color: context.muted, fontSize: 13),
              ),
            ),
          if (trailing != null)
            trailing
          else if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: context.muted.withValues(alpha: .5),
              size: 18,
            ),
          ],
        ],
      ),
    ),
  );

  Widget _toggle(
    IconData icon,
    String title,
    bool enabled,
    ValueChanged<bool> onChanged,
  ) => _row(
    icon,
    title,
    onTap: () => onChanged(!enabled),
    trailing: SizedBox(
      height: 23,
      child: Switch(
        value: enabled,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );
}

class GestureGuide extends StatelessWidget {
  const GestureGuide({super.key, this.landscape = false});
  final bool landscape;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final row
          in landscape
              ? const [
                  ('单击屏幕', '显示 / 隐藏控制栏'),
                  ('左右滑动', '微调进度，松手跳转'),
                  ('长按屏幕', '临时 2 倍速，松手恢复'),
                  ('亮度调节', '使用播放菜单中的亮度滑块'),
                  ('音量调节', '使用系统音量键或播放菜单滑块'),
                  ('底部控制栏', '播放、选集、倍速、锁定和切回竖屏'),
                  ('系统返回', '先退出横屏，再返回剧库'),
                ]
              : const [
                  ('上半区长按', '呼出播放菜单，选集 / 收藏 / 倍速'),
                  ('下半区长按', '临时 2 倍速，松手恢复原倍速'),
                  ('长按后横滑', '微调播放进度，松手跳转'),
                  ('上下滚动', '画面跟随手指，松手翻到上一集 / 下一集'),
                  ('亮度和音量', '打开播放菜单拖动滑块调节'),
                  ('单击屏幕', '播放 / 暂停，并显示顶部控制栏'),
                  ('侧边小胶囊', '时间与进度、横屏播放、锁定屏幕'),
                ])
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 87,
                child: Text(
                  row.$1,
                  style: TextStyle(
                    color: context.colors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  row.$2,
                  style: TextStyle(
                    color: context.colors.onSurface.withValues(alpha: .85),
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
