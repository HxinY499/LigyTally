import 'dart:async';
import 'dart:convert';

import 'package:flutter_ai_provider_openai/flutter_ai_provider_openai.dart';
import 'package:http/http.dart' as http;

/// DeepSeek 的 Chat Completions。
///
/// 协议和 OpenAI 兼容，但思考内容走 `reasoning_content`。
/// 现成的 [OpenAiProvider] 会把这个字段丢掉，思考既不会出现在消息里，
/// 下一轮带工具调用时也补不回去。DeepSeek 要求把上一跳的思考原样带回，
/// 否则工具循环会 400。
class DeepSeekProvider implements LlmProvider {
  DeepSeekProvider({
    required this.apiKey,
    Uri? baseUrl,
    http.Client? client,
    this.defaultModel = 'deepseek-flash',
    this.maxRetries = 2,
    this.timeout = const Duration(seconds: 60),
    this.errorLabel = 'DeepSeek',
  }) : _baseUrl = baseUrl ?? Uri.parse('https://api.deepseek.com'),
       _ownsClient = client == null,
       _client = client ?? http.Client();

  final String apiKey;
  final String defaultModel;
  final int maxRetries;
  final Duration timeout;

  /// 写进错误详情的平台名，智谱/Kimi 复用本 provider 时错误不再顶着
  /// 「DeepSeek」的前缀。
  final String errorLabel;

  final Uri _baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _client.close();
  }

  @override
  Stream<AiStreamEvent> send(
    AiConversation conversation, {
    List<ToolDefinition>? tools,
    AiRequestOptions? options,
  }) async* {
    final extra = options?.extra ?? const <String, Object?>{};
    final payload = <String, Object?>{
      ...extra,
      'model': options?.model ?? defaultModel,
      'messages': _buildMessages(conversation),
      'stream': true,
      'stream_options': extra['stream_options'] ?? {'include_usage': true},
      if (options?.temperature != null) 'temperature': options!.temperature,
      if (options?.maxOutputTokens != null)
        'max_completion_tokens': options!.maxOutputTokens,
      if (tools != null && tools.isNotEmpty) 'tools': _buildTools(tools),
    };

    final http.StreamedResponse response;
    try {
      response = await _connect(
        () => http.Request('POST', _endpoint())
          ..headers['authorization'] = 'Bearer $apiKey'
          ..headers['content-type'] = 'application/json'
          ..body = jsonEncode(payload),
      );
    } on Object catch (error) {
      yield StreamErrorEvent(error: error);
      return;
    }

    final parser = DeepSeekChunkParser();
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(timeout);
    try {
      await for (final line in lines) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) continue;
        final data = trimmed.substring(5).trim();
        if (data == '[DONE]') break;
        final Object? decoded;
        try {
          decoded = jsonDecode(data);
        } on FormatException {
          continue;
        }
        if (decoded is! Map) continue;
        for (final event in parser.parse(decoded.cast<String, Object?>())) {
          yield event;
        }
      }
    } on TimeoutException catch (error) {
      yield StreamErrorEvent(error: error, messageId: parser.messageId);
      return;
    }
    for (final event in parser.finalize()) {
      yield event;
    }
  }

  Future<http.StreamedResponse> _connect(http.Request Function() build) async {
    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await _client.send(build()).timeout(timeout);
        if (response.statusCode == 200) return response;
        final body = await response.stream.bytesToString();
        final error = llmExceptionFor(response.statusCode, '$errorLabel: $body');
        final retryable =
            response.statusCode == 429 || response.statusCode >= 500;
        if (!retryable || attempt == maxRetries) throw error;
        lastError = error;
        // 429 是账户级限流：服务端可能还在处理上一个请求（思考型模型的
        // 长尾能拖几十秒），几百毫秒就重试只会继续撞墙。尊重 Retry-After，
        // 否则按秒级退避；5xx 保持原来的短退避。
        if (response.statusCode == 429) {
          await Future<void>.delayed(_rateLimitDelay(response, attempt));
          continue;
        }
      } on TimeoutException catch (error) {
        lastError = error;
        if (attempt == maxRetries) rethrow;
      } on http.ClientException catch (error) {
        lastError = error;
        if (attempt == maxRetries) rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 400 * (1 << attempt)));
    }
    throw lastError ?? StateError('$errorLabel 连接失败');
  }

  static Duration _rateLimitDelay(http.StreamedResponse response, int attempt) {
    final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
    if (retryAfter != null && retryAfter > 0) {
      return Duration(seconds: retryAfter.clamp(1, 15));
    }
    return Duration(seconds: 2 * (1 << attempt));
  }

  Uri _endpoint() {
    final base = _baseUrl.toString().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/chat/completions');
  }

  List<Map<String, Object?>> _buildMessages(AiConversation conversation) {
    final messages = <Map<String, Object?>>[];
    for (final message in conversation.messages) {
      switch (message.role) {
        case AiRole.system:
          messages.add({'role': 'system', 'content': message.text});
        case AiRole.user:
          messages.add({'role': 'user', 'content': _userContent(message)});
        case AiRole.assistant:
          final toolCalls = message.parts.whereType<ToolCallPart>().toList();
          final reasoning = message.parts
              .whereType<ReasoningPart>()
              .map((part) => part.text)
              .where((text) => text.isNotEmpty)
              .join();
          messages.add({
            'role': 'assistant',
            'content': message.text.isEmpty ? null : message.text,
            if (reasoning.isNotEmpty) 'reasoning_content': reasoning,
            if (toolCalls.isNotEmpty)
              'tool_calls': [
                for (final call in toolCalls)
                  {
                    'id': call.toolCallId,
                    'type': 'function',
                    'function': {
                      'name': call.toolName,
                      'arguments': jsonEncode(call.args),
                    },
                  },
              ],
          });
          messages.addAll(_toolResults(message));
        case AiRole.tool:
          messages.addAll(_toolResults(message));
      }
    }
    return messages;
  }

  Object? _userContent(AiMessage message) {
    final images = message.parts
        .whereType<FilePart>()
        .where((file) => file.mediaType.startsWith('image/'))
        .toList();
    if (images.isEmpty) return message.text;
    return [
      if (message.text.isNotEmpty) {'type': 'text', 'text': message.text},
      for (final image in images)
        {
          'type': 'image_url',
          'image_url': {'url': _imageUrl(image)},
        },
    ];
  }

  static String _imageUrl(FilePart image) => image.bytes != null
      ? 'data:${image.mediaType};base64,${base64Encode(image.bytes!)}'
      : image.url.toString();

  Iterable<Map<String, Object?>> _toolResults(AiMessage message) =>
      message.parts.whereType<ToolResultPart>().map(
        (result) => {
          'role': 'tool',
          'tool_call_id': result.toolCallId,
          'content': result.result is String
              ? result.result as String
              : jsonEncode(result.result),
        },
      );

  List<Map<String, Object?>> _buildTools(List<ToolDefinition> tools) => [
    for (final tool in tools)
      {
        'type': 'function',
        'function': {
          'name': tool.name,
          'description': tool.description,
          'parameters': tool.parametersSchema,
        },
      },
  ];
}

/// 在 OpenAI 块解析之上补上 DeepSeek 的 `reasoning_content`。
class DeepSeekChunkParser {
  final OpenAiChunkParser _inner = OpenAiChunkParser();

  String get messageId => _inner.messageId;

  List<AiStreamEvent> finalize() => _inner.finalize();

  List<AiStreamEvent> parse(Map<String, Object?> chunk) {
    final events = _inner.parse(chunk);
    final reasoning = _reasoningText(chunk);
    if (reasoning == null) return events;
    final event = ReasoningDelta(messageId: _inner.messageId, delta: reasoning);
    final out = <AiStreamEvent>[];
    var placed = false;
    for (final item in events) {
      final isContent =
          item is TextDelta || item is ToolCallStarted || item is ToolCallDelta;
      if (!placed && isContent) {
        out.add(event);
        placed = true;
      }
      out.add(item);
    }
    if (placed) return out;
    final started = out.indexWhere((item) => item is MessageStarted);
    if (started >= 0) {
      out.insert(started + 1, event);
    } else {
      out.add(event);
    }
    return out;
  }

  static String? _reasoningText(Map<String, Object?> chunk) {
    final choices = chunk['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return null;
    }
    final delta = (choices.first as Map)['delta'];
    if (delta is! Map) return null;
    final raw = delta['reasoning_content'] ?? delta['reasoning'];
    if (raw is! String || raw.isEmpty) return null;
    return raw;
  }
}
