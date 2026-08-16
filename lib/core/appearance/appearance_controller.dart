import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_accent.dart';
import '../theme/app_density.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/hero_skin.dart';
import '../theme/sign_palette.dart';
import 'appearance_config.dart';
import 'appearance_preset.dart';

/// 整套外观配置的落盘 key。
const appearancePrefsKey = 'appearance_config';

/// 合并之前每一项各占一个 key 的旧格式。
///
/// 只在新 key 不存在时读一次（首次升级），读完把整套写进新 key 并**删掉**旧 key。
/// 留着旧 key 会让同一个偏好在盘上有两份，下一个改这块的人必然要问
/// 「到底哪份是准的」；而删掉的代价只是「装回旧版本会看到默认外观」，
/// 账单数据一个字节都不受影响。
const _legacyThemeMode = 'app_theme_mode';
const _legacyAccent = 'app_accent';
const _legacyCorner = 'app_corner_style';
const _legacyImageStyle = 'transaction_image_style';
const _legacyBackdropBlur = 'backdrop_blur_sigma';
const _legacyPickerLayout = 'category_picker_layout';
const _legacyMoneyGrouped = 'money_grouped';

/// 滑杆落盘的攒批时长。
///
/// 拖一次色相条 / 浓度条会产生上百个中间值，每个都过一趟 platform channel
/// 纯属拿磁盘当画布。值本身立刻生效，只有写盘延后。
const _persistDebounce = Duration(milliseconds: 400);

/// 全部外观偏好的唯一持有者。
///
/// ## 读盘发生在 `runApp` 之前
///
/// 与旧的九个 controller 不同，这里**不**做「先给默认值、异步读盘再覆盖」。
/// `main.dart` 会先 await 一次读盘，把结果通过 [seeded] 注入，所以第一帧
/// 就是终态。代价是启动多等一次 SharedPreferences 初始化（与已有的
/// `ImageStorage.warmUp()` 同量级），换掉的是「锁定深色 + 紧凑 + 悬浮底栏
/// 的用户看到版式分几帧重排」。
///
/// 没有注入种子时（测试、以及万一读盘失败）退回异步读盘，行为与旧版一致，
/// 用 [ready] 可以等它读完。
class AppearanceController extends Notifier<AppearanceConfig> {
  AppearanceController() : _seed = null;

  /// 用已经读好的配置构造，跳过异步读盘。见 `main.dart`。
  AppearanceController.seeded(AppearanceConfig seed) : _seed = seed;

  final AppearanceConfig? _seed;

  Timer? _saveTimer;

  /// 攒批中还没落盘的那份配置。
  ///
  /// 单独存一份而不是回头读 `state`：provider 销毁之后 `state` 就读不到了，
  /// 而销毁正是最需要把它冲刷出去的时刻。
  AppearanceConfig? _pending;

  final Completer<void> _ready = Completer<void>();

  /// 读盘完成。注入种子时立刻完成。
  Future<void> get ready => _ready.future;

  @override
  AppearanceConfig build() {
    // 销毁时把攒批中的写**冲刷掉**而不是丢掉：拖完滑杆立刻退出的话，
    // 取消定时器等于把用户刚调的值扔了。
    ref.onDispose(_flush);
    final seed = _seed;
    if (seed != null) {
      if (!_ready.isCompleted) _ready.complete();
      return seed;
    }
    _load();
    return AppearanceConfig.initial;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loaded = await loadAppearanceConfig(prefs);
      if (loaded != state) state = loaded;
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  // ------------------------------------------------------------------ 逐项设置
  //
  // 每个 setter 都返回落盘的 Future。UI 侧可以当成 `void Function(T)` 直接
  // 塞给 `onChanged`（Dart 允许返回值被丢弃），需要确认「真的写进去了」的
  // 场合（测试、导出备份前）则可以 await。

  Future<void> setThemeMode(AppThemeMode mode) =>
      _apply(state.copyWith(themeMode: mode));

  Future<void> setCorner(AppCornerStyle corner) =>
      _apply(state.copyWith(corner: corner));

  Future<void> setDensity(AppDensityLevel density) =>
      _apply(state.copyWith(density: density));

  Future<void> setMotion(MotionLevel motion) =>
      _apply(state.copyWith(motion: motion));

  Future<void> setTrueBlack(bool value) =>
      _apply(state.copyWith(trueBlack: value));

  Future<void> setSignPalette(SignPalette palette) =>
      _apply(state.copyWith(signPalette: palette));

  Future<void> setTabularFigures(bool value) =>
      _apply(state.copyWith(tabularFigures: value));

  Future<void> setMoneyGrouped(bool value) =>
      _apply(state.copyWith(moneyGrouped: value));

  Future<void> setHeroStyle(HeroCardStyle style) =>
      _apply(state.copyWith(heroStyle: style));

  Future<void> setNavBarStyle(NavBarStyle style) =>
      _apply(state.copyWith(navBarStyle: style));

  Future<void> setTransactionImageStyle(TransactionImageStyle style) =>
      _apply(state.copyWith(transactionImageStyle: style));

  Future<void> setCategoryPickerLayout(CategoryPickerLayout layout) =>
      _apply(state.copyWith(categoryPickerLayout: layout));

  /// 只改内存里的强调色，不落盘。
  ///
  /// 给色相 / 浓淡滑杆的拖动过程用；松手时调 [setAccent] 落最终值。
  void previewAccent(AccentChoice accent) {
    if (accent != state.accent) state = state.copyWith(accent: accent);
  }

  /// 不能在这里对相等提前返回：滑杆松手时 state 已被 [previewAccent] 改成
  /// 最终值了，比一次就直接不落盘。
  Future<void> setAccent(AccentChoice accent) {
    state = state.copyWith(accent: accent);
    return _persistNow(state);
  }

  /// 记账页背板模糊。滑杆边拖边改，落盘攒批。
  Future<void> setBackdropBlur(double value) {
    final next = value.clamp(kBackdropBlurMin, kBackdropBlurMax).toDouble();
    return _apply(state.copyWith(backdropBlur: next), debounce: true);
  }

  // ------------------------------------------------------------------ 壁纸

  /// 记下「已经存好一张新壁纸」。文件写入由调用方（`ImageStorage`）负责，
  /// 这里只推进时间戳，让图片缓存把同名旧文件丢掉。
  Future<void> enableWallpaper({required int stamp}) => _apply(
    state.copyWith(
      wallpaper: state.wallpaper.copyWith(enabled: true, stamp: stamp),
    ),
  );

  /// 关掉壁纸但保留浓度 / 模糊：用户再打开时不用重新调。
  Future<void> disableWallpaper() => _apply(
    state.copyWith(wallpaper: state.wallpaper.copyWith(enabled: false)),
  );

  Future<void> setWallpaperOpacity(double value) {
    final next = value
        .clamp(kWallpaperOpacityMin, kWallpaperOpacityMax)
        .toDouble();
    return _apply(
      state.copyWith(wallpaper: state.wallpaper.copyWith(opacity: next)),
      debounce: true,
    );
  }

  Future<void> setWallpaperBlur(double value) {
    final next = value.clamp(kWallpaperBlurMin, kWallpaperBlurMax).toDouble();
    return _apply(
      state.copyWith(wallpaper: state.wallpaper.copyWith(blur: next)),
      debounce: true,
    );
  }

  // ------------------------------------------------------------------ 成套操作

  Future<void> applyPreset(AppearancePreset preset) =>
      _apply(preset.applyTo(state));

  /// 当前配置的分享码（不含壁纸，见 [AppearanceConfig.encode]）。
  String exportCode() => state.encode(includeWallpaper: false);

  /// 导入一段主题码。返回是否认得出这串东西。
  ///
  /// 认出来之后**保留本机壁纸**：主题码里没有壁纸（那是本机的一个图片文件），
  /// 若按解码结果原样套用，导入别人的配色会顺手把用户自己的壁纸关掉。
  bool importCode(String raw) {
    final text = raw.trim();
    if (!AppearanceConfig.looksLikeCode(text)) return false;
    final decoded = AppearanceConfig.decode(text);
    // 落盘不等：调用方要的是「认不认得出这串东西」这个同步答案，
    // 好决定是关闭浮层还是就地报错。
    _apply(decoded.copyWith(wallpaper: state.wallpaper));
    return true;
  }

  /// 恢复备份时把包里带的外观整套装回来。
  ///
  /// 与 [importCode] 相反，这里**要**接受壁纸：备份包里连壁纸图片一起打包了，
  /// 恢复的承诺是「回到导出那天的样子」。
  Future<void> restoreFromConfig(AppearanceConfig config) => _apply(config);

  // ------------------------------------------------------------------ 内部

  Future<void> _apply(AppearanceConfig next, {bool debounce = false}) {
    if (next == state) return Future.value();
    state = next;
    if (debounce) {
      _saveTimer?.cancel();
      _pending = next;
      _saveTimer = Timer(_persistDebounce, _flush);
      return Future.value();
    }
    return _persistNow(next);
  }

  Future<void> _persistNow(AppearanceConfig next) {
    _saveTimer?.cancel();
    _saveTimer = null;
    _pending = null;
    return _write(next);
  }

  /// 立刻写掉攒批中的那一份（定时器到点、或 provider 被销毁）。
  void _flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final pending = _pending;
    _pending = null;
    if (pending != null) _write(pending);
  }

  Future<void> _write(AppearanceConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(appearancePrefsKey, config.encode());
  }
}

/// 从偏好里读出整套外观，必要时做一次旧格式迁移。
///
/// 独立成顶层函数是为了 `main.dart` 能在 `runApp` 之前直接调用它，
/// 不必先建一个 ProviderContainer。
Future<AppearanceConfig> loadAppearanceConfig(SharedPreferences prefs) async {
  final raw = prefs.getString(appearancePrefsKey);
  if (raw != null) return AppearanceConfig.decode(raw);
  final migrated = _migrateLegacy(prefs);
  await prefs.setString(appearancePrefsKey, migrated.encode());
  await _clearLegacy(prefs);
  return migrated;
}

/// 把旧的七个 key 拼成一套配置。缺哪个就用哪个的默认值——
/// 老用户没设过的项本来就该是默认。
AppearanceConfig _migrateLegacy(SharedPreferences prefs) {
  final blur = prefs.getDouble(_legacyBackdropBlur);
  return AppearanceConfig(
    themeMode: AppThemeMode.decode(prefs.getString(_legacyThemeMode)),
    accent: AccentChoice.decode(prefs.getString(_legacyAccent)),
    corner: AppCornerStyle.decode(prefs.getString(_legacyCorner)),
    transactionImageStyle: TransactionImageStyle.decode(
      prefs.getString(_legacyImageStyle),
    ),
    backdropBlur: blur == null
        ? kBackdropBlurDefault
        : blur.clamp(kBackdropBlurMin, kBackdropBlurMax).toDouble(),
    categoryPickerLayout: CategoryPickerLayout.decode(
      prefs.getString(_legacyPickerLayout),
    ),
    moneyGrouped: prefs.getBool(_legacyMoneyGrouped) ?? true,
  );
}

Future<void> _clearLegacy(SharedPreferences prefs) async {
  for (final key in const [
    _legacyThemeMode,
    _legacyAccent,
    _legacyCorner,
    _legacyImageStyle,
    _legacyBackdropBlur,
    _legacyPickerLayout,
    _legacyMoneyGrouped,
  ]) {
    await prefs.remove(key);
  }
}

final appearanceProvider =
    NotifierProvider<AppearanceController, AppearanceConfig>(
      AppearanceController.new,
    );

/// ── 单项选择器 ────────────────────────────────────────────────
///
/// 每一项一个 `Provider`，而不是让页面直接 watch 整个 [appearanceProvider]。
/// Riverpod 的 `Provider` 会用 `==` 比较结果，值没变就不通知——所以改一个
/// 圆角档位不会让明细页那几十行账单跟着重建。这比合并之前的九个
/// `NotifierProvider` 粒度更细，不是更粗。
///
/// 名字与合并之前保持一致，调用点的 `ref.watch(...)` 不用改；
/// 只有写入方从 `xxxProvider.notifier` 换成 [appearanceProvider]`.notifier`。
final appThemeModeProvider = Provider<AppThemeMode>(
  (ref) => ref.watch(appearanceProvider).themeMode,
);

final appAccentProvider = Provider<AccentChoice>(
  (ref) => ref.watch(appearanceProvider).accent,
);

final appCornerStyleProvider = Provider<AppCornerStyle>(
  (ref) => ref.watch(appearanceProvider).corner,
);

final appDensityProvider = Provider<AppDensityLevel>(
  (ref) => ref.watch(appearanceProvider).density,
);

final appMotionLevelProvider = Provider<MotionLevel>(
  (ref) => ref.watch(appearanceProvider).motion,
);

final moneyGroupedProvider = Provider<bool>(
  (ref) => ref.watch(appearanceProvider).moneyGrouped,
);

final transactionImageStyleProvider = Provider<TransactionImageStyle>(
  (ref) => ref.watch(appearanceProvider).transactionImageStyle,
);

final backdropBlurProvider = Provider<double>(
  (ref) => ref.watch(appearanceProvider).backdropBlur,
);

final categoryPickerLayoutProvider = Provider<CategoryPickerLayout>(
  (ref) => ref.watch(appearanceProvider).categoryPickerLayout,
);

final navBarStyleProvider = Provider<NavBarStyle>(
  (ref) => ref.watch(appearanceProvider).navBarStyle,
);

final wallpaperProvider = Provider<WallpaperConfig>(
  (ref) => ref.watch(appearanceProvider).wallpaper,
);
