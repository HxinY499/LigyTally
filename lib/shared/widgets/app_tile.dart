import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// 应用统一列表行壳，转发到 forui 的 [FTile]。
///
/// 薄封装作为「注入锚点」：以后想统一列表行的图标间距 / 点击态，
/// 只改这一处。业务页一律用 [AppTile]，不裸用 FTile。
///
/// `with FTileMixin`：满足 [AppTileGroup]（FTileGroup）对 children
/// 的 `List<FTileMixin>` 约束，使 AppTile 能直接放进分组。
class AppTile extends StatelessWidget with FTileMixin {
  const AppTile({
    super.key,
    required this.title,
    this.prefix,
    this.subtitle,
    this.details,
    this.suffix,
    this.onPress,
    this.enabled,
  });

  final Widget title;
  final Widget? prefix;
  final Widget? subtitle;
  final Widget? details;
  final Widget? suffix;
  final VoidCallback? onPress;
  final bool? enabled;

  @override
  Widget build(BuildContext context) {
    return FTile(
      title: title,
      prefix: prefix,
      subtitle: subtitle,
      details: details,
      suffix: suffix,
      onPress: onPress,
      enabled: enabled,
    );
  }
}

/// 应用统一列表分组壳，转发到 forui 的 [FTileGroup]。
///
/// 把一组 [AppTile] 包成带分隔线的卡片式分组。
class AppTileGroup extends StatelessWidget {
  const AppTileGroup({super.key, required this.children});

  /// 子项为[AppTile]（内部 with FTileMixin，满足 FTileGroup 约束）。
  final List<AppTile> children;

  @override
  Widget build(BuildContext context) {
    return FTileGroup(children: children);
  }
}
