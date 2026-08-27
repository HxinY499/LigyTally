import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/appearance/appearance.dart';
import 'package:ligy_tally/core/backup/backup_service.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/media/image_storage.dart';
import 'package:ligy_tally/core/theme/app_accent.dart';
import 'package:ligy_tally/core/theme/app_density.dart';
import 'package:ligy_tally/core/theme/app_motion.dart';
import 'package:ligy_tally/core/theme/app_radius.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/core/theme/hero_skin.dart';
import 'package:ligy_tally/core/theme/sign_palette.dart';

/// 一套「每一项都不是默认值」的配置，用来验往返不丢字段。
///
/// 逐项写死而不是随机生成：加了新字段但忘了接进编解码时，这里会因为
/// 少改一行而露出来；随机生成反而会把新字段悄悄带过去。
const _loaded = AppearanceConfig(
  themeMode: AppThemeMode.dark,
  accent: AccentChoice.custom(hue: 217.5, saturation: 0.625),
  corner: AppCornerStyle.extraRound,
  density: AppDensityLevel.compact,
  motion: MotionLevel.off,
  trueBlack: true,
  signPalette: SignPalette.coolExpense,
  tabularFigures: false,
  moneyGrouped: false,
  heroStyle: HeroCardStyle.outline,
  navBarStyle: NavBarStyle.floating,
  wallpaper: WallpaperConfig(
    enabled: true,
    opacity: 0.35,
    blur: 8,
    stamp: 1755000000000,
  ),
  transactionImageStyle: TransactionImageStyle.backdrop,
  backdropBlur: 12,
  categoryPickerLayout: CategoryPickerLayout.list,
);

void main() {
  group('外观配置的编解码', () {
    test('全非默认值往返一字不丢', () {
      expect(AppearanceConfig.decode(_loaded.encode()), _loaded);
    });

    test('默认值往返也稳定', () {
      expect(
        AppearanceConfig.decode(AppearanceConfig.initial.encode()),
        AppearanceConfig.initial,
      );
    });

    test('认不出前缀就整串作废，回落默认值', () {
      for (final raw in [
        null,
        '',
        'hello',
        'LT2~dark',
        '{"themeMode":"dark"}',
      ]) {
        expect(
          AppearanceConfig.decode(raw),
          AppearanceConfig.initial,
          reason: '$raw',
        );
      }
    });

    test('串被截断时，读不到的字段各自回落，已读到的保留', () {
      // 偏好文件和备份包都是外部输入。一个字段被截断不该让用户丢掉其余十几项。
      final config = AppearanceConfig.decode('LT1~dark~purple');
      expect(config.themeMode, AppThemeMode.dark);
      expect(config.accent, const AccentChoice.preset(AppAccent.purple));
      expect(config.corner, AppCornerStyle.fallback);
      expect(config.density, AppDensityLevel.fallback);
      expect(config.tabularFigures, isTrue, reason: '布尔项该回落到自己的默认值');
      expect(config.wallpaper, WallpaperConfig.none);
    });

    test('单个字段是脏数据时只影响它自己', () {
      final raw = _loaded
          .encode()
          .replaceAll('extraRound', 'bubbly')
          .replaceAll('compact', 'microscopic');
      final config = AppearanceConfig.decode(raw);
      expect(config.corner, AppCornerStyle.fallback);
      expect(config.density, AppDensityLevel.fallback);
      // 其余字段照旧。
      expect(config.themeMode, AppThemeMode.dark);
      expect(config.heroStyle, HeroCardStyle.outline);
    });

    test('末尾多出没见过的字段时照旧解码——往后加字段只能追加', () {
      // 这条锁住向前兼容：新版本在末尾追加字段后，老版本装回去仍要能读。
      final config = AppearanceConfig.decode('${_loaded.encode()}~future~42');
      expect(config, _loaded);
    });

    test('越界的数值被夹回可用区间', () {
      final raw = AppearanceConfig.decode(
        'LT1~system~blue~standard~standard~full~0~warmExpense~1~1'
        '~gradient~docked~backdrop~9999~list~1~9~999~0',
      );
      expect(raw.backdropBlur, kBackdropBlurMax);
      expect(raw.wallpaper.opacity, kWallpaperOpacityMax);
      expect(raw.wallpaper.blur, kWallpaperBlurMax);
    });
  });

  group('外观令牌接进主题', () {
    test('动效关闭档把每个时长压成零，调用点不需要判断', () {
      const off = AppMotion(scale: 0);
      expect(off(const Duration(milliseconds: 380)), Duration.zero);
      expect(off.isOff, isTrue);
      const reduced = AppMotion(scale: 0.55);
      expect(
        reduced(const Duration(milliseconds: 200)),
        const Duration(milliseconds: 110),
      );
      expect(
        const AppMotion()(const Duration(seconds: 1)),
        const Duration(seconds: 1),
      );
    });

    test('三档动效都挂进 Material 主题，关闭档还换掉页面转场', () {
      for (final level in MotionLevel.values) {
        final theme = buildMaterialTheme(
          Brightness.light,
          AppearanceConfig(motion: level),
        );
        expect(theme.extension<AppMotion>()?.scale, level.scale);
      }
      // 完整档沿用平台默认转场（pageTransitions 为 null，copyWith 不覆盖）。
      expect(MotionLevel.full.pageTransitions, isNull);
      expect(MotionLevel.off.pageTransitions, isNotNull);
    });

    test('三档密度都挂进 Material 主题', () {
      for (final level in AppDensityLevel.values) {
        final theme = buildMaterialTheme(
          Brightness.light,
          AppearanceConfig(density: level),
        );
        final density = theme.extension<AppDensity>()!;
        expect(density.textScale, level.textScale);
        expect(density.spaceScale, level.spaceScale);
      }
    });

    test('等宽数字挂在 textTheme 上，才能被几十处金额 Text 继承到', () {
      // 逐处给金额加 fontFeatures 要改二十多个文件，而且下一个新增的一定会忘。
      // Text 的 style 会与最近的 DefaultTextStyle 做 merge，而 merge 对
      // fontFeatures 的处理是「自己没给就沿用祖先的」，所以挂在这里就够。
      final on = buildMaterialTheme(
        Brightness.light,
        const AppearanceConfig(tabularFigures: true),
      );
      expect(
        on.textTheme.bodyMedium?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      final off = buildMaterialTheme(
        Brightness.light,
        const AppearanceConfig(tabularFigures: false),
      );
      expect(off.textTheme.bodyMedium?.fontFeatures, isNull);
    });

    test('壁纸模式下页底让位，但 canvasBase 仍是实色', () {
      final colors = AppColors.resolve(
        Brightness.light,
        const AppearanceConfig(wallpaper: WallpaperConfig(enabled: true)),
      );
      expect(colors.canvas, Colors.transparent);
      // 这一条就是把 canvas 拆成两支的全部理由：深色 FAB 上的加号、
      // 强调按钮上的文字都拿它当前景色，透明会让字直接消失。
      expect(colors.canvasBase, AppColors.light.canvasBase);
      expect(colors.canvasBase.a, 1);
    });

    test('Hero 卡三档：彩色档字是白的，描边档换成墨色且卡面不再是渐变', () {
      for (final style in HeroCardStyle.values) {
        final hero = AppColors.resolve(
          Brightness.light,
          AppearanceConfig(heroStyle: style),
        ).hero;
        if (style == HeroCardStyle.outline) {
          expect(hero.gradient, isNull);
          expect(hero.side, isNot(BorderSide.none));
          expect(hero.foreground, AppColors.light.ink);
        } else {
          expect(hero.foreground, Colors.white);
          expect(hero.isTinted, isTrue);
        }
      }
      // 纯色档取渐变的中间色停，不是 primary——primary 是为「压得住白字」
      // 挑的，铺满一张大卡会亮得刺眼。
      final solid = AppColors.resolve(
        Brightness.light,
        const AppearanceConfig(heroStyle: HeroCardStyle.solid),
      );
      expect(solid.hero.color, solid.heroGradient.colors[1]);
    });
  });

  group('外观进备份', () {
    Future<
      ({
        BackupService source,
        BackupService target,
        AppDatabase targetDb,
        File zip,
      })
    >
    setUpPair() async {
      final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(sourceDb.close);
      final sourceDir = await Directory.systemTemp.createTemp('ligy_ap_src');
      addTearDown(() => sourceDir.delete(recursive: true));
      final targetDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(targetDb.close);
      final targetDir = await Directory.systemTemp.createTemp('ligy_ap_dst');
      addTearDown(() => targetDir.delete(recursive: true));
      return (
        source: BackupService(sourceDb, ImageStorage.atRoot(sourceDir.path)),
        target: BackupService(targetDb, ImageStorage.atRoot(targetDir.path)),
        targetDb: targetDb,
        zip: File('${sourceDir.path}/backup.ligytally'),
      );
    }

    test('整套外观跟着备份走，恢复后原样回来', () async {
      // 用户花时间调出来的一套外观，换机恢复后账单全在、外观全丢，
      // 这件事对「这是我的 app」的伤害比少几个开关大得多。
      final pair = await setUpPair();
      // 壁纸文件不在，这里只验配置本身跟着走。
      final exported = _loaded.copyWith(wallpaper: WallpaperConfig.none);
      await pair.source.writeBackupTo(pair.zip, appearance: exported);

      final restored = await pair.target.restore(pair.zip.path);
      expect(restored, exported);
    });

    test('不带外观的包恢复后返回 null，调用方保持当前外观不动', () async {
      final pair = await setUpPair();
      await pair.source.writeBackupTo(pair.zip);
      expect(await pair.target.restore(pair.zip.path), isNull);
    });

    test('壁纸图片也进包，恢复后文件原样落回', () async {
      final sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(sourceDb.close);
      final sourceDir = await Directory.systemTemp.createTemp('ligy_wp_src');
      addTearDown(() => sourceDir.delete(recursive: true));
      final sourceStorage = ImageStorage.atRoot(sourceDir.path);
      final bytes = List<int>.generate(64, (i) => i * 3 % 256);
      final origin = await sourceStorage.resolve(kWallpaperRelativePath);
      await origin.parent.create(recursive: true);
      await origin.writeAsBytes(bytes, flush: true);

      final zip = File('${sourceDir.path}/backup.ligytally');
      await BackupService(sourceDb, sourceStorage).writeBackupTo(
        zip,
        appearance: const AppearanceConfig(
          wallpaper: WallpaperConfig(enabled: true, stamp: 9),
        ),
      );

      final targetDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(targetDb.close);
      final targetDir = await Directory.systemTemp.createTemp('ligy_wp_dst');
      addTearDown(() => targetDir.delete(recursive: true));
      final targetStorage = ImageStorage.atRoot(targetDir.path);

      final restored = await BackupService(
        targetDb,
        targetStorage,
      ).restore(zip.path);
      expect(restored?.wallpaper.enabled, isTrue);
      final landed = await targetStorage.resolve(kWallpaperRelativePath);
      expect(await landed.exists(), isTrue, reason: '恢复后壁纸文件必须存在');
      expect(await landed.readAsBytes(), bytes);
    });

    test('说有壁纸但文件不在时照旧导出，不让整次备份失败', () async {
      // 用户可能在系统文件管理器里把壁纸删了。为一张装饰图让整次备份失败，
      // 代价远大于收益——账单图片才必须一字不差。
      final pair = await setUpPair();
      await pair.source.writeBackupTo(
        pair.zip,
        appearance: const AppearanceConfig(
          wallpaper: WallpaperConfig(enabled: true),
        ),
      );
      final restored = await pair.target.restore(pair.zip.path);
      expect(restored?.wallpaper.enabled, isTrue);
    });
  });
}
