import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ai_elements/flutter_ai_elements.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../ledger/application/providers.dart';
import '../application/ai_approval.dart';
import '../application/ai_chat_session.dart';
import '../application/ai_settings.dart';
import '../data/ai_chat_store.dart';
import 'ai_settings_screen.dart';

/// AI 助手的唯一页面。
///
/// 流式渲染、Markdown、自动滚动、输入框和停止按钮都由 flutter_ai_elements
/// 负责；本页只做 DeepSeek 会话的创建/销毁、Key 缺失状态、错误提示，以及
/// 写操作的人工确认。
class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final ToolApprovalCoordinator _approval = ToolApprovalCoordinator();
  final PrefsChatThreadStore _store = PrefsChatThreadStore();

  AiChatSession? _session;
  AiSettings? _settings;
  String? _threadId;
  List<ChatThread> _threads = const [];
  VoidCallback? _detachStore;
  bool _loading = true;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _approval.handler = _showApproval;
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _generation++;
    _approval.handler = null;
    _disposeSession();
    super.dispose();
  }

  void _disposeSession() {
    final session = _session;
    if (session != null) {
      // 切会话/退出页面时先把正在流的回复收尾，避免只存下一半消息。
      if (session.chat.status.isBusy) session.chat.stop();
      _detachStore?.call();
      _detachStore = null;
      session.dispose();
      _session = null;
      return;
    }
    _detachStore?.call();
    _detachStore = null;
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    _disposeSession();
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final settings = await ref.read(aiSettingsProvider.future);
      if (!mounted || generation != _generation) return;
      if (!settings.hasKey) {
        setState(() {
          _settings = settings;
          _threadId = null;
          _threads = const [];
          _loading = false;
        });
        return;
      }

      final threads = await _store.listThreads();
      final activeId = await _store.readActiveThreadId();
      final String threadId;
      if (activeId != null && threads.any((thread) => thread.id == activeId)) {
        threadId = activeId;
      } else if (threads.isNotEmpty) {
        threadId = threads.first.id;
      } else {
        threadId = _store.newThreadId();
      }
      var initial = await _store.load(threadId);
      if (initial == null) {
        initial = AiConversation.empty(threadId);
        await _store.save(threadId, initial);
      }
      await _store.writeActiveThreadId(threadId);
      final session = await AiChatSession.create(
        database: ref.read(databaseProvider),
        ledgerService: ref.read(ledgerServiceProvider),
        settings: settings,
        initial: initial,
        approval: _approval,
      );
      if (!mounted || generation != _generation) {
        session.dispose();
        return;
      }
      _session = session;
      _threadId = threadId;
      _detachStore = attachStore(session.chat, _store, threadId);
      final refreshed = await _store.listThreads();
      if (!mounted || generation != _generation) return;
      setState(() {
        _settings = settings;
        _threads = refreshed;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _retryInitialize() async {
    ref.invalidate(aiSettingsProvider);
    await _initialize();
  }

  Future<bool> _showApproval(ToolApprovalRequest request) async {
    if (!mounted) return false;
    final result = await showAppConfirmDialog(
      context,
      message: request.message,
      confirmLabel: request.confirmLabel,
      accent: request.destructive ? null : context.colors.primary,
    );
    return result && mounted;
  }

  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const AiSettingsScreen()));
    if (mounted) await _initialize();
  }

  Future<void> _refreshThreads() async {
    final threads = await _store.listThreads();
    if (mounted) setState(() => _threads = threads);
  }

  Future<void> _openThread(String id, {AiConversation? initial}) async {
    final settings = _settings ?? ref.read(aiSettingsProvider).value;
    if (settings == null || !settings.hasKey) return;
    final generation = ++_generation;
    _disposeSession();
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      var conversation = initial ?? await _store.load(id);
      if (conversation == null) {
        conversation = AiConversation.empty(id);
        await _store.save(id, conversation);
      } else {
        await _store.ensureThread(id, conversation);
      }
      await _store.writeActiveThreadId(id);
      final session = await AiChatSession.create(
        database: ref.read(databaseProvider),
        ledgerService: ref.read(ledgerServiceProvider),
        settings: settings,
        initial: conversation,
        approval: _approval,
      );
      if (!mounted || generation != _generation) {
        session.dispose();
        return;
      }
      _session = session;
      _threadId = id;
      _detachStore = attachStore(session.chat, _store, id);
      final threads = await _store.listThreads();
      if (!mounted || generation != _generation) return;
      setState(() {
        _threads = threads;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _newConversation() async {
    if (_session != null && _session!.chat.messages.isEmpty) {
      showAppToast(context, message: '当前已经是新会话');
      return;
    }
    final id = _store.newThreadId();
    await _openThread(id, initial: AiConversation.empty(id));
  }

  Future<void> _openConversationSheet() async {
    await _refreshThreads();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ConversationSheet(
        threads: _threads,
        activeId: _threadId,
        onSelect: (thread) {
          Navigator.of(sheetContext).pop();
          if (thread.id != _threadId) unawaited(_openThread(thread.id));
        },
        onNew: () {
          Navigator.of(sheetContext).pop();
          unawaited(_newConversation());
        },
        onDelete: (thread) {
          Navigator.of(sheetContext).pop();
          unawaited(_deleteThread(thread));
        },
      ),
    );
  }

  Future<void> _deleteThread(ChatThread thread) async {
    final confirmed = await showAppConfirmDialog(
      context,
      message: '删除会话「${thread.title}」？账单数据不会被删除。',
      confirmLabel: '删除会话',
    );
    if (!confirmed || !mounted) return;
    final deletingActive = thread.id == _threadId;
    // 先停掉并关闭当前 controller，再删存储；否则 attachStore 的
    // detach 会在删除之后把当前会话又写回来。
    if (deletingActive) {
      _disposeSession();
      if (mounted) setState(() => _loading = true);
    }
    try {
      await _store.delete(thread.id);
    } on Object catch (error) {
      if (!mounted) return;
      showAppToast(
        context,
        message: '删除会话失败：$error',
        level: AppToastLevel.error,
      );
      await _initialize();
      return;
    }
    if (!mounted) return;
    if (deletingActive) {
      final threads = await _store.listThreads();
      if (threads.isNotEmpty) {
        await _openThread(threads.first.id);
      } else {
        await _newConversation();
      }
    } else {
      await _refreshThreads();
    }
  }

  String _friendlyError(Object error) {
    if (error is LlmAuthException) {
      return 'DeepSeek Key 无效，请到 AI 设置里检查。';
    }
    if (error is LlmRateLimitException) {
      return '请求过于频繁，请稍后再试。';
    }
    if (error is LlmException && error.statusCode == 402) {
      return 'DeepSeek 余额不足，请先充值。';
    }
    if (error is TimeoutException) {
      return '连接超时，请检查网络后重试。';
    }
    final text = error.toString();
    if (text.contains('401')) return 'DeepSeek Key 无效，请到 AI 设置里检查。';
    if (text.contains('402')) return 'DeepSeek 余额不足，请先充值。';
    if (text.contains('429')) return '请求过于频繁，请稍后再试。';
    final short = text.length > 180 ? '${text.substring(0, 180)}…' : text;
    return 'AI 请求失败：$short';
  }

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (_session != null)
        AppHeaderAction(
          icon: FLucideIcons.history,
          tooltip: '会话列表',
          onTap: () => unawaited(_openConversationSheet()),
        ),
      if (_session != null)
        AppHeaderAction(
          icon: FLucideIcons.plus,
          tooltip: '新建会话',
          onTap: () => unawaited(_newConversation()),
        ),
      AppHeaderAction(
        icon: FLucideIcons.settings2,
        tooltip: 'AI 设置',
        onTap: _openSettings,
      ),
    ];
    return Scaffold(
      body: AppTopBar(
        title: 'AI 助手',
        actions: actions,
        slivers: [
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _ErrorView(
                message: _friendlyError(_error!),
                onRetry: _retryInitialize,
                onSettings: _openSettings,
              ),
            )
          else if (_session == null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _SetupView(
                onSetup: _openSettings,
                maskedKey: _settings?.maskedKey,
              ),
            )
          else
            SliverFillRemaining(
              // AiChatView 自带 ListView；这里必须声明「子里有滚动体」，
              // 否则 SliverFillRemaining 会去问 viewport 要 intrinsic height，
              // debug 下直接抛 RenderViewport 不支持 intrinsic dimensions。
              hasScrollBody: true,
              child: _ChatBody(session: _session!, themed: _themed),
            ),
        ],
      ),
    );
  }

  Widget _themed(Widget child) {
    final base = Theme.of(context);
    final colors = context.colors;
    final baseAi = colors.isDark
        ? AiThemeExtension.dark()
        : AiThemeExtension.fallback();
    final aiTheme = baseAi.copyWith(
      userBubbleColor: colors.primary,
      userTextColor: colors.isDark ? colors.canvasBase : Colors.white,
      assistantBubbleColor: colors.surface,
      assistantTextColor: colors.ink,
      chipColor: colors.primarySoft,
      accentColor: colors.primary,
      onAccentColor: colors.isDark ? colors.canvasBase : Colors.white,
      borderColor: colors.lineSoft,
      errorColor: colors.danger,
      successColor: colors.success,
      warningColor: colors.accent,
      linkColor: colors.primary,
      bubbleRadius: context.radii.cardAll,
      bubblePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      messageSpacing: 14,
      textStyle: TextStyle(fontSize: 15.5, height: 1.55, color: colors.ink),
      loaderColor: colors.primary,
      orbColor: colors.primary,
      composerPadding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
    );
    return Theme(
      data: base.copyWith(
        extensions: [
          ...base.extensions.values.where(
            (extension) => extension is! AiThemeExtension,
          ),
          aiTheme,
        ],
      ),
      child: child,
    );
  }
}

class _ChatBody extends StatelessWidget {
  const _ChatBody({required this.session, required this.themed});

  final AiChatSession session;
  final Widget Function(Widget child) themed;

  @override
  Widget build(BuildContext context) {
    return themed(
      ListenableBuilder(
        listenable: session.chat,
        builder: (context, _) {
          final error = session.chat.error;
          return Column(
            children: [
              if (error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: AiErrorBanner(
                    message: _errorText(error),
                    onRetry: () => unawaited(session.chat.regenerate()),
                  ),
                ),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: AiChatView(
                    controller: session.chat,
                    hintText: '问账单，或说「记一笔午饭 28 元」',
                    maxContentWidth: 760,
                    emptyState: _AiWelcome(
                      onSelected: (text) =>
                          unawaited(session.chat.sendText(text)),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _errorText(Object error) {
    if (error is LlmAuthException) {
      return 'DeepSeek Key 无效，请到 AI 设置里检查。';
    }
    if (error is LlmRateLimitException) {
      return '请求过于频繁，请稍后再试。';
    }
    if (error is LlmException && error.statusCode == 402) {
      return 'DeepSeek 余额不足，请先充值。';
    }
    final text = error.toString();
    if (text.contains('401')) return 'DeepSeek Key 无效，请到 AI 设置里检查。';
    if (text.contains('402')) return 'DeepSeek 余额不足，请先充值。';
    if (text.contains('429')) return '请求过于频繁，请稍后再试。';
    return 'AI 请求失败，请稍后重试。';
  }
}

class _SetupView extends StatelessWidget {
  const _SetupView({required this.onSetup, required this.maskedKey});

  final VoidCallback onSetup;
  final String? maskedKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colors.primarySoft,
                borderRadius: context.radii.cardAll,
              ),
              child: Icon(
                FLucideIcons.sparkles,
                size: 30,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '先配置 DeepSeek API Key',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'AI 会读取本地账单来回答问题，也可以帮你记一笔或删账单。'
              'Key 只保存在本机，AI 请求直接发往 DeepSeek。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.55, color: colors.muted),
            ),
            if (maskedKey != null && maskedKey != '未配置') ...[
              const SizedBox(height: 8),
              Text(
                '当前 Key：$maskedKey',
                style: TextStyle(fontSize: 12, color: colors.inactive),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: AppButton(onPress: onSetup, child: const Text('去配置')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onSettings,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FLucideIcons.circleAlert, size: 34, color: colors.danger),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: colors.ink, height: 1.5),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    variant: AppButtonVariant.outline,
                    onPress: onSettings,
                    child: const Text('打开设置'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(onPress: onRetry, child: const Text('重试')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AiWelcome extends StatelessWidget {
  const _AiWelcome({required this.onSelected});

  final ValueChanged<String> onSelected;

  static const _suggestions = <String>[
    '这个月花了多少？',
    '上个月餐饮花了多少？',
    '这个月哪类花得最多？',
    '帮我记一笔午饭 28 元',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(FLucideIcons.sparkles, size: 34, color: colors.primary),
          const SizedBox(height: 14),
          Text(
            '问问你的账本',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: colors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '我会先查本地账单，再回答。记账和删除前都会请你确认。',
            style: TextStyle(fontSize: 14, height: 1.55, color: colors.muted),
          ),
          const SizedBox(height: 22),
          AiSuggestions(
            suggestions: _suggestions,
            layout: AiSuggestionsLayout.grid,
            onSelected: onSelected,
          ),
          const SizedBox(height: 18),
          Text(
            'AI 可能理解错金额或分类，结果仅供参考。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: colors.inactive),
          ),
        ],
      ),
    );
  }
}

/// 会话列表底部浮层。
///
/// 只负责展示和回调；删除确认、切换会话、创建会话都由页面状态层处理，
/// 避免浮层关闭后还在操作已经卸载的 context。
class _ConversationSheet extends StatelessWidget {
  const _ConversationSheet({
    required this.threads,
    required this.activeId,
    required this.onSelect,
    required this.onNew,
    required this.onDelete,
  });

  final List<ChatThread> threads;
  final String? activeId;
  final ValueChanged<ChatThread> onSelect;
  final VoidCallback onNew;
  final ValueChanged<ChatThread> onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: Material(
          color: colors.surface,
          borderRadius: context.radii.sheetTop,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '会话',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: colors.ink,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onNew,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.primary,
                      ),
                      icon: const Icon(FLucideIcons.plus, size: 18),
                      label: const Text('新建'),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: colors.lineSoft),
              Expanded(
                child: threads.isEmpty
                    ? Center(
                        child: Text(
                          '还没有会话',
                          style: TextStyle(color: colors.inactive),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: threads.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          thickness: 1,
                          indent: 20,
                          endIndent: 20,
                          color: colors.lineSoft,
                        ),
                        itemBuilder: (context, index) {
                          final thread = threads[index];
                          final active = thread.id == activeId;
                          return InkWell(
                            onTap: () => onSelect(thread),
                            child: Container(
                              color: active ? colors.primarySoft : null,
                              padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
                              child: Row(
                                children: [
                                  Icon(
                                    FLucideIcons.messageSquare,
                                    size: 20,
                                    color: active
                                        ? colors.primary
                                        : colors.inactive,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          thread.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: active
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                            color: colors.ink,
                                          ),
                                        ),
                                        if (thread.updatedAt != null) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            _threadTime(thread.updatedAt!),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: colors.inactive,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (active)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      child: Icon(
                                        FLucideIcons.check,
                                        size: 17,
                                        color: colors.primary,
                                      ),
                                    ),
                                  IconButton(
                                    onPressed: () => onDelete(thread),
                                    tooltip: '删除会话',
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(
                                      FLucideIcons.trash2,
                                      size: 18,
                                      color: colors.inactive,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _threadTime(DateTime value) {
  final now = DateTime.now();
  final day = dateOnly(value);
  final today = dateOnly(now);
  if (day == today) return '今天 ${formatClock(value)}';
  if (day == today.subtract(const Duration(days: 1))) {
    return '昨天 ${formatClock(value)}';
  }
  if (value.year == now.year) return '${value.month} 月 ${value.day} 日';
  return '${value.year} 年 ${value.month} 月 ${value.day} 日';
}
