import 'package:flutter_ai_client/flutter_ai_client.dart';

import '../../../core/utils/ledger_date.dart';

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

/// 把一次工具调用收成一句人话。参数还没到齐时用进行中的说法。
String describeToolCall(String toolName, Map<String, Object?> args) {
  switch (toolName) {
    case 'get_cashflow_summary':
      final span = formatDateSpan(args['from'], args['to']);
      return span == null ? '正在查询收支' : '查询$span的收支';
    case 'get_category_breakdown':
      final span = formatDateSpan(args['from'], args['to']);
      final kind = args['kind'] == 'income'
          ? '收入'
          : args['kind'] == 'expense'
          ? '支出'
          : null;
      if (span == null || kind == null) return '正在查看分类';
      return '查看$span的$kind分类';
    case 'search_transactions':
      final query = _text(args['query']);
      if (query != null) return '查找「${_clip(query)}」';
      final amount = _cents(args['amountCents']);
      if (amount != null) return '查找 ${formatMoney(amount)} 的账单';
      final span = formatDateSpan(args['from'], args['to']);
      return span == null ? '正在查找账单' : '查找$span的账单';
    case 'save_transaction':
      final amount = _cents(args['amountCents']);
      if (amount == null) return '正在准备记账';
      final kind = args['kind'] == 'income' ? '收入' : '支出';
      final note = _text(args['note']);
      final base = '记一笔$kind ${formatMoney(amount)}';
      return note == null ? base : '$base · ${_clip(note)}';
    case 'update_transaction':
      final bits = <String>[];
      final amount = _cents(args['amountCents']);
      if (amount != null) bits.add('金额改为 ${formatMoney(amount)}');
      if (args['kind'] == 'income') bits.add('改为收入');
      if (args['kind'] == 'expense') bits.add('改为支出');
      final day = formatDateSpan(args['accountingDate'], null);
      if (day != null) bits.add('改到$day');
      final note = args['note'];
      if (note is String) {
        final trimmed = note.trim();
        bits.add(trimmed.isEmpty ? '清空备注' : '备注改为「${_clip(trimmed)}」');
      }
      if (bits.isEmpty) {
        return args.isEmpty ? '正在准备修改' : '修改这笔账单';
      }
      return '修改账单：${bits.join('，')}';
    case 'delete_transactions':
      final ids = args['ids'];
      if (ids is! List || ids.isEmpty) return '正在准备删除';
      return ids.length == 1 ? '删除这笔账单' : '删除 ${ids.length} 笔账单';
    default:
      return '正在处理';
  }
}

/// `from` / `to` 都是 YYYY-MM-DD。同一天、同一个月会收成更短的一句。
String? formatDateSpan(Object? fromRaw, Object? toRaw, {DateTime? now}) {
  final from = _day(fromRaw);
  final to = _day(toRaw);
  if (from == null && to == null) return null;
  final today = now ?? DateTime.now();

  String label(DateTime day, {bool withYear = false}) {
    final year = withYear || day.year != today.year ? '${day.year}年' : '';
    return '$year${day.month}月${day.day}日';
  }

  if (from == null) return label(to!);
  if (to == null || _sameDay(from, to)) return label(from);
  if (from.year == to.year && from.month == to.month) {
    final year = from.year != today.year ? '${from.year}年' : '';
    return '$year${from.month}月${from.day}日–${to.day}日';
  }
  final withYear = from.year != today.year || to.year != today.year;
  return '${label(from, withYear: withYear)}–${label(to, withYear: withYear)}';
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

DateTime? _day(Object? raw) {
  if (raw is! String || raw.length < 10) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int? _cents(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  return null;
}

String? _text(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _clip(String value, [int max = 16]) {
  final compact = value.replaceAll(RegExp(r'\s+'), ' ');
  if (compact.length <= max) return compact;
  return '${compact.substring(0, max)}…';
}
