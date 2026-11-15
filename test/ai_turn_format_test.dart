import 'package:flutter_ai_client/flutter_ai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/features/ai/application/ai_settings.dart';
import 'package:ligy_tally/features/ai/application/ai_turn_format.dart';
import 'package:ligy_tally/features/ai/application/deepseek_provider.dart';

void main() {
  test('工具说明用模型写的 desc，参数没到齐时先占位', () {
    expect(
      toolCallDesc({'desc': ' 查询这个月的收支 ', 'from': '2026-11-01'}),
      '查询这个月的收支',
    );
    expect(toolCallDesc({'from': '2026-11-01'}), '正在调用');
    expect(toolCallDesc({'desc': '   '}), '正在调用');
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

  test('智谱和 Kimi 不能关思考，Kimi 不传 thinking', () {
    expect(thinkingExtraFor('glm-5.3', AiReasoningEffort.off), {
      'thinking': {'type': 'enabled'},
      'reasoning_effort': 'low',
    });
    expect(thinkingExtraFor('glm-5.3-flash', AiReasoningEffort.max), {
      'thinking': {'type': 'enabled'},
      'reasoning_effort': 'max',
    });
    expect(thinkingExtraFor('kimi-k3.1-pro', AiReasoningEffort.off), {
      'reasoning_effort': 'low',
    });
    expect(thinkingExtraFor('kimi-k3', AiReasoningEffort.high), {
      'reasoning_effort': 'high',
    });
    expect(
      thinkingExtraFor('deepseek-v4-pro', AiReasoningEffort.off),
      thinkingRequestExtra(AiReasoningEffort.off),
    );
  });

  test('只列出已经配置 Key 的平台，模型是叠加的', () {
    expect(
      modelsForConfigured({AiPlatform.glm, AiPlatform.kimi}).map((m) => m.id),
      [
        'glm-5.3',
        'glm-5.3-flash',
        'kimi-k3.1-pro',
        'kimi-k3.1-pro-highspeed',
        'kimi-k3',
      ],
    );
    expect(
      resolveSelectedModel('deepseek-flash', {AiPlatform.kimi}),
      'kimi-k3.1-pro',
    );
    expect(
      resolveSelectedModel('glm-5.3-flash', {
        AiPlatform.deepseek,
        AiPlatform.glm,
      }),
      'glm-5.3-flash',
    );
  });

  test('一轮结束后，最后一段文字之外都算过程', () {
    final first = AiMessage(
      id: 'a1',
      role: AiRole.assistant,
      parts: const [
        ReasoningPart('先查'),
        TextPart('我先看一下范围。'),
        ToolCallPart(
          toolCallId: 'c1',
          toolName: 'search_transactions',
          state: ToolCallState.outputAvailable,
        ),
      ],
    );
    final second = AiMessage.text(
      id: 'a2',
      role: AiRole.assistant,
      text: '这个月餐饮花了 28 元。',
    );
    final content = splitAssistantTurn([first, second]);
    expect(content.answer?.text, '这个月餐饮花了 28 元。');
    expect(content.process.map((piece) => piece.part.runtimeType).toList(), [
      ReasoningPart,
      TextPart,
      ToolCallPart,
    ]);
    expect(workProcessLabel(content.process), '思考 · 1 个工具');
    expect(processStaysOpen(content.process), isFalse);
    expect(
      processStaysOpen([
        TurnPiece(
          AiMessage.text(id: 'a', role: AiRole.assistant, text: ''),
          const ReasoningPart('只有一段'),
        ),
      ]),
      isTrue,
    );
    expect(
      processStaysOpen([
        TurnPiece(
          AiMessage.text(id: 'a', role: AiRole.assistant, text: ''),
          const ToolCallPart(
            toolCallId: 'c',
            toolName: 'search_transactions',
            state: ToolCallState.outputAvailable,
          ),
        ),
      ]),
      isTrue,
    );
    expect(
      splitAssistantTurn([
        AiMessage.text(id: 'a', role: AiRole.assistant, text: '只有回答'),
      ]).process,
      isEmpty,
    );
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
