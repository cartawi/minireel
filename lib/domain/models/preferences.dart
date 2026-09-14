import 'remote_key_map.dart';

enum AppAppearance { system, light, dark }

enum RailSide { right, left }

enum GestureSensitivity { low, medium, high }

const playbackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

final class Preferences {
  const Preferences({
    this.appearance = AppAppearance.system,
    this.speed = 1,
    this.quality = '自动',
    this.autoNext = true,
    this.rememberProgress = true,
    this.railSide = RailSide.right,
    this.sensitivity = GestureSensitivity.medium,
    this.largeText = false,
    this.haptics = true,
    this.gestureHintSeen = false,
    this.pauseWhenMinimized = true,
    this.desktopVolume = .75,
    this.prefetchNextEpisode = true,
    this.remoteKeyMap,
  });

  final AppAppearance appearance;
  final double speed;
  final String quality;
  final bool autoNext;
  final bool rememberProgress;
  final RailSide railSide;
  final GestureSensitivity sensitivity;
  final bool largeText;
  final bool haptics;
  final bool gestureHintSeen;
  final bool pauseWhenMinimized;
  final double desktopVolume;
  final bool prefetchNextEpisode;
  /// 遥控器按键映射。null 表示用默认映射（未自定义）。
  final RemoteKeyMap? remoteKeyMap;

  Preferences copyWith({
    AppAppearance? appearance,
    double? speed,
    String? quality,
    bool? autoNext,
    bool? rememberProgress,
    RailSide? railSide,
    GestureSensitivity? sensitivity,
    bool? largeText,
    bool? haptics,
    bool? gestureHintSeen,
    bool? pauseWhenMinimized,
    double? desktopVolume,
    bool? prefetchNextEpisode,
    RemoteKeyMap? remoteKeyMap,
  }) => Preferences(
    appearance: appearance ?? this.appearance,
    speed: speed ?? this.speed,
    quality: quality ?? this.quality,
    autoNext: autoNext ?? this.autoNext,
    rememberProgress: rememberProgress ?? this.rememberProgress,
    railSide: railSide ?? this.railSide,
    sensitivity: sensitivity ?? this.sensitivity,
    largeText: largeText ?? this.largeText,
    haptics: haptics ?? this.haptics,
    gestureHintSeen: gestureHintSeen ?? this.gestureHintSeen,
    pauseWhenMinimized: pauseWhenMinimized ?? this.pauseWhenMinimized,
    desktopVolume: desktopVolume ?? this.desktopVolume,
    prefetchNextEpisode: prefetchNextEpisode ?? this.prefetchNextEpisode,
    remoteKeyMap: remoteKeyMap ?? this.remoteKeyMap,
  );

  Map<String, dynamic> toJson() => {
    'appearance': appearance.name,
    'speed': speed,
    'quality': quality,
    'autoNext': autoNext,
    'rememberProgress': rememberProgress,
    'railSide': railSide.name,
    'sensitivity': sensitivity.name,
    'largeText': largeText,
    'haptics': haptics,
    'gestureHintSeen': gestureHintSeen,
    'pauseWhenMinimized': pauseWhenMinimized,
    'desktopVolume': desktopVolume,
    'prefetchNextEpisode': prefetchNextEpisode,
    if (remoteKeyMap != null) 'remoteKeyMap': remoteKeyMap!.toJson(),
  };

  factory Preferences.fromJson(Map<String, dynamic> json) => Preferences(
    appearance: AppAppearance.values.firstWhere(
      (value) => value.name == json['appearance'],
      orElse: () => AppAppearance.system,
    ),
    speed: playbackSpeeds.contains(json['speed'])
        ? (json['speed'] as num).toDouble()
        : 1,
    quality: json['quality'] as String? ?? '自动',
    autoNext: json['autoNext'] != false,
    rememberProgress: json['rememberProgress'] != false,
    railSide: json['railSide'] == 'left' ? RailSide.left : RailSide.right,
    sensitivity: GestureSensitivity.values.firstWhere(
      (value) => value.name == json['sensitivity'],
      orElse: () => GestureSensitivity.medium,
    ),
    largeText: json['largeText'] == true,
    haptics: json['haptics'] != false,
    gestureHintSeen: json['gestureHintSeen'] == true,
    pauseWhenMinimized: json['pauseWhenMinimized'] != false,
    desktopVolume:
        json['desktopVolume'] is num && (json['desktopVolume'] as num).isFinite
        ? (json['desktopVolume'] as num).toDouble().clamp(0, 1)
        : .75,
    prefetchNextEpisode: json['prefetchNextEpisode'] != false,
    remoteKeyMap: json['remoteKeyMap'] is Map
        ? RemoteKeyMap.fromJson(json['remoteKeyMap'] as Map<String, dynamic>)
        : null,
  );
}
