import 'dart:convert';

import 'package:flutter_ai_client/flutter_ai_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// AI 会话只存在本机，支持多会话列表。
///
/// 旧版本只有一个 `ai_chat_conversation_v1`，读取时会自动迁移成
/// `ledger-ai-main` 会话，历史聊天不会因为这次升级丢掉。
class PrefsChatThreadStore implements ChatThreadStore {
  static const _legacyKey = 'ai_chat_conversation_v1';
  static const _indexKey = 'ai_chat_threads_v1';
  static const _activeKey = 'ai_chat_active_thread_v1';
  static const _prefix = 'ai_chat_thread_v1_';
  static const _legacyThreadId = 'ledger-ai-main';
  static const _uuid = Uuid();

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  String _threadKey(String id) => '$_prefix$id';

  String newThreadId() => _uuid.v4();

  Future<String?> readActiveThreadId() async =>
      (await _prefs).getString(_activeKey);

  Future<void> writeActiveThreadId(String id) async {
    await (await _prefs).setString(_activeKey, id);
  }

  @override
  Future<AiConversation?> load(String id) async {
    final prefs = await _prefs;
    await _migrateLegacy(prefs);
    final raw = prefs.getString(_threadKey(id));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return AiConversation.fromJson(decoded.cast<String, Object?>());
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(String id, AiConversation conversation) async {
    final prefs = await _prefs;
    await prefs.setString(_threadKey(id), jsonEncode(conversation.toJson()));
    final threads = await _readIndex(prefs);
    final entry = ChatThread(
      id: id,
      title: autoTitle(conversation, fallback: '新会话'),
      updatedAt: DateTime.now(),
    );
    final index = threads.indexWhere((thread) => thread.id == id);
    if (index == -1) {
      threads.add(entry);
    } else {
      threads[index] = entry;
    }
    threads.sort(_newestFirst);
    await _writeIndex(prefs, threads);
  }

  /// 新会话第一次出现时登记到索引；已存在则不动它的更新时间。
  Future<void> ensureThread(String id, AiConversation conversation) async {
    final prefs = await _prefs;
    if (prefs.containsKey(_threadKey(id))) return;
    await save(id, conversation);
  }

  @override
  Future<List<ChatThread>> listThreads() async {
    final prefs = await _prefs;
    await _migrateLegacy(prefs);
    return _readIndex(prefs);
  }

  @override
  Future<void> delete(String id) async {
    final prefs = await _prefs;
    await prefs.remove(_threadKey(id));
    final threads = await _readIndex(prefs)
      ..removeWhere((thread) => thread.id == id);
    await _writeIndex(prefs, threads);
    if (prefs.getString(_activeKey) == id) {
      await prefs.remove(_activeKey);
    }
  }

  Future<void> _migrateLegacy(SharedPreferences prefs) async {
    final raw = prefs.getString(_legacyKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final conversation = AiConversation.fromJson(
        decoded.cast<String, Object?>(),
      );
      if (conversation.messages.isNotEmpty &&
          !prefs.containsKey(_threadKey(_legacyThreadId))) {
        final migrated = conversation.copyWith(id: _legacyThreadId);
        await prefs.setString(
          _threadKey(_legacyThreadId),
          jsonEncode(migrated.toJson()),
        );
        final threads = await _readIndex(prefs);
        if (!threads.any((thread) => thread.id == _legacyThreadId)) {
          threads.add(
            ChatThread(
              id: _legacyThreadId,
              title: autoTitle(conversation, fallback: '历史会话'),
              updatedAt: DateTime.now(),
            ),
          );
          await _writeIndex(prefs, threads);
        }
      }
      await prefs.remove(_legacyKey);
    } on Object {
      // 损坏的旧缓存不阻塞使用；保留原值方便排查。
    }
  }

  Future<List<ChatThread>> _readIndex(SharedPreferences prefs) async {
    final threads = <ChatThread>[];
    final raw = prefs.getString(_indexKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map) continue;
            final map = item.cast<String, Object?>();
            final id = map['id'] as String?;
            if (id == null || id.isEmpty) continue;
            final title = (map['title'] as String?)?.trim();
            final updatedAt = DateTime.tryParse(
              (map['updatedAt'] as String?) ?? '',
            );
            threads.add(
              ChatThread(
                id: id,
                title: title?.isNotEmpty == true ? title! : '新会话',
                updatedAt: updatedAt,
              ),
            );
          }
        }
      } on Object {
        // 索引坏了就回退到扫描会话 key。
      }
    }

    if (threads.isEmpty) {
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(_prefix)) continue;
        final id = key.substring(_prefix.length);
        final rawConversation = prefs.getString(key);
        if (rawConversation == null || rawConversation.isEmpty) continue;
        try {
          final decoded = jsonDecode(rawConversation);
          if (decoded is! Map) continue;
          final conversation = AiConversation.fromJson(
            decoded.cast<String, Object?>(),
          );
          threads.add(
            ChatThread(
              id: id,
              title: autoTitle(conversation, fallback: '新会话'),
              updatedAt: _latestMessageTime(conversation),
            ),
          );
        } on Object {
          // 单个损坏会话不影响其他会话。
        }
      }
    }

    final valid = [
      for (final thread in threads)
        if (prefs.containsKey(_threadKey(thread.id))) thread,
    ]..sort(_newestFirst);
    if (valid.length != threads.length) {
      await _writeIndex(prefs, valid);
    }
    return valid;
  }

  Future<void> _writeIndex(
    SharedPreferences prefs,
    List<ChatThread> threads,
  ) async {
    await prefs.setString(
      _indexKey,
      jsonEncode([
        for (final thread in threads)
          {
            'id': thread.id,
            'title': thread.title,
            if (thread.updatedAt != null)
              'updatedAt': thread.updatedAt!.toIso8601String(),
          },
      ]),
    );
  }

  static int _newestFirst(ChatThread a, ChatThread b) {
    final left = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final right = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return right.compareTo(left);
  }

  static DateTime? _latestMessageTime(AiConversation conversation) {
    DateTime? latest;
    for (final message in conversation.messages) {
      final createdAt = message.createdAt;
      if (createdAt == null) continue;
      if (latest == null || createdAt.isAfter(latest)) {
        latest = createdAt;
      }
    }
    return latest;
  }
}
