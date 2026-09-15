import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../domain/models/preferences.dart';
import '../shared/widgets.dart';
import 'mac_theme.dart';

/// macOS 版设置页。
///
/// 复用 SettingsScreen 的设置项逻辑，重新设计布局：
/// - 分组卡片用 macOS 风格的小圆角（10）+ 分隔线
/// - 桌面控制组对 Mac 版生效（最小化暂停）
/// - 手势组替换为键盘快捷键说明（后续可扩展）
class MacSettingsScreen extends StatefulWidget {
  const MacSettingsScreen({super.key});
  @override
  State<MacSettingsScreen> createState() => _MacSettingsScreenState();
}

class _MacSettingsScreenState extends State<MacSettingsScreen> {
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 2, 0, 16),
            child: Text(
              '设置',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 28),
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
                  '键盘快捷键',
                  onTap: () => showReelSheet<void>(
                    context,
                    builder: (_) => const SheetFrame(
                      title: '键盘快捷键',
                      child: _MacShortcutGuide(),
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
              const SizedBox(height: 12),
              const Center(child: BrandMark(size: 40)),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'MiniReel',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Center(
                child: Text(
                  '好故事，随时开场',
                  style: TextStyle(color: context.muted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
      ),
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
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
          child: Text(
            label,
            style: TextStyle(
              color: context.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
        Material(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(MacTheme.radiusContainer),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: .5,
                    indent: 12,
                    endIndent: 12,
                    color: context.macSeparator,
                  ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 17, color: context.muted),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontSize: 13)),
          const Spacer(),
          if (value != null) ...[
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.muted, fontSize: 12.5),
            ),
            const SizedBox(width: 4),
          ],
          if (trailing != null)
            trailing
          else if (onTap != null)
            Icon(
              Icons.chevron_right_rounded,
              color: context.muted.withValues(alpha: .4),
              size: 15,
            ),
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
      height: 22,
      child: Switch(
        value: enabled,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );
}

/// macOS 版键盘快捷键说明。
class _MacShortcutGuide extends StatelessWidget {
  const _MacShortcutGuide();
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final row in const [
        ('空格 / K', '播放 / 暂停'),
        ('← / →', '后退 / 前进 5 秒'),
        ('↑ / ↓', '音量增减'),
        ('J / L', '后退 / 前进 10 秒'),
        ('← / →（长按）', '2 倍速快进'),
        ('F', '全屏 / 退出全屏'),
        ('Esc', '退出播放器'),
        ('N', '播放下一集'),
      ])
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
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
