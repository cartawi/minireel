import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// macOS 专属主题。
///
/// 在 ReelTheme 基础上覆盖 macOS 原生 app 的视觉特征：
/// - 字体：SF Pro（-apple-system），通过 platform fallback 链实现
/// - 圆角：控件 6、卡片 8、容器 10（macOS 比 Material 默认更小更克制）
/// - 侧边栏 vibrancy 色：深色模式 #1C1C1E 带透明感
/// - 间距更紧凑、精确
///
/// 不修改全局 ReelTheme（手机版/TV版/Windows版共用），仅 Mac 版使用。
abstract final class MacTheme {
  /// macOS 侧边栏背景色（深色模式 vibrancy 感）。
  static const sidebarDark = Color(0xFF1C1C1E);
  static const sidebarLight = Color(0xFFE5E5EA);

  /// macOS 内容区背景（比 ReelTheme 的 #0B0D12 更偏中性灰）。
  static const contentDark = Color(0xFF1C1C1E);
  static const contentLight = Color(0xFFF5F5F7);

  /// macOS 分隔线。
  static const separatorDark = Color(0x33FFFFFF);
  static const separatorLight = Color(0x33000000);

  /// macOS 控件圆角。
  static const radiusControl = 6.0;
  static const radiusCard = 8.0;
  static const radiusContainer = 10.0;

  static ThemeData make(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final base = ReelTheme.make(brightness);

    // macOS 字体：用 .AppleSystemUI（SF Pro）在 macOS 上原生渲染，
    // 其他平台 fallback 到系统默认。
    const macFont = String.fromEnvironment(
      'MAC_FONT_FAMILY',
      defaultValue: '.AppleSystemUI',
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: macFont,
        bodyColor: base.colorScheme.onSurface,
        displayColor: base.colorScheme.onSurface,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: dark ? contentDark : contentLight,
        foregroundColor: base.colorScheme.onSurface,
      ),
      scaffoldBackgroundColor: dark ? contentDark : contentLight,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusControl),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusControl),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusControl),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.white
              : (dark ? const Color(0xFF8E8E93) : const Color(0xFFAEAEB2)),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? base.colorScheme.primary
              : (dark
                  ? const Color(0xFF3A3A3C)
                  : const Color(0xFFE9E9EB)),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: base.colorScheme.primary,
        thumbColor: Colors.white,
        inactiveTrackColor: dark
            ? const Color(0xFF48484A)
            : const Color(0xFFD1D1D6),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      ),
      dividerColor: dark ? separatorDark : separatorLight,
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusControl),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }
}

/// Mac 版上下文扩展：提供 macOS 风格的颜色访问。
extension MacColors on BuildContext {
  /// macOS 侧边栏背景色。
  Color get macSidebar =>
      dark ? MacTheme.sidebarDark : MacTheme.sidebarLight;

  /// macOS 分隔线色。
  Color get macSeparator =>
      dark ? MacTheme.separatorDark : MacTheme.separatorLight;

  /// macOS 二级背景色（用于分组容器、chip 底色）。
  Color get macSecondary =>
      dark ? const Color(0xFF2C2C2E) : const Color(0xFFEFEFF2);

  /// macOS 三级背景色（hover、选中态）。
  Color get macTertiary =>
      dark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA);

  /// macOS 选中态 accent 半透明背景。
  Color get macSelectionOverlay =>
      colors.primary.withValues(alpha: dark ? .20 : .12);
}
