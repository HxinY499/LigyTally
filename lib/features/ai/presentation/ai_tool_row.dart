import 'package:flutter/material.dart';
import 'package:flutter_ai_client/flutter_ai_client.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/app_theme.dart';
import '../application/ai_turn_format.dart';
import 'ai_downward_reveal.dart';

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
    final desc = toolCallDesc(widget.call.args);

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
        AiDownwardReveal(
          open: _open,
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: AiDetailFrame(
              child: _ToolDetails(call: widget.call, result: widget.result),
            ),
          ),
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
    AiToolCategory.category => FLucideIcons.layoutGrid,
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
        const SizedBox(height: 8),
        Text('参数', style: label),
        const SizedBox(height: 4),
        StructuredValue(value: _withoutDesc(call.args)),
        if (result != null) ...[
          const SizedBox(height: 10),
          Text(result!.isError ? '错误' : '结果', style: label),
          const SizedBox(height: 4),
          StructuredValue(value: result!.result),
        ],
      ],
    );
  }

  static Map<String, Object?> _withoutDesc(Map<String, Object?> args) {
    if (!args.containsKey('desc')) return args;
    return {
      for (final entry in args.entries)
        if (entry.key != 'desc') entry.key: entry.value,
    };
  }
}

/// 思考和工具详情共用的圆角框。内容超出后在框里滚动。
class AiDetailFrame extends StatelessWidget {
  const AiDetailFrame({
    super.key,
    required this.child,
    this.maxHeight = 220,
    this.reverse = false,
  });

  final Widget child;
  final double maxHeight;
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.lineSoft),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          reverse: reverse,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: child,
        ),
      ),
    );
  }
}

/// 把工具参数和结果按层级排开。字段本身不另做解释，只把对象和列表拆清楚。
class StructuredValue extends StatelessWidget {
  const StructuredValue({super.key, required this.value, this.depth = 0});

  final Object? value;
  final int depth;

  static const _maxDepth = 5;

  @override
  Widget build(BuildContext context) {
    if (depth >= _maxDepth) return _leaf(context, '$value');
    if (value is Map) {
      final entries = (value as Map).entries.toList();
      if (entries.isEmpty) return _leaf(context, '无');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in entries)
            _Field(name: '${entry.key}', value: entry.value, depth: depth),
        ],
      );
    }
    if (value is List) {
      final items = value as List;
      if (items.isEmpty) return _leaf(context, '无');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            StructuredValue(value: items[i], depth: depth + 1),
          ],
        ],
      );
    }
    return _leaf(context, _text(value));
  }

  static Widget _leaf(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        height: 1.4,
        color: context.colors.ink.withValues(alpha: 0.82),
      ),
    );
  }

  static String _text(Object? value) {
    if (value == null) return '无';
    if (value is String) return value.isEmpty ? '无' : value;
    return '$value';
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.name, required this.value, required this.depth});

  final String name;
  final Object? value;
  final int depth;

  bool get _nested => value is Map || value is List;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final nameStyle = TextStyle(
      fontSize: 12,
      height: 1.35,
      color: colors.inactive,
    );
    if (_nested) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: nameStyle),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: StructuredValue(value: value, depth: depth + 1),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              name,
              style: nameStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: StructuredValue._leaf(context, StructuredValue._text(value)),
          ),
        ],
      ),
    );
  }
}
