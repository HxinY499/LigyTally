import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/appearance/appearance.dart';
import 'core/media/image_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 两件预热互不依赖，并发跑，别把两次 platform channel 排成串：
  // - support 目录：分类自定义图标要靠它同步拼出文件路径，否则首帧会先
  //   渲染一次空白再补上图，滚动列表里看起来是在闪。壁纸也走这条路径。
  // - 外观偏好：整套外观必须在第一帧之前就位，否则锁定深色 / 紧凑 / 悬浮
  //   底栏的用户会看到版式分几帧重排。
  final warmUp = ImageStorage.warmUp();
  final appearance = await _loadAppearance();
  await warmUp;
  runApp(
    ProviderScope(
      overrides: [
        // 读盘失败时不加 override，controller 会退回自己异步读一次，
        // 行为与合并之前一致（只是会闪一下），而不是让 app 起不来。
        if (appearance != null)
          appearanceProvider.overrideWith(
            () => AppearanceController.seeded(appearance),
          ),
      ],
      child: const LigyTallyApp(),
    ),
  );
}

Future<AppearanceConfig?> _loadAppearance() async {
  try {
    return await loadAppearanceConfig(await SharedPreferences.getInstance());
  } on Exception {
    return null;
  }
}
