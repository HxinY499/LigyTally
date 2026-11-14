import 'package:flutter/widgets.dart';

/// 让折叠标题留在原地，新内容从标题下面长出来。
class AiExpandDown extends InheritedWidget {
  const AiExpandDown({super.key, required this.onToggle, required super.child});

  final void Function(GlobalKey anchor, VoidCallback change) onToggle;

  static AiExpandDown? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AiExpandDown>();
  }

  static void run(BuildContext context, GlobalKey anchor, VoidCallback change) {
    final scope = maybeOf(context);
    if (scope == null) {
      change();
      return;
    }
    scope.onToggle(anchor, change);
  }

  @override
  bool updateShouldNotify(AiExpandDown oldWidget) => false;
}
