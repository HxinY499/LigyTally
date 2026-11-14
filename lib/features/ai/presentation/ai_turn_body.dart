import 'package:flutter/material.dart';
import 'package:flutter_ai_elements/flutter_ai_elements.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../application/ai_turn_format.dart';
import 'ai_tool_row.dart';
import 'ai_turn_label.dart';

/// 一轮助手回复。
///
/// 进行中时，思考、工具和中途写的字都摊开。结束后这些收成一行，
/// 只留下最后一段正文。点那一行可以再打开。
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
  });

  final List<TurnPiece> pieces;
  final Map<String, ToolResultPart> results;
  final bool working;

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
      children: [for (final piece in widget.pieces) _piece(piece)],
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
        AnimatedSize(
          duration: context.motion(const Duration(milliseconds: 180)),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 6),
                  child: body,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _piece(TurnPiece piece) {
    final part = piece.part;
    if (part is ReasoningPart) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          part.text.trim(),
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: context.colors.ink.withValues(alpha: 0.62),
          ),
        ),
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
