/// 应用级 UI 壳层的统一导出。
///
/// 业务页只 import本文件即可拿到全部 App* 壳，
/// **不要**在业务页直接 import forui 或裸用 F* 组件。
///
/// 设计意图（薄封装的价值）：现在这些壳几乎等于直接转发到 forui，
/// 但它们是「未来注入统一样式 / 逻辑的锚点」——想给所有按钮加动效、
/// 给所有输入框加校验样式、或整体换底层组件库时，只改壳层这几处，
/// 改动不会扩散到每个页面。
///
/// 保留裸用 forui 的例外（强业务语义 / 单点使用，抽壳收益低）：
/// - `FItem`（账单行，高度定制，见ledger_screen）
/// - `FBottomNavigationBar`（仅 home_shell 一处）
/// - `FScaffold` / `FTheme`（应用骨架，app.dart）
///
/// 页头：一级页 `AppPageHeader`、二级页 `AppTopBar`、页头图标 `AppHeaderAction`
/// 三者同在 `app_page_header.dart`，共用一套几何令牌（见该文件顶部常量）。
library;

export 'app_button.dart';
export 'app_card.dart';
export 'app_confirm_dialog.dart';
export 'app_page_header.dart';
export 'app_password_dialog.dart';
export 'app_picker_sheet.dart';
export 'app_switch.dart';
export 'app_text_field.dart';
export 'app_tile.dart';
export 'app_toast.dart';
export 'category_icon_view.dart';
export 'category_picker.dart';
export 'segmented_control.dart';
