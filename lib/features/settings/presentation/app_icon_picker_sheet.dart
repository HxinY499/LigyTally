import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../core/preferences/app_icon.dart';
import '../../../core/theme/app_theme.dart';

/// 应用图标选择底部弹窗：白面 + 顶部抓手 + 四枚缩略卡（2×2）。
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
              // 四款排成 2×2。不用 GridView：项数固定且很少，
              // Row/Column 组合更轻，也不引入多余的滚动容器。
              child: Column(
                children: [
                  for (var row = 0; row < 2; row++) ...[
                    if (row > 0) const SizedBox(height: 14),
                    Row(
                      children: [
                        for (var col = 0; col < 2; col++) ...[
                          if (col > 0) const SizedBox(width: 14),
                          Expanded(
                            child: _buildOption(
                              context,
                              AppIconStyle.values[row * 2 + col],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(BuildContext context, AppIconStyle style) => _IconOption(
    style: style,
    selected: current == style,
    onTap: () => Navigator.pop(context, style),
  );
}

/// 单个图标选项：大圆角缩略图 + 中文名 + 选中态描边。
///
/// 只有两款时靠图本身足以分辨；四款里「素白」与「浅蓝」缩略图的差异仅在
/// 标记颜色，小尺寸下不易区分，所以补一行文字标签。
class _IconOption extends StatelessWidget {
  const _IconOption({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final AppIconStyle style;
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  children: [
                    // 缩略图本身走圆角矩形裁剪，模拟系统桌面上的图标呈现
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: context.radii.blockAll,
                        child: Image.asset(style.asset, fit: BoxFit.cover),
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
              const SizedBox(height: 8),
              Text(
                style.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? colors.primary : colors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
