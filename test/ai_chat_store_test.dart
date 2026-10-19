import 'dart:convert';

import 'package:flutter_ai_client/flutter_ai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/features/ai/data/ai_chat_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

AiConversation _conversation(String id, String title) => AiConversation(
  id: id,
  messages: [
    AiMessage.text(
      id: '$id-user',
      role: AiRole.user,
      text: title,
      createdAt: DateTime(2026, 10, 19, 12),
    ),
  ],
);

void main() {
  test('多会话保存、排序、读取和删除', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PrefsChatThreadStore();

    await store.save('first', _conversation('first', '这个月花了多少'));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await store.save('second', _conversation('second', '上个月餐饮'));

    final threads = await store.listThreads();
    expect(threads.map((thread) => thread.id), ['second', 'first']);
    expect(threads.first.title, '上个月餐饮');
    expect((await store.load('first'))!.messages, hasLength(1));

    await store.writeActiveThreadId('second');
    expect(await store.readActiveThreadId(), 'second');

    await store.delete('second');
    expect(await store.listThreads(), hasLength(1));
    expect(await store.load('second'), isNull);
    expect(await store.readActiveThreadId(), isNull);
  });

  test('旧版单会话会自动迁移成第一个历史会话', () async {
    final legacy = _conversation('legacy', '旧会话');
    SharedPreferences.setMockInitialValues({
      'ai_chat_conversation_v1': jsonEncode(legacy.toJson()),
    });
    final store = PrefsChatThreadStore();

    final threads = await store.listThreads();
    expect(threads, hasLength(1));
    expect(threads.single.id, 'ledger-ai-main');
    expect(threads.single.title, '旧会话');

    final loaded = await store.load('ledger-ai-main');
    expect(loaded, isNotNull);
    expect(loaded!.id, 'ledger-ai-main');
    expect(loaded.messages.single.text, '旧会话');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ai_chat_conversation_v1'), isNull);
  });
}
