/// 外观偏好的统一入口。
///
/// 业务代码一律 `import '.../core/appearance/appearance.dart'`，不要分别引
/// 三个实现文件——外观项以后还会增减，调用点只该依赖「有这么一组偏好」，
/// 不该依赖它们眼下被拆在哪几个文件里。
library;

export 'appearance_config.dart';
export 'appearance_controller.dart';
export 'appearance_preset.dart';
