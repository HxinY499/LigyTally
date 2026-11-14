import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_theme.dart';

/// 模型的思考。正文还没出来时摊开，正文一开始就收成一行，点开还能再看。
class AiThinkingBlock extends StatefulWidget {
  const AiThinkingBlock({super.key, required this.text, required this.live});

  final String text;

  /// 这一条还在思考、正文还是空的。
  final bool live;

  @override
  State<AiThinkingBlock> createState() => _AiThinkingBlockState();
}

class _AiThinkingBlockState extends State<AiThinkingBlock> {
  late bool _open = widget.live;
  bool _userToggled = false;

  @override
  void didUpdateWidget(AiThinkingBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_userToggled) return;
    if (widget.live != _open) setState(() => _open = widget.live);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final muted = colors.muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: widget.live ? '思考中' : '思考',
          child: InkWell(
            onTap: () => setState(() {
              _userToggled = true;
              _open = !_open;
            }),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FLucideIcons.brain, size: 15, color: muted),
                  const SizedBox(width: 6),
                  Text(
                    widget.live ? '思考中' : '思考',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: muted,
                      height: 1.3,
                    ),
                  ),
                  Icon(
                    _open ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
                    size: 14,
                    color: muted,
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: context.motion(const Duration(milliseconds: 180)),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(left: 21, top: 2, bottom: 4),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Text(
                        widget.text,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          color: colors.ink.withValues(alpha: 0.62),
                        ),
                      ),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
