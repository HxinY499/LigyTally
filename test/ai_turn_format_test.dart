import 'package:flutter_ai_client/flutter_ai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/features/ai/application/ai_settings.dart';
import 'package:ligy_tally/features/ai/application/ai_turn_format.dart';
import 'package:ligy_tally/features/ai/application/deepseek_provider.dart';

void main() {
  test('工具说明按参数生成，不暴露工具名', () {
    expect(
      describeToolCall('get_cashflow_summary', {
        'from': '2026-11-01',
        'to': '2026-11-14',
      }),
      '查询${formatDateSpan('2026-11-01', '2026-11-14')}的收支',
    );
    expect(describeToolCall('search_transactions', {'query': '午饭'}), '查找「午饭」');
    expect(
      describeToolCall('save_transaction', {
        'kind': 'expense',
        'amountCents': 2800,
      }),
      '记一笔支出 ¥28.00',
    );
    expect(
      describeToolCall('delete_transactions', {
        'ids': ['a', 'b'],
      }),
      '删除 2 笔账单',
    );
    expect(describeToolCall('get_cashflow_summary', {}), '正在查询收支');
    expect(toolCategory('search_transactions'), AiToolCategory.search);
    expect(toolCategory('save_transaction'), AiToolCategory.write);
    expect(toolCategory('delete_transactions'), AiToolCategory.remove);
  });

  test('用时按秒和分钟收成一句', () {
    expect(formatTurnDuration(const Duration(milliseconds: 800)), '用时 0.8 秒');
    expect(formatTurnDuration(const Duration(milliseconds: 1200)), '用时 1.2 秒');
    expect(formatTurnDuration(const Duration(seconds: 12)), '用时 12 秒');
    expect(formatTurnDuration(const Duration(seconds: 65)), '用时 1 分 5 秒');
    expect(formatTurnDuration(const Duration(minutes: 2)), '用时 2 分钟');
  });

  test('用时写进这一轮第一条助手消息，再读出来', () {
    final conversation = AiConversation(
      id: 'c',
      messages: [
        AiMessage.text(id: 'u', role: AiRole.user, text: '这个月呢'),
        AiMessage.text(id: 'a1', role: AiRole.assistant, text: '查一下'),
        AiMessage(
          id: 't',
          role: AiRole.tool,
          parts: [
            const ToolResultPart(toolCallId: 'call-1', result: {'ok': true}),
          ],
        ),
        AiMessage.text(id: 'a2', role: AiRole.assistant, text: '花了 100'),
      ],
    );

    final stamped = stampTurnDuration(conversation, 1800);
    expect(turnTimingMs(stamped.messages[1]), 1800);
    expect(turnTimingMs(stamped.messages[3]), isNull);
    expect(isAssistantTurnHead(stamped.messages[1], stamped.messages), isTrue);
    expect(isAssistantTurnHead(stamped.messages[3], stamped.messages), isFalse);
    expect(stampTurnDuration(stamped, 999), same(stamped));
  });

  test('思考档位写成 DeepSeek 的 thinking 和 reasoning_effort', () {
    expect(thinkingRequestExtra(AiReasoningEffort.off), {
      'thinking': {'type': 'disabled'},
    });
    expect(
      thinkingRequestExtra(AiReasoningEffort.low)['reasoning_effort'],
      'low',
    );
    expect(
      thinkingRequestExtra(AiReasoningEffort.high)['reasoning_effort'],
      'high',
    );
    expect(
      thinkingRequestExtra(AiReasoningEffort.max)['reasoning_effort'],
      'max',
    );
    expect(AiReasoningEffort.fromWire(null), AiReasoningEffort.high);
    expect(AiReasoningEffort.fromWire('nope'), AiReasoningEffort.high);
  });

  test('DeepSeek 的 reasoning_content 会变成思考增量，并且排在正文前面', () {
    final parser = DeepSeekChunkParser();
    final started = parser.parse({
      'id': 'm1',
      'choices': [
        {
          'delta': {'reasoning_content': '先看日期'},
        },
      ],
    });
    expect(started[0], isA<MessageStarted>());
    expect(started[1], isA<ReasoningDelta>());
    expect((started[1] as ReasoningDelta).delta, '先看日期');

    final followed = parser.parse({
      'choices': [
        {
          'delta': {'content': '本月'},
        },
      ],
    });
    expect(followed, hasLength(1));
    expect(followed.single, isA<TextDelta>());
  });
}
