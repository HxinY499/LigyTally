import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_elements/flutter_ai_elements.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/app_theme.dart';
import '../application/ai_turn_format.dart';
import 'ai_chart_card.dart';
import 'ai_downward_reveal.dart';
import 'ai_tool_row.dart';
import 'ai_transaction_cards.dart';
import 'ai_turn_label.dart';

/// 一轮助手回复。
///
/// 进行中时过程摊开，但每段思考结束后自己收起。整轮结束后过程和工具再收成一行。
/// 点开那一行时，思考仍然是收起的。
class AiTurnBody extends StatelessWidget {
  const AiTurnBody({
    super.key,
    required this.turn,
    required this.results,
    required this.working,
    this.fixedMs,
    this.startedAt,
  });

  final List<AiMessage> turn;
  final Map<String, ToolResultPart> results;
  final bool working;
  final int? fixedMs;
  final DateTime? startedAt;

  @override
  Widget build(BuildContext context) {
    final content = splitAssistantTurn(turn);
    // <bills> 标记出现在正文哪儿，卡片就渲染在哪儿。
    final blocks = content.answer == null
        ? const <AiAnswerBlock>[]
        : splitAnswerBlocks(content.answer!.text);
    final copyText = content.answer?.text.trim() ?? '';
    final streaming =
        working &&
        content.answerMessage?.status == AiMessageStatus.streaming;
    final theme = AiThemeExtension.of(context);
    return DefaultTextStyle.merge(
      style: theme.textStyle.copyWith(color: theme.assistantTextColor),
      child: Padding(
        padding: EdgeInsets.only(bottom: theme.messageSpacing),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (fixedMs != null || startedAt != null)
              AiTurnLabel(fixedMs: fixedMs, startedAt: startedAt),
            if (content.process.isNotEmpty)
              _WorkProcess(
                pieces: content.process,
                results: results,
                working: working,
                hasAnswer: content.answer != null,
              ),
            for (final block in blocks)
              switch (block) {
                AiAnswerTextBlock(:final text) => _AnswerText(
                  text: text,
                  streaming: streaming,
                ),
                AiAnswerBillsBlock(:final ids) => Padding(
                  key: ValueKey('bills-${ids.join(',')}'),
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: AiTransactionCards(ids: ids),
                ),
                AiAnswerChartBlock(:final spec) => Padding(
                  key: ValueKey('chart-${spec.identityKey}'),
                  padding: const EdgeInsets.only(top: 6, bottom: 10),
                  child: AiChartCard(spec: spec),
                ),
              },
            if (!working && copyText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [_CopyAnswerButton(text: copyText)],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkProcess extends StatefulWidget {
  const _WorkProcess({
    required this.pieces,
    required this.results,
    required this.working,
    required this.hasAnswer,
  });

  final List<TurnPiece> pieces;
  final Map<String, ToolResultPart> results;
  final bool working;
  final bool hasAnswer;

  @override
  State<_WorkProcess> createState() => _WorkProcessState();
}

class _WorkProcessState extends State<_WorkProcess> {
  late bool _open = widget.working;
  bool _pinned = false;

  @override
  void didUpdateWidget(_WorkProcess oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.working) {
      _open = true;
      return;
    }
    if (oldWidget.working && !_pinned) _open = false;
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.pieces.length; i++)
          _piece(widget.pieces[i], i),
      ],
    );
    if (widget.working || processStaysOpen(widget.pieces)) return body;

    final colors = context.colors;
    final muted = colors.muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: workProcessLabel(widget.pieces),
          child: InkWell(
            onTap: () => setState(() {
              _pinned = true;
              _open = !_open;
            }),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FLucideIcons.listTree, size: 15, color: muted),
                  const SizedBox(width: 6),
                  Text(
                    workProcessLabel(widget.pieces),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: muted,
                      height: 1.3,
                    ),
                  ),
                  Icon(
                    _open ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
                    size: 14,
                    color: muted,
                  ),
                ],
              ),
            ),
          ),
        ),
        AiDownwardReveal(
          open: _open,
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: body,
          ),
        ),
      ],
    );
  }

  Widget _piece(TurnPiece piece, int index) {
    final part = piece.part;
    if (part is ReasoningPart) {
      final last = index == widget.pieces.length - 1;
      final live =
          widget.working &&
          !widget.hasAnswer &&
          last &&
          piece.message.status == AiMessageStatus.streaming;
      return _ThinkingBlock(
        text: part.text.trim(),
        live: live,
        stayOpen: processStaysOpen(widget.pieces),
      );
    }
    if (part is ToolCallPart) {
      return AiToolRow(call: part, result: widget.results[part.toolCallId]);
    }
    if (part is TextPart) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: const MarkdownTextRenderer().render(
          part.text,
          isStreaming: false,
        ),
      );
    }
    if (part is FilePart) return AiAttachment(file: part);
    return const SizedBox.shrink();
  }
}

class _ThinkingBlock extends StatefulWidget {
  const _ThinkingBlock({
    required this.text,
    required this.live,
    required this.stayOpen,
  });

  final String text;
  final bool live;

  /// 整轮里只有这一段思考时，结束后仍然摊开。
  final bool stayOpen;

  @override
  State<_ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<_ThinkingBlock> {
  late bool _open = widget.live || widget.stayOpen;
  bool _pinned = false;

  @override
  void didUpdateWidget(_ThinkingBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pinned) return;
    if (widget.live || widget.stayOpen) {
      _open = true;
      return;
    }
    if (oldWidget.live) _open = false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final muted = colors.muted;
    final label = widget.live ? '思考中' : '思考';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: label,
          child: InkWell(
            onTap: () => setState(() {
              _pinned = true;
              _open = !_open;
            }),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FLucideIcons.brain, size: 15, color: muted),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: muted,
                      height: 1.3,
                    ),
                  ),
                  Icon(
                    _open ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
                    size: 14,
                    color: muted,
                  ),
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
              maxHeight: 180,
              reverse: widget.live,
              child: Text(
                widget.text,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: colors.ink.withValues(alpha: 0.72),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnswerText extends StatelessWidget {
  const _AnswerText({required this.text, required this.streaming});

  final String text;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return const MarkdownTextRenderer().render(text, isStreaming: streaming);
  }
}

class _CopyAnswerButton extends StatefulWidget {
  const _CopyAnswerButton({required this.text});

  final String text;

  @override
  State<_CopyAnswerButton> createState() => _CopyAnswerButtonState();
}

class _CopyAnswerButtonState extends State<_CopyAnswerButton> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void didUpdateWidget(_CopyAnswerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text && _copied) {
      _resetTimer?.cancel();
      _copied = false;
    }
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _copy() {
    unawaited(HapticFeedback.lightImpact());
    unawaited(Clipboard.setData(ClipboardData(text: widget.text)));
    _resetTimer?.cancel();
    setState(() => _copied = true);
    _resetTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = _copied ? colors.primary : colors.inactive;
    return Tooltip(
      message: _copied ? '已复制' : '复制',
      child: InkWell(
        onTap: _copy,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _copied ? FLucideIcons.check : FLucideIcons.copy,
                size: 15,
                color: color,
              ),
              if (_copied) ...[
                const SizedBox(width: 4),
                Text(
                  '已复制',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
