import 'dart:convert';

import 'package:flutter_ai_client/flutter_ai_client.dart';

/// 写进助手消息里的用时。页面读它，发给模型时会丢掉。
const kTurnTimingDataType = 'turn-timing';

/// 工具按用途分成几类，每一类共用一个图标。
enum AiToolCategory { stats, search, write, edit, remove, other }

AiToolCategory toolCategory(String toolName) => switch (toolName) {
  'get_cashflow_summary' || 'get_category_breakdown' => AiToolCategory.stats,
  'search_transactions' => AiToolCategory.search,
  'save_transaction' => AiToolCategory.write,
  'update_transaction' => AiToolCategory.edit,
  'delete_transactions' => AiToolCategory.remove,
  _ => AiToolCategory.other,
};

/// 模型在工具参数里写的 `desc`。还没流出来时先占一行。
String toolCallDesc(Map<String, Object?> args) {
  final raw = args['desc'];
  if (raw is String) {
    final text = raw.trim();
    if (text.isNotEmpty) return text;
  }
  return '正在调用';
}

/// 一轮对话花了多久。10 秒以内保留一位小数。
String formatTurnDuration(Duration duration) {
  final ms = duration.inMilliseconds < 0 ? 0 : duration.inMilliseconds;
  if (ms < 10000) {
    return '用时 ${(ms / 1000).toStringAsFixed(1)} 秒';
  }
  final seconds = ms ~/ 1000;
  if (seconds < 60) return '用时 $seconds 秒';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  if (rest == 0) return '用时 $minutes 分钟';
  return '用时 $minutes 分 $rest 秒';
}

int? turnTimingMs(AiMessage message) {
  for (final part in message.parts) {
    if (part is! DataPart || part.dataType != kTurnTimingDataType) continue;
    final raw = part.data['ms'];
    if (raw is int) return raw;
    if (raw is num) return raw.round();
  }
  return null;
}

/// 这一轮里第一条助手消息。用时记在它上面，显示在整段回复的顶部。
bool isAssistantTurnHead(AiMessage message, List<AiMessage> messages) {
  if (message.role != AiRole.assistant) return false;
  final index = messages.indexWhere((item) => item.id == message.id);
  if (index < 0) return false;
  for (var i = index - 1; i >= 0; i--) {
    switch (messages[i].role) {
      case AiRole.user:
        return true;
      case AiRole.assistant:
        return false;
      case AiRole.system:
      case AiRole.tool:
        continue;
    }
  }
  return true;
}

/// 一轮里要画出来的一块内容，带着它所属的那条消息。
class TurnPiece {
  const TurnPiece(this.message, this.part);

  final AiMessage message;
  final AiPart part;
}

/// 一轮助手回复拆成「过程」和「最后一段文字」。
///
/// 过程包括最后一段正文之前的文字、思考和工具调用。没有正文时全部算过程。
class TurnContent {
  const TurnContent({required this.process, this.answer, this.answerMessage});

  final List<TurnPiece> process;
  final TextPart? answer;
  final AiMessage? answerMessage;
}

/// 从这条助手消息起到下一个用户消息之前，含中间的工具结果。
List<AiMessage> messagesInTurn(AiMessage head, List<AiMessage> messages) {
  final index = messages.indexWhere((item) => item.id == head.id);
  if (index < 0) return [head];
  final turn = <AiMessage>[];
  for (var i = index; i < messages.length; i++) {
    if (i != index && messages[i].role == AiRole.user) break;
    turn.add(messages[i]);
  }
  return turn;
}

TurnContent splitAssistantTurn(List<AiMessage> turn) {
  final pieces = <TurnPiece>[];
  for (final message in turn) {
    if (message.role != AiRole.assistant) continue;
    for (final part in message.parts) {
      if (!_visiblePiece(part)) continue;
      pieces.add(TurnPiece(message, part));
    }
  }
  var lastText = -1;
  for (var i = 0; i < pieces.length; i++) {
    if (pieces[i].part is TextPart) lastText = i;
  }
  if (lastText < 0) {
    return TurnContent(process: pieces);
  }
  final answer = pieces[lastText];
  return TurnContent(
    process: pieces.sublist(0, lastText),
    answer: answer.part as TextPart,
    answerMessage: answer.message,
  );
}

/// 只有一段思考，或只有一次工具调用时，不必再收成一行。
bool processStaysOpen(List<TurnPiece> process) {
  var thoughts = 0;
  var tools = 0;
  var other = 0;
  for (final piece in process) {
    final part = piece.part;
    if (part is ReasoningPart) {
      thoughts++;
    } else if (part is ToolCallPart) {
      tools++;
    } else {
      other++;
    }
  }
  if (other > 0) return false;
  if (thoughts == 1 && tools == 0) return true;
  if (tools == 1 && thoughts == 0) return true;
  return false;
}

/// 折叠行上的短标题。
String workProcessLabel(List<TurnPiece> process) {
  var thoughts = 0;
  var tools = 0;
  for (final piece in process) {
    if (piece.part is ReasoningPart) thoughts++;
    if (piece.part is ToolCallPart) tools++;
  }
  final bits = <String>[];
  if (thoughts > 0) bits.add('思考');
  if (tools == 1) bits.add('1 个工具');
  if (tools > 1) bits.add('$tools 个工具');
  if (bits.isEmpty) return '过程';
  return bits.join(' · ');
}

bool _visiblePiece(AiPart part) {
  if (part is DataPart && part.dataType == kTurnTimingDataType) return false;
  if (part is ToolResultPart) return false;
  if (part is TextPart && part.text.trim().isEmpty) return false;
  if (part is ReasoningPart && part.text.trim().isEmpty) return false;
  return true;
}

String? assistantTurnHeadId(AiConversation conversation) {
  final messages = conversation.messages;
  final lastUser = messages.lastIndexWhere(
    (message) => message.role == AiRole.user,
  );
  final start = lastUser < 0 ? 0 : lastUser + 1;
  for (var i = start; i < messages.length; i++) {
    if (messages[i].role == AiRole.assistant) return messages[i].id;
  }
  return null;
}

/// 把用时写进这一轮第一条助手消息。已经记过，或这一轮还没有助手消息时原样返回。
AiConversation stampTurnDuration(
  AiConversation conversation,
  int milliseconds,
) {
  final ms = milliseconds < 0 ? 0 : milliseconds;
  final messages = conversation.messages;
  final lastUser = messages.lastIndexWhere(
    (message) => message.role == AiRole.user,
  );
  final start = lastUser < 0 ? 0 : lastUser + 1;
  for (var i = start; i < messages.length; i++) {
    final message = messages[i];
    if (message.role != AiRole.assistant) continue;
    if (turnTimingMs(message) != null) return conversation;
    final next = [...messages];
    next[i] = message.copyWith(
      parts: [
        DataPart(dataType: kTurnTimingDataType, data: {'ms': ms}),
        ...message.parts,
      ],
    );
    return conversation.copyWith(messages: next);
  }
  return conversation;
}

Map<String, ToolResultPart> toolResultsIn(List<AiMessage> messages) {
  final results = <String, ToolResultPart>{};
  for (final message in messages) {
    for (final part in message.parts) {
      if (part is ToolResultPart) results[part.toolCallId] = part;
    }
  }
  return results;
}

/// 回答正文里的一块：一段 Markdown 文本，或一组账单卡片。
///
/// 卡片按模型输出标记的位置就地渲染，不在回答末尾统一堆放。
sealed class AiAnswerBlock {
  const AiAnswerBlock();
}

class AiAnswerTextBlock extends AiAnswerBlock {
  const AiAnswerTextBlock(this.text);

  final String text;
}

class AiAnswerBillsBlock extends AiAnswerBlock {
  const AiAnswerBillsBlock(this.ids);

  final List<String> ids;
}

/// 账单卡片标记：`<bills>["id1","id2"]</bills>`。
///
/// 标记写在哪儿，卡片就渲染在哪儿，一段回答里可以出现多次。
final _billTag = RegExp(r'<bills>\s*(\[[\s\S]*?\])\s*</bills>');

/// 把回答正文切成「文本 / 账单卡片」交替的块序列。
///
/// 模型没按约定输出时整段当文本，不会崩，也不会漏字。
List<AiAnswerBlock> splitAnswerBlocks(String text) {
  final blocks = <AiAnswerBlock>[];
  var cursor = 0;
  for (final match in _billTag.allMatches(text)) {
    _appendText(blocks, text.substring(cursor, match.start));
    final ids = _billIds(match.group(1)!);
    if (ids.isNotEmpty) blocks.add(AiAnswerBillsBlock(ids));
    cursor = match.end;
  }
  var rest = text.substring(cursor);
  // 流式中途半截标记还没写完，先别把它露出来。
  final open = rest.lastIndexOf('<bills>');
  if (open >= 0 && !rest.contains('</bills>', open)) {
    rest = rest.substring(0, open);
  }
  _appendText(blocks, rest);
  return blocks;
}

List<String> _billIds(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is String && item.isNotEmpty) item,
    ];
  } on Object {
    // JSON 写坏了就当作没有卡片，标记本身仍然剥掉。
    return const [];
  }
}

void _appendText(List<AiAnswerBlock> blocks, String raw) {
  final text = raw.trim();
  if (text.isEmpty) return;
  blocks.add(AiAnswerTextBlock(text));
}
