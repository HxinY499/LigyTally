import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/appearance/appearance_config.dart';
import 'package:ligy_tally/core/theme/app_radius.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/core/theme/hero_skin.dart';
import 'package:ligy_tally/shared/widgets/category_icon_badge.dart';

import 'surface_probe.dart';

void main() {
  group('大面走超椭圆圆角', () {
    test('卡片与弹层是超椭圆，且圆角跟着档位缩放', () {
      // 普通圆角在直边与圆弧的接点处曲率突变，半径越大越像「被剪掉的角」。
      // 卡片（18）和弹层（24）是全应用最大的两档半径，必须走连续曲率。
      for (final style in AppCornerStyle.values) {
        final radii = AppRadius(scale: style.scale);
        expect(radii.cardShape(), isA<RoundedSuperellipseBorder>());
        expect(radii.sheetTopShape, isA<RoundedSuperellipseBorder>());
        expect(
          shapeRadius(radii.cardShape())!.topLeft.x,
          AppRadius.cardBase * style.scale,
        );
      }
    });

    test('chip 档刻意没有超椭圆形状', () {
      // 10px 上肉眼分不出，而 chip 的调用点是日历格子这类一屏几十个的元素，
      // 超椭圆比 RRect 贵。这条断言是防止以后顺手补一个 chipShape。
      const radii = AppRadius();
      expect(
        radii.chip,
        lessThan(radii.block),
        reason: 'chip 应该是最小一档；它没有对应的 ShapeBorder 是刻意的',
      );
    });

    test('卡片形状默认无描边——卡片靠阴影收边', () {
      // line 是实色 #DCDCDC，压在浅灰页底上会留一道灰边；再叠阴影就是双层边。
      const radii = AppRadius();
      expect(radii.cardShape().side, BorderSide.none);
    });
  });

  group('Hero 卡卡面', () {
    test('三档卡面都只用 gradient，不用 color', () {
      // ShapeDecoration 断言 color 与 gradient 不能同时非空，而它的 lerp 是
      // 各自独立插值的。渐变档 →纯色档 的中间帧会两者都非空，直接抛异常。
      // 所以纯色/描边档把实底表达成首尾同色的退化渐变。
      for (final style in HeroCardStyle.values) {
        final hero = AppColors.resolve(
          Brightness.light,
          AppearanceConfig(heroStyle: style),
        ).hero;
        final decoration = hero.decoration(const AppRadius().cardAll);
        expect(decoration.color, isNull, reason: '$style 档还在用 color 字段');
        expect(decoration.gradient, isNotNull, reason: '$style 档没有卡面');
      }
    });

    test('三档卡面两两之间都插得动', () {
      // 上一条是原因，这条是它真正要保住的结果：外观页的样张靠
      // AnimatedContainer 在这三档之间过渡。
      const radius = BorderRadius.all(Radius.circular(18));
      final decorations = [
        for (final style in HeroCardStyle.values)
          AppColors.resolve(
            Brightness.light,
            AppearanceConfig(heroStyle: style),
          ).hero.decoration(radius),
      ];
      for (final from in decorations) {
        for (final to in decorations) {
          for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
            expect(
              () => Decoration.lerp(from, to, t),
              returnsNormally,
              reason: 't=$t 处插值抛异常',
            );
          }
        }
      }
    });

    test('只有彩色档有高光层', () {
      const radius = BorderRadius.all(Radius.circular(18));
      for (final brightness in Brightness.values) {
        for (final style in HeroCardStyle.values) {
          final hero = AppColors.resolve(
            brightness,
            AppearanceConfig(heroStyle: style),
          ).hero;
          final sheen = hero.sheen(radius);
          if (style == HeroCardStyle.outline) {
            // 卡面是白的，白色高光叠上去什么也看不见，只是白付一层渲染。
            expect(sheen, isNull, reason: '$brightness 描边档还铺了高光');
          } else {
            expect(sheen!.gradient, isA<RadialGradient>());
          }
        }
      }
    });

    test('深色下的高光比浅色弱', () {
      // 深色页面里这张卡本来就是唯一的亮块，同强度的白会让它从「有体积」
      // 变成「在发光」，把深色皮肤刻意压暗 Hero 卡那一步抵掉一半。
      double peak(Brightness brightness) =>
          AppColors.resolve(brightness).hero.sheenGradient!.colors.first.a;

      expect(peak(Brightness.dark), lessThan(peak(Brightness.light)));
      // 两套都必须「低到不能被单独看见」：这一层是打破匀速感的，不是画一道光。
      for (final brightness in Brightness.values) {
        expect(peak(brightness), lessThan(0.2));
      }
    });

    test('渐变跨度收得够紧，才不会被读成「一条渐变」', () {
      // 首尾停相对中间停各只差约 6% 亮度：体积感交给径向高光，
      // 线性渐变只负责整块面的基调。
      for (final brightness in Brightness.values) {
        final gradient = AppColors.resolve(brightness).heroGradient;
        final stops = gradient.colors;
        final middle = stops[1].computeLuminance();
        for (final edge in [stops.first, stops.last]) {
          final delta = (edge.computeLuminance() - middle).abs();
          expect(
            delta,
            lessThan(0.08),
            reason: '$brightness 下渐变跨度过大，会被读成一个「效果」',
          );
        }
      }
    });

    test('纯色档仍取渐变的中间色停', () {
      // 改中间停会让「渐变 → 纯色」两档之间跳色。
      final colors = AppColors.resolve(
        Brightness.light,
        const AppearanceConfig(heroStyle: HeroCardStyle.solid),
      );
      expect(colors.hero.color, colors.heroGradient.colors[1]);
      expect(
        flatGradientColor(
          colors.hero.decoration(const AppRadius().cardAll).gradient,
        ),
        colors.heroGradient.colors[1],
      );
    });
  });

  group('分类图标底座', () {
    testWidgets('底座是圆片，字形按固定比例缩放', (tester) async {
      // 这个组合原来在五处各写一遍且五处都不一样（40 圆 / 34 圆 / 36 圆 /
      // 34 圆角方 / 无底座），同一个分类在同一个 App 里有三种长相。
      for (final diameter in [
        CategoryIconBadge.small,
        CategoryIconBadge.large,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: CategoryIconBadge(
              iconKey: 'other',
              color: const Color(0xFFD55A46),
              background: const Color(0xFFF8E8E4),
              diameter: diameter,
            ),
          ),
        );
        final container = tester.widget<Container>(find.byType(Container));
        final decoration = container.decoration! as ShapeDecoration;
        expect(decoration.shape, isA<CircleBorder>());

        final glyph = tester.widget<Icon>(find.byType(Icon));
        // 内置图标是线性字形、四周自带留白，铺满底座会显得笨重。
        expect(glyph.size! / diameter, closeTo(18 / 34, 0.001));
      }
    });

    test('尺寸只有两档，且主内容那档更大', () {
      expect(CategoryIconBadge.large, greaterThan(CategoryIconBadge.small));
    });
  });
}
