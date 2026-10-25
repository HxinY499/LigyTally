import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_elements/flutter_ai_elements.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/app_theme.dart';

const _zh = AiLocalizations(
  send: '发送',
  stop: '停止',
  retry: '重试',
  dismiss: '关闭',
  thinking: '正在思考',
  you: '你',
  assistant: '助手',
  toolArguments: '参数',
  toolResult: '结果',
  toolError: '错误',
  scrollToLatest: '回到最新',
);

/// 聊天记录 + 输入框。
///
/// 列表反向排：偏移 0 就是最新一条，贴在输入框上方。
/// 键盘把视口压矮时，最新内容仍留在输入框之上，不会整段被顶到标题后面。
///
/// 不用 [AiChat] 的自动滚动。那套把刚发出的问题钉在视口顶部，
/// 并在下面垫一块空白；手机上键盘开着时，输入框上方看到的就是这块空白。
class AiChatPane extends StatefulWidget {
  const AiChatPane({
    super.key,
    required this.controller,
    this.empty,
    this.banner,
    this.hintText = '问账单，或说「记一笔午饭 28 元」',
  });

  final UseChatController controller;
  final Widget? empty;

  /// 放在记录上方、输入框同一列里。错误条走这里，才能用到本页的中文文案。
  final Widget? banner;
  final String hintText;

  @override
  State<AiChatPane> createState() => _AiChatPaneState();
}

class _AiChatPaneState extends State<AiChatPane> {
  final ScrollController _scroll = ScrollController();
  late int _messageCount = widget.controller.messages.length;
  ChatStatus? _status;

  /// 用户往上翻过这段距离后，才给出「回到最新」。
  bool _showJump = false;

  @override
  void initState() {
    super.initState();
    _status = widget.controller.status;
    widget.controller.addListener(_onChat);
  }

  @override
  void didUpdateWidget(AiChatPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onChat);
    widget.controller.addListener(_onChat);
    _messageCount = widget.controller.messages.length;
    _status = widget.controller.status;
    _showJump = false;
    _revealLatest();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChat);
    _scroll.dispose();
    super.dispose();
  }

  void _onChat() {
    final status = widget.controller.status;
    final wasBusy = _status?.isBusy ?? false;
    if (wasBusy && !status.isBusy && mounted) _haptic();
    _status = status;

    final messages = widget.controller.messages;
    final sentByUser =
        messages.length > _messageCount &&
        messages.isNotEmpty &&
        messages.last.role == AiRole.user;
    _messageCount = messages.length;
    if (sentByUser) _revealLatest();
  }

  void _haptic() {
    final theme = AiThemeExtension.of(context);
    if (!theme.enableHaptics || kIsWeb) return;
    final platform = defaultTargetPlatform;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.android) {
      unawaited(HapticFeedback.lightImpact());
    }
  }

  /// 用户在看历史时发出新消息，把视口拉回最新一条。
  /// 已经贴在底部时反向列表自己会把新内容留在输入框上方，不必再滚。
  void _revealLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_scroll.position.pixels <= 1) return;
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final show = notification.metrics.pixels > 280;
    if (show != _showJump) setState(() => _showJump = show);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return AiLocalizationsScope(
      strings: _zh,
      child: Column(
        children: [
          if (widget.banner != null) widget.banner!,
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: media.padding.left,
                right: media.padding.right,
              ),
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) => _transcript(),
              ),
            ),
          ),
          _ComposerDock(
            child: AiPromptInput(
              controller: widget.controller,
              hintText: widget.hintText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _transcript() {
    final messages = widget.controller.messages;
    final showLoader = widget.controller.status == ChatStatus.submitted;
    if (widget.empty != null &&
        messages.isEmpty &&
        !showLoader &&
        !widget.controller.status.isBusy) {
      return widget.empty!;
    }

    final list = ListView.builder(
      controller: _scroll,
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: AlwaysScrollableScrollPhysics(
        parent: ScrollConfiguration.of(context).getScrollPhysics(context),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      itemCount: messages.length + (showLoader ? 1 : 0),
      itemBuilder: (context, index) {
        if (showLoader && index == 0) {
          return const Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: AiLoader(),
            ),
          );
        }
        final fromBottom = showLoader ? index - 1 : index;
        final message = messages[messages.length - 1 - fromBottom];
        return AiMessageBubble(key: ValueKey(message.id), message: message);
      },
    );

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          // 把堆叠撑满视口。短对话若被收缩到内容高度，反向列表会贴着标题，
          // 而不是贴着输入框。
          const SizedBox.expand(),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: list,
              ),
            ),
          ),
          if (_showJump && messages.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Center(child: _JumpToLatest(onTap: _jumpToLatest)),
            ),
        ],
      ),
    );
  }

  void _jumpToLatest() {
    if (!_scroll.hasClients) return;
    unawaited(
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

class _JumpToLatest extends StatelessWidget {
  const _JumpToLatest({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: '回到最新',
      child: Material(
        color: colors.surface,
        shape: CircleBorder(side: BorderSide(color: colors.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: 36,
            child: Icon(FLucideIcons.arrowDown, size: 18, color: colors.ink),
          ),
        ),
      ),
    );
  }
}

/// 输入框停在键盘上方。系统键盘弹起时不再额外垫底部安全区，避免把正文顶出屏幕。
class _ComposerDock extends StatelessWidget {
  const _ComposerDock({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: context.colors.lineSoft, width: 0.6),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: media.padding.left,
          right: media.padding.right,
          bottom: keyboard > 0 ? 0 : media.padding.bottom,
        ),
        child: child,
      ),
    );
  }
}
