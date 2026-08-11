import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/media/image_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 预热 support 目录：分类自定义图标要靠它同步拼出文件路径，
  // 否则首帧会先渲染一次空白再补上图，滚动列表里看起来是在闪。
  await ImageStorage.warmUp();
  runApp(const ProviderScope(child: LigyTallyApp()));
}
