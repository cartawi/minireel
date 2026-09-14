import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../domain/models/preferences.dart';
import '../shared/widgets.dart';
import 'tv_focus.dart';

/// TV 版设置页。
/// 复用 SettingsScreen 的核心设置项，省略 TV 不适用的项（手势灵敏度）。
/// 所有交互元素用 TVFocusable 包裹。横屏居中约束宽度。
class TVSettingsScreen extends StatefulWidget {
  const TVSettingsScreen({super.key});
  @override
  State<TVSettingsScreen> createState() => _TVSettingsScreenState();
}

class _TVSettingsScreenState extends State<TVSettingsScreen> {
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 22, 24, 18),
              child: Text(
                '设置',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  children: [
                  _group(context, '主题', [
                    _navRow(
                      context,
                      Icons.dark_mode_outlined,
                      '外观',
                      appearances[prefs.appearance]!,
                      () => _pick(
                        context,
                        '外观',
                        appearances,
                        prefs.appearance,
                        (v) => app.setPreferences(prefs.copyWith(appearance: v)),
                      ),
                    ),
                    _switchRow(
                      context,
                      Icons.text_fields_rounded,
                      '大号文字',
                      '放大界面文字，适合远距离观看',
                      prefs.largeText,
                      (v) => app.setPreferences(
                        prefs.copyWith(largeText: v),
                      ),
                    ),
                  ]),
                  _group(context, '播放', [
                    _switchRow(
                      context,
                      Icons.history_rounded,
                      '记忆观看进度',
                      '下次打开自动跳到上次看到的位置',
                      prefs.rememberProgress,
                      (v) => app.setPreferences(
                        prefs.copyWith(rememberProgress: v),
                      ),
                    ),
                    _navRow(
                      context,
                      Icons.speed_rounded,
                      '默认倍速',
                      '${prefs.speed}x',
                      () => _pick(
                        context,
                        '默认倍速',
                        {
                          0.5: '0.5x',
                          0.75: '0.75x',
                          1.0: '1.0x',
                          1.25: '1.25x',
                          1.5: '1.5x',
                          2.0: '2.0x',
                        },
                        prefs.speed,
                        (v) => app.setPreferences(
                          prefs.copyWith(speed: v),
                        ),
                      ),
                    ),
                  ]),
                  _group(context, '存储', [
                    FutureBuilder<int>(
                      future: _cache,
                      builder: (context, snapshot) => _navRow(
                        context,
                        Icons.cached_rounded,
                        '清除缓存',
                        snapshot.hasData
                            ? '${_mb(snapshot.data!)} MB'
                            : '计算中…',
                        snapshot.hasData && snapshot.data! > 0
                            ? () => _clearCache(app)
                            : null,
                      ),
                    ),
                  ]),
                  _group(context, '关于', [
                    FutureBuilder<PackageInfo?>(
                      future: _packageInfo,
                      builder: (context, snapshot) {
                        final info = snapshot.data;
                        return _infoRow(
                          context,
                          Icons.info_outline_rounded,
                          '版本',
                          info != null
                              ? '${info.version} (${info.buildNumber})'
                              : '—',
                        );
                      },
                    ),
                    _infoRow(
                      context,
                      Icons.tv_rounded,
                      '设备',
                      'Android TV',
                    ),
                  ]),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'MiniReel TV · 好故事，随时开场',
                      style: TextStyle(
                        color: context.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _group(BuildContext context, String title, List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.muted,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    children[i],
                    if (i < children.length - 1)
                      Divider(
                        height: 1,
                        indent: 56,
                        color: Theme.of(context).dividerColor,
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  Widget _navRow(
    BuildContext context,
    IconData icon,
    String title,
    String value,
    VoidCallback? onTap,
  ) => TVFocusable(
    radius: 16,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 22, color: context.muted),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 14, color: context.muted),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: context.muted,
          ),
        ],
      ),
    ),
  );

  Widget _switchRow(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: [
        Icon(icon, size: 22, color: context.muted),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: context.muted),
              ),
            ],
          ),
        ),
        TVFocusable(
          radius: 20,
          onTap: () => onChanged(!value),
          child: Switch(
            value: value,
            onChanged: onChanged,
          ),
        ),
      ],
    ),
  );

  Widget _infoRow(
    BuildContext context,
    IconData icon,
    String title,
    String value,
  ) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(
      children: [
        Icon(icon, size: 22, color: context.muted),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 14, color: context.muted),
        ),
      ],
    ),
  );

  Future<void> _pick<T>(
    BuildContext context,
    String title,
    Map<T, String> options,
    T value,
    ValueChanged<T> onSelected,
  ) async {
    final result = await showReelSheet<T>(
      context,
      builder: (context) => SheetFrame(
        title: title,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: TVFocusable(
                  radius: 12,
                  onTap: () => Navigator.of(context).pop(option.key),
                  child: ListTile(
                    title: Text(
                      option.value,
                      style: TextStyle(
                        fontSize: 15,
                        color: option.key == value
                            ? context.colors.primary
                            : null,
                      ),
                    ),
                    trailing: option.key == value
                        ? Icon(
                            Icons.check_rounded,
                            color: context.colors.primary,
                            size: 20,
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (result != null) onSelected(result);
  }

  Future<void> _clearCache(AppController app) async {
    await app.store.clearCache();
    setState(() => _cache = app.store.cacheBytes());
  }

  String _mb(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(1);
}
