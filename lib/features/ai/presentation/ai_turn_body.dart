import 'package:flutter/material.dart';
import 'package:flutter_ai_elements/flutter_ai_elements.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/app_theme.dart';
import '../application/ai_turn_format.dart';
import 'ai_downward_reveal.dart';
import 'ai_tool_row.dart';
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
            if (content.answer != null)
              _AnswerText(
                text: content.answer!.text,
                streaming:
                    working &&
                    content.answerMessage?.status == AiMessageStatus.streaming,
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
    if (widget.working) return body;

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
      return _ThinkingBlock(text: part.text.trim(), live: live);
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
  const _ThinkingBlock({required this.text, required this.live});

  final String text;
  final bool live;

  @override
  State<_ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<_ThinkingBlock> {
  late bool _open = widget.live;
  bool _pinned = false;

  @override
  void didUpdateWidget(_ThinkingBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.live) {
      _open = true;
      return;
    }
    if (oldWidget.live && !_pinned) _open = false;
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
