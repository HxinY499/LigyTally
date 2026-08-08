# Ligy Tally

Android-first 的本地轻量记账应用，使用 Flutter、Riverpod、Drift 和 SQLite 构建。

## 当前能力

- 收入、支出新增、编辑和删除
- 月度明细、类型筛选和备注/分类搜索
- 日、周、月、年和自定义时间范围统计
- 收支趋势和分类排行
- 通用两级分类、自定义分类、删除与停用
- 分类配置 JSON 导入和导出
- 每笔账单最多三张本地图片
- 包含图片的完整备份、可选密码和覆盖恢复
- 纯本地存储，无账号、无服务端

## 运行

```bash
flutter pub get
dart run build_runner build
flutter emulators --launch Ligy_Pixel_8_API_36
flutter run -d emulator-5554
```

## 检查

```bash
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

Debug APK 输出位置：

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## 数据

账单和分类保存在应用私有 SQLite 数据库中，图片保存在应用私有 `media` 目录。备份文件扩展名为 `.ligytally`，迁移采用全量覆盖恢复，不提供多设备同步或数据合并。

## 已知事项

当前 `flutter_image_compress_common` 和 `share_plus` 仍会触发 Flutter 关于旧 Kotlin Gradle Plugin 接入方式的前瞻警告。当前 Flutter 3.44.9 / AGP 9 构建正常，后续升级 Flutter 前应先检查这两个插件的兼容版本。
