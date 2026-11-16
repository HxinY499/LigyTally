import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_ai_client/flutter_ai_client.dart';

/// 写进助手消息里的用时。页面读它，发给模型时会丢掉。
const kTurnTimingDataType = 'turn-timing';

/// 工具按用途分成几类，每一类共用一个图标。
enum AiToolCategory { stats, search, write, edit, remove, other }

AiToolCategory toolCategory(String toolName) => switch (toolName) {
  'get_cashflow_summary' ||
  'get_category_breakdown' ||
  'get_spending_trend' ||
  'compare_periods' => AiToolCategory.stats,
  'search_transactions' => AiToolCategory.search,
  'save_transaction' || 'save_transactions' => AiToolCategory.write,
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

/// AI 消息内嵌图表的类型。
enum AiChartType { trend, category, delta }

/// `<chart>{...}</chart>` 解析后的查询意图。
///
/// 只携带查询坐标与口径，数据由前端直连本地数据库实时聚合，避免模型拼写长串数字。
class AiChartSpec {
  const AiChartSpec({
    required this.type,
    required this.from,
    required this.to,
    this.compareFrom,
    this.compareTo,
    this.kind = 0,
    this.granularity,
    this.categoryId,
    this.useStatsExclusion = false,
    this.excludedCategoryIds = const {},
    this.title,
  });

  final AiChartType type;
  final DateTime from;
  final DateTime to;
  final DateTime? compareFrom;
  final DateTime? compareTo;

  /// 0 支出，1 收入，2 结余（结余仅按月柱状图支持）。
  final int kind;

  /// `day` / `month` / null（自动）。
  final String? granularity;

  /// 趋势图的分类过滤，或分类构成图的一级分类下钻。
  final String? categoryId;

  final bool useStatsExclusion;
  final Set<String> excludedCategoryIds;
  final String? title;

  String get identityKey =>
      '${type.name}|${from.toIso8601String()}|${to.toIso8601String()}|'
      '${compareFrom?.toIso8601String() ?? ''}|'
      '${compareTo?.toIso8601String() ?? ''}|'
      '$kind|${granularity ?? ''}|${categoryId ?? ''}|'
      '$useStatsExclusion|${excludedCategoryIds.join(',')}';
}

/// 回答正文里的一块：Markdown 文本、账单卡片或实时统计图表。
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

class AiAnswerChartBlock extends AiAnswerBlock {
  const AiAnswerChartBlock(this.spec);

  final AiChartSpec spec;
}

/// 正文内嵌块标记：`<bills>[...]</bills>` 与 `<chart>{...}</chart>`。
final _inlineTag = RegExp(r'<(bills|chart)>\s*([\s\S]*?)\s*</\1>');

/// 流式末尾刚吐出一半的标签头（如 `<bil` / `<cha`），避免裸露一帧尖括号。
final _trailingTagPrefix = RegExp(r'<(?:bi?l?l?s?|ch?a?r?t?)$');

/// 把回答正文切成「文本 / 账单卡片 / 统计图表」交替的块序列。
///
/// 标记写在哪儿，对应组件就渲染在哪儿；模型输出损坏时静默剥除标记，不崩溃。
List<AiAnswerBlock> splitAnswerBlocks(String text) {
  final blocks = <AiAnswerBlock>[];
  var cursor = 0;
  for (final match in _inlineTag.allMatches(text)) {
    _appendText(blocks, text.substring(cursor, match.start));
    final tag = match.group(1)!;
    final payload = match.group(2)!;
    if (tag == 'bills') {
      final ids = _billIds(payload);
      if (ids.isNotEmpty) blocks.add(AiAnswerBillsBlock(ids));
    } else if (tag == 'chart') {
      final spec = _parseChartSpec(payload);
      if (spec != null) blocks.add(AiAnswerChartBlock(spec));
    }
    cursor = match.end;
  }
  var rest = text.substring(cursor);
  // 流式中途半截标记还没写完，先别把它露出来。
  final cut = _unclosedTagOffset(rest);
  if (cut >= 0) {
    rest = rest.substring(0, cut);
  }
  _appendText(blocks, rest);
  return blocks;
}

int _unclosedTagOffset(String rest) {
  var cut = -1;
  final openBills = rest.lastIndexOf('<bills>');
  if (openBills >= 0 && !rest.contains('</bills>', openBills)) {
    cut = openBills;
  }
  final openChart = rest.lastIndexOf('<chart>');
  if (openChart >= 0 && !rest.contains('</chart>', openChart)) {
    cut = cut < 0 ? openChart : math.min(cut, openChart);
  }
  if (cut >= 0) return cut;
  final prefixMatch = _trailingTagPrefix.firstMatch(rest);
  return prefixMatch?.start ?? -1;
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
    return const [];
  }
}

AiChartSpec? _parseChartSpec(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return null;
    final rawType = decoded['type']?.toString().trim();
    final AiChartType? type = switch (rawType) {
      'trend' => AiChartType.trend,
      'category' || 'breakdown' => AiChartType.category,
      'delta' || 'comparison' || 'compare' => AiChartType.delta,
      _ => null,
    };
    if (type == null) return null;

    final from = _tryParseYmd(decoded['from']?.toString());
    final to = _tryParseYmd(decoded['to']?.toString());
    if (from == null || to == null || to.isBefore(from)) return null;
    final dayCount = to.difference(from).inDays + 1;
    if (dayCount > 3660) return null;

    DateTime? compareFrom = _tryParseYmd(decoded['compareFrom']?.toString());
    DateTime? compareTo = _tryParseYmd(decoded['compareTo']?.toString());
    if (type == AiChartType.delta) {
      if (compareFrom == null || compareTo == null) {
        final shift = Duration(days: dayCount);
        compareFrom = from.subtract(shift);
        compareTo = to.subtract(shift);
      } else if (compareTo.isBefore(compareFrom)) {
        return null;
      }
      final currentEndEx = to.add(const Duration(days: 1));
      final compareEndEx = compareTo.add(const Duration(days: 1));
      if (from.isBefore(compareEndEx) && compareFrom.isBefore(currentEndEx)) {
        return null;
      }
    }

    final kind = switch (decoded['kind']?.toString().trim()) {
      'income' => 1,
      'net' => 2,
      _ => 0,
    };
    final rawGranularity = decoded['granularity']?.toString().trim();
    final granularity = (rawGranularity == 'day' || rawGranularity == 'month')
        ? rawGranularity
        : null;
    final rawCat = (decoded['categoryId'] ?? decoded['parentCategoryId'])
        ?.toString()
        .trim();
    final categoryId = (rawCat == null || rawCat.isEmpty) ? null : rawCat;
    final useStatsExclusion = decoded['useStatsExclusion'] == true;
    final rawExcluded = decoded['excludedCategoryIds'];
    final excludedCategoryIds = <String>{
      if (rawExcluded is List)
        for (final item in rawExcluded)
          if (item != null && item.toString().trim().isNotEmpty)
            item.toString().trim(),
    };
    final rawTitle = decoded['title']?.toString().trim();
    final title = (rawTitle == null || rawTitle.isEmpty) ? null : rawTitle;

    return AiChartSpec(
      type: type,
      from: from,
      to: to,
      compareFrom: compareFrom,
      compareTo: compareTo,
      kind: kind,
      granularity: granularity,
      categoryId: categoryId,
      useStatsExclusion: useStatsExclusion,
      excludedCategoryIds: excludedCategoryIds,
      title: title,
    );
  } on Object {
    return null;
  }
}

DateTime? _tryParseYmd(String? raw) {
  if (raw == null) return null;
  final text = raw.trim();
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return null;
  final parts = text.split('-').map(int.parse).toList();
  final parsed = DateTime(parts[0], parts[1], parts[2]);
  if (parsed.year != parts[0] ||
      parsed.month != parts[1] ||
      parsed.day != parts[2]) {
    return null;
  }
  return parsed;
}

void _appendText(List<AiAnswerBlock> blocks, String raw) {
  final text = raw.trim();
  if (text.isEmpty) return;
  blocks.add(AiAnswerTextBlock(text));
}

/// 提取回答正文里给人看的纯文本，剥除 `<bills>` 与 `<chart>` 等内部标记。
String plainAnswerText(String text) {
  final parts = <String>[
    for (final block in splitAnswerBlocks(text))
      if (block is AiAnswerTextBlock) block.text,
  ];
  return parts.join('\n\n');
}
