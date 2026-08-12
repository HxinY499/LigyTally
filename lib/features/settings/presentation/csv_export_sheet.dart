import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ledger_date.dart';

/// 点「导出 CSV」之后先选范围，再决定要不要打开日历。
enum CsvExportPreset { month, year, all, custom }

/// 导出范围快捷菜单：本月 / 今年 / 全部，自定义再进日期区间选择。
///
/// 三个快捷项覆盖最常见的导出意图；日历留给「既不是整月也不是整年」的情况，
/// 不该让每次导出都先过一遍选日期。
Future<CsvExportPreset?> showCsvExportSheet(BuildContext context) {
  return showFSheet<CsvExportPreset>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    builder: (sheetContext) => const _CsvExportSheet(),
  );
}

class _CsvExportSheet extends StatelessWidget {
  const _CsvExportSheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final now = DateTime.now();
    return Material(
      color: colors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
              '导出 CSV',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '不含图片，可用表格软件打开',
              style: TextStyle(fontSize: 12, color: colors.muted),
            ),
            const SizedBox(height: 8),
            _Option(
              icon: FLucideIcons.calendar,
              title: '本月',
              subtitle: formatMonth(now),
              onTap: () => Navigator.pop(context, CsvExportPreset.month),
            ),
            _Option(
              icon: FLucideIcons.calendarDays,
              title: '今年',
              subtitle: '${now.year} 年',
              onTap: () => Navigator.pop(context, CsvExportPreset.year),
            ),
            _Option(
              icon: FLucideIcons.files,
              title: '全部',
              subtitle: '所有账单',
              onTap: () => Navigator.pop(context, CsvExportPreset.all),
            ),
            Divider(height: 1, thickness: 1, color: colors.lineSoft),
            _Option(
              icon: FLucideIcons.calendarRange,
              title: '自定义区间',
              subtitle: '自己选起止日期',
              showChevron: true,
              onTap: () => Navigator.pop(context, CsvExportPreset.custom),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showChevron = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colors.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 17, color: colors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: colors.ink,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.inactive,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (showChevron)
              Icon(FLucideIcons.chevronRight, size: 18, color: colors.faint),
          ],
        ),
      ),
    );
  }
}
