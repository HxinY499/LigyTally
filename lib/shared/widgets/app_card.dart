import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// 应用统一卡片壳，转发到 forui 的 [FCard]。
///
/// 薄封装作为「注入锚点」：以后想统一调卡片圆角 / 阴影 / 内边距，
/// 只改这一处。业务页一律用 [AppCard]，不裸用 FCard。
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FCard(child: child);
  }
}
