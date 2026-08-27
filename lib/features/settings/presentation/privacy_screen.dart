import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../core/branding/app_brand.dart';
import '../../../core/branding/privacy_policy.dart';
import '../../../core/platform/open_url.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_widgets.dart';
import 'settings_widgets.dart';

/// 隐私与备案二级页。
///
/// 政策正文和备案号收在同一屏：两者都是上架必须公示、平时没人翻的合规信息，
/// 各占设置首页一行只会把「关于」挤成公告板。
///
/// 正文与 [kPrivacyPolicyUrl] 上的网页同源（见 core/branding/privacy_policy.dart），
/// 改一处必须同时改另一处，否则商店审核会拿两份不一致的说明来问。
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  Future<void> _openUrl(BuildContext context, String url) async {
    final ok = await openExternalUrl(url);
    if (!context.mounted) return;
    if (!ok) {
      showAppToast(context, message: '无法打开网页', level: AppToastLevel.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppTopBar(
      title: '隐私与备案',
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          sliver: SliverList.list(
            children: [
              Text(
                '更新日期：$kPrivacyPolicyUpdatedAt',
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.inactive,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 16),
              for (final section in kPrivacyPolicySections) ...[
                Text(
                  section.title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  section.body,
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.ink,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 2),
              const SectionLabel('备案'),
              SettingsCard(
                children: [
                  SettingsItem(
                    icon: FLucideIcons.badgeCheck,
                    title: 'ICP 备案号',
                    subtitle: kIcpFilingNumber,
                    showChevron: true,
                    onTap: () => _openUrl(context, kIcpQueryUrl),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => _openUrl(context, kPrivacyPolicyUrl),
                child: Text(
                  kPrivacyPolicyUrl,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colors.primary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
