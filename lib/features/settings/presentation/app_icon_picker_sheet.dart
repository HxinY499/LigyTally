import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../core/preferences/app_icon.dart';
import '../../../core/theme/app_theme.dart';

/// 应用图标选择底部弹窗：白面 + 顶部抓手 + 两枚大缩略卡。
///
/// 点击卡片即选中并关闭浮层，选中态用品牌色描边 + 右上角勾标提示；
/// 结构上刻意不放「取消/确定」按钮——图标是即时切换，二次确认反而累赘。
Future<AppIconStyle?> showAppIconPickerSheet(
  BuildContext context, {
  required AppIconStyle current,
}) {
  return showFSheet<AppIconStyle>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    builder: (sheetContext) => _AppIconPickerSheet(current: current),
  );
}

class _AppIconPickerSheet extends StatelessWidget {
  const _AppIconPickerSheet({required this.current});

  final AppIconStyle current;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      borderRadius: context.radii.sheetTop,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '应用图标',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '桌面刷新可能需要几秒',
              style: TextStyle(fontSize: 12, color: colors.muted),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Row(
                children: [
                  Expanded(
                    child: _IconOption(
                      asset: 'assets/branding/app-icon-dark.png',
                      selected: current == AppIconStyle.dark,
                      onTap: () => Navigator.pop(context, AppIconStyle.dark),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _IconOption(
                      asset: 'assets/branding/app-icon-light.png',
                      selected: current == AppIconStyle.light,
                      onTap: () => Navigator.pop(context, AppIconStyle.light),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个图标选项：大圆角缩略图 + 选中态描边。
///
/// 卡片自身没有文字标签——图标本身即是描述，用户看图选图，
/// 加文字反而破坏「所见即所得」。
class _IconOption extends StatelessWidget {
  const _IconOption({
    required this.asset,
    required this.selected,
    required this.onTap,
  });

  final String asset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 选中时用品牌色描 2px 边并加淡色光晕；未选中给一条浅灰描边，
    // 避免白底黑字那张卡片直接融进白色 sheet 背景。
    final colors = context.colors;
    final borderColor = selected ? colors.primary : colors.line;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: context.radii.cardAll,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? colors.primarySoft : colors.surface,
            borderRadius: context.radii.cardAll,
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
          ),
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                // 缩略图本身走圆角矩形裁剪，模拟系统桌面上的图标呈现
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: context.radii.blockAll,
                    child: Image.asset(asset, fit: BoxFit.cover),
                  ),
                ),
                if (selected)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            offset: Offset(0, 1),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        FLucideIcons.check,
                        size: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
