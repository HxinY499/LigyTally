import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_ai_client/flutter_ai_client.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../application/ai_turn_format.dart';

/// 一次工具调用：分类图标 + 一句说明。点开才看参数和结果，外面不套方框。
class AiToolRow extends StatefulWidget {
  const AiToolRow({super.key, required this.call, this.result});

  final ToolCallPart call;
  final ToolResultPart? result;

  @override
  State<AiToolRow> createState() => _AiToolRowState();
}

class _AiToolRowState extends State<AiToolRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final failed =
        (widget.result?.isError ?? false) ||
        widget.call.state == ToolCallState.error;
    final running = widget.result == null && !failed;
    final color = failed
        ? colors.danger
        : running
        ? colors.primary
        : colors.muted;
    final desc = describeToolCall(widget.call.toolName, widget.call.args);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: desc,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(_icon(widget.call.toolName), size: 15, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: colors.ink.withValues(alpha: 0.82),
                      ),
                    ),
                  ),
                  if (running) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: context.motion(const Duration(milliseconds: 180)),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(left: 23, bottom: 4),
                  child: _ToolDetails(call: widget.call, result: widget.result),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  static IconData _icon(String toolName) => switch (toolCategory(toolName)) {
    AiToolCategory.stats => FLucideIcons.chartColumn,
    AiToolCategory.search => FLucideIcons.search,
    AiToolCategory.write => FLucideIcons.receipt,
    AiToolCategory.edit => FLucideIcons.pencil,
    AiToolCategory.remove => FLucideIcons.trash2,
    AiToolCategory.other => FLucideIcons.sparkles,
  };
}

class _ToolDetails extends StatelessWidget {
  const _ToolDetails({required this.call, required this.result});

  final ToolCallPart call;
  final ToolResultPart? result;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = TextStyle(
      fontSize: 12,
      height: 1.45,
      color: colors.muted,
      fontFamily: 'monospace',
    );
    final label = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: colors.inactive,
      height: 1.4,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(call.toolName, style: label),
        const SizedBox(height: 6),
        Text('参数', style: label),
        Text(_pretty(call.args), style: style),
        if (result != null) ...[
          const SizedBox(height: 8),
          Text(result!.isError ? '错误' : '结果', style: label),
          Text(_pretty(result!.result), style: style),
        ],
      ],
    );
  }

  static String _pretty(Object? value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } on Object {
      return '$value';
    }
  }
}
