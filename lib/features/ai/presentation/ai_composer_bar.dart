import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_client/flutter_ai_client.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../application/ai_platform.dart';
import 'ai_platform_logo.dart';

/// 底部输入条。
///
/// 没焦点时保持一行：附件、输入、发送。获得焦点、已经有图、或者草稿写长了，
/// 上半截变成纯输入区，两个按钮下移，附件右边才出现模型。
class AiComposerBar extends StatefulWidget {
  const AiComposerBar({
    super.key,
    required this.controller,
    this.hintText = '问问账本',
    this.onPickAttachment,
    this.model,
    this.onPickModel,
    this.reasoningLabel,
    this.onPickReasoning,
  });

  final UseChatController controller;
  final String hintText;
  final Future<List<FilePart>> Function()? onPickAttachment;
  final String? model;
  final VoidCallback? onPickModel;
  final String? reasoningLabel;
  final VoidCallback? onPickReasoning;

  @override
  State<AiComposerBar> createState() => _AiComposerBarState();
}

class _AiComposerBarState extends State<AiComposerBar> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final GlobalKey _fieldKey = GlobalKey();
  final List<FilePart> _attachments = [];

  @override
  void initState() {
    super.initState();
    _focus.addListener(_rebuild);
    _text.addListener(_rebuild);
  }

  @override
  void dispose() {
    _focus.removeListener(_rebuild);
    _text.removeListener(_rebuild);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  bool get _expanded {
    if (_focus.hasFocus || _attachments.isNotEmpty) return true;
    final text = _text.text;
    return text.contains('\n') || text.trim().length > 48;
  }

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    if (widget.controller.status.isBusy) return;
    unawaited(HapticFeedback.lightImpact());
    final staged = List<FilePart>.of(_attachments);
    setState(_attachments.clear);
    _text.clear();
    unawaited(widget.controller.sendText(text, attachments: staged));
  }

  void _stop() {
    unawaited(HapticFeedback.mediumImpact());
    widget.controller.stop();
  }

  Future<void> _pick() async {
    final picked = await widget.onPickAttachment?.call();
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _attachments.addAll(picked));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final busy = widget.controller.status.isBusy;
        final expanded = _expanded;
        final canSend =
            !busy && (_text.text.trim().isNotEmpty || _attachments.isNotEmpty);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_attachments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _AttachmentStrip(
                    files: _attachments,
                    onRemove: (file) =>
                        setState(() => _attachments.remove(file)),
                  ),
                ),
              AnimatedSize(
                duration: context.motion(const Duration(milliseconds: 180)),
                curve: Curves.easeOutCubic,
                alignment: Alignment.bottomCenter,
                child: AnimatedContainer(
                  duration: context.motion(const Duration(milliseconds: 180)),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(expanded ? 22 : 26),
                    border: Border.all(
                      color: expanded && _focus.hasFocus
                          ? colors.primary.withValues(alpha: 0.45)
                          : colors.lineSoft,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                  child: expanded
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                              child: _field(expanded: true),
                            ),
                            Row(
                              children: [
                                _attachButton(),
                                if (widget.model != null &&
                                    widget.onPickModel != null)
                                  _ModelChip(
                                    model: widget.model!,
                                    onTap: widget.onPickModel!,
                                  ),
                                if (widget.reasoningLabel != null &&
                                    widget.onPickReasoning != null)
                                  _ReasoningChip(
                                    label: widget.reasoningLabel!,
                                    onTap: widget.onPickReasoning!,
                                  ),
                                const Spacer(),
                                _SendButton(
                                  busy: busy,
                                  enabled: busy || canSend,
                                  onSend: _send,
                                  onStop: _stop,
                                ),
                              ],
                            ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _attachButton(),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  start: 2,
                                ),
                                child: _field(expanded: false),
                              ),
                            ),
                            _SendButton(
                              busy: busy,
                              enabled: busy || canSend,
                              onSend: _send,
                              onStop: _stop,
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _field({required bool expanded}) {
    final colors = context.colors;
    return TextField(
      key: _fieldKey,
      controller: _text,
      focusNode: _focus,
      minLines: expanded ? 2 : 1,
      maxLines: expanded ? 8 : 1,
      textInputAction: expanded
          ? TextInputAction.newline
          : TextInputAction.send,
      onSubmitted: expanded ? null : (_) => _send(),
      cursorColor: colors.primary,
      style: TextStyle(fontSize: 16, height: 1.45, color: colors.ink),
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: TextStyle(
          fontSize: 16,
          height: 1.45,
          color: colors.ink.withValues(alpha: 0.38),
        ),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }

  Widget _attachButton() {
    if (widget.onPickAttachment == null) return const SizedBox.shrink();
    final colors = context.colors;
    return IconButton(
      onPressed: () => unawaited(_pick()),
      tooltip: '上传图片',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      icon: Icon(Icons.add, size: 24, color: colors.muted),
    );
  }
}

class _ModelChip extends StatelessWidget {
  const _ModelChip({required this.model, required this.onTap});

  final String model;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: '切换模型',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AiPlatformLogo(
                aiModelById(model)?.platform ?? AiPlatform.deepseek,
                size: 16,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: Text(
                  model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.muted,
                  ),
                ),
              ),
              Icon(FLucideIcons.chevronDown, size: 14, color: colors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasoningChip extends StatelessWidget {
  const _ReasoningChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final muted = label == '关' ? colors.inactive : colors.muted;
    return Tooltip(
      message: '思考强度',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FLucideIcons.brain, size: 14, color: muted),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
              Icon(FLucideIcons.chevronDown, size: 14, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.busy,
    required this.enabled,
    required this.onSend,
    required this.onStop,
  });

  final bool busy;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconColor = colors.isDark ? colors.canvasBase : Colors.white;
    return Tooltip(
      message: busy ? '停止' : '发送',
      child: Material(
        color: enabled
            ? colors.primary
            : colors.primary.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: !enabled
              ? null
              : busy
              ? onStop
              : onSend,
          child: SizedBox.square(
            dimension: 38,
            child: Icon(
              busy ? Icons.stop_rounded : Icons.arrow_upward_rounded,
              size: 20,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentStrip extends StatelessWidget {
  const _AttachmentStrip({required this.files, required this.onRemove});

  final List<FilePart> files;
  final ValueChanged<FilePart> onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final file in files)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: file.bytes != null
                          ? Image.memory(file.bytes!, fit: BoxFit.cover)
                          : ColoredBox(color: colors.primarySoft),
                    ),
                  ),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Material(
                      color: colors.ink,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onRemove(file),
                        customBorder: const CircleBorder(),
                        child: const SizedBox.square(
                          dimension: 18,
                          child: Icon(
                            Icons.close,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
