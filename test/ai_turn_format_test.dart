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
    expect(toolCategory('save_transactions'), AiToolCategory.write);
    expect(toolCategory('get_spending_trend'), AiToolCategory.stats);
    expect(toolCategory('compare_periods'), AiToolCategory.stats);
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

  test('bills 标记在哪儿，卡片就切在哪儿', () {
    List<String> texts(List<AiAnswerBlock> blocks) => [
      for (final block in blocks)
        if (block is AiAnswerTextBlock) block.text,
    ];
    List<List<String>> cards(List<AiAnswerBlock> blocks) => [
      for (final block in blocks)
        if (block is AiAnswerBillsBlock) block.ids,
    ];

    // 标记在中间：前后都是正文，卡片夹在中间。
    final middle = splitAnswerBlocks(
      '上午这笔是：\n<bills>["t1"]</bills>\n下午还有一笔。',
    );
    expect(texts(middle), ['上午这笔是：', '下午还有一笔。']);
    expect(cards(middle), [
      ['t1'],
    ]);

    // 一组回答里可以有多个标记，各就各位。
    final multiple = splitAnswerBlocks(
      '先说支出：\n<bills>["t1","t2"]</bills>\n收入这些：\n<bills>["t3"]</bills>',
    );
    expect(texts(multiple), ['先说支出：', '收入这些：']);
    expect(cards(multiple), [
      ['t1', 't2'],
      ['t3'],
    ]);

    // 没有标记时就是一整段文本。
    final plain = splitAnswerBlocks('这个月餐饮花了 280 元。');
    expect(texts(plain), ['这个月餐饮花了 280 元。']);
    expect(cards(plain), isEmpty);

    // 流式中途的半截标记先藏起来，等写完再解析。
    final streaming = splitAnswerBlocks('找到了，是这两笔。\n<bills>["t1"');
    expect(texts(streaming), ['找到了，是这两笔。']);
    expect(cards(streaming), isEmpty);

    // JSON 写坏了：标记剥掉，不出空卡片，不崩。
    final broken = splitAnswerBlocks('找到了。\n<bills>[t1,t2]</bills>');
    expect(texts(broken), ['找到了。']);
    expect(cards(broken), isEmpty);

    // 空列表不产生卡片。
    expect(splitAnswerBlocks('<bills>[]</bills>'), isEmpty);
  });

  test('chart 与 bills 标记可混排解析，流式半截与非法区间自动隐藏或剥除', () {
    final mixed = splitAnswerBlocks(
      '本月走势如下：\n'
      '<chart>{"type":"trend","from":"2026-10-01","to":"2026-10-31","kind":"expense","granularity":"day"}</chart>\n'
      '其中最大的一笔是：\n'
      '<bills>["tx-99"]</bills>',
    );
    expect(mixed, hasLength(4));
    expect(mixed[0], isA<AiAnswerTextBlock>());
    expect(mixed[1], isA<AiAnswerChartBlock>());
    final chart = (mixed[1] as AiAnswerChartBlock).spec;
    expect(chart.type, AiChartType.trend);
    expect(chart.granularity, 'day');
    expect(mixed[2], isA<AiAnswerTextBlock>());
    expect((mixed[3] as AiAnswerBillsBlock).ids, ['tx-99']);

    // 流式半截 <chart> 或 <cha 不外露
    final halfChart = splitAnswerBlocks(
      '看看构成：\n<chart>{"type":"category","from":"2026-10-01"',
    );
    expect(halfChart, hasLength(1));
    expect((halfChart.single as AiAnswerTextBlock).text, '看看构成：');

    final prefixOnly = splitAnswerBlocks('看看构成：\n<cha');
    expect(prefixOnly, hasLength(1));
    expect((prefixOnly.single as AiAnswerTextBlock).text, '看看构成：');

    // delta 未传对照期时自动推算等长上一周期；重叠区间则静默丢弃
    final autoDelta = splitAnswerBlocks(
      '<chart>{"type":"delta","from":"2026-10-11","to":"2026-10-20"}</chart>',
    );
    expect(autoDelta, hasLength(1));
    final deltaSpec = (autoDelta.single as AiAnswerChartBlock).spec;
    expect(deltaSpec.compareFrom, DateTime(2026, 10, 1));
    expect(deltaSpec.compareTo, DateTime(2026, 10, 10));

    final overlapped = splitAnswerBlocks(
      '<chart>{"type":"delta","from":"2026-10-01","to":"2026-10-20","compareFrom":"2026-10-10","compareTo":"2026-10-30"}</chart>',
    );
    expect(overlapped, isEmpty);
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
