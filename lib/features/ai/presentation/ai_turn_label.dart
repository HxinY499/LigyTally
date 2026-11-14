import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../application/ai_turn_format.dart';

/// 助手回复顶部的用时。进行中的那一轮自己走表，结束以后用记下来的毫秒数。
class AiTurnLabel extends StatefulWidget {
  const AiTurnLabel({super.key, this.fixedMs, this.startedAt});

  final int? fixedMs;
  final DateTime? startedAt;

  @override
  State<AiTurnLabel> createState() => _AiTurnLabelState();
}

class _AiTurnLabelState extends State<AiTurnLabel> {
  Timer? _timer;

  bool get _live => widget.fixedMs == null && widget.startedAt != null;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(AiTurnLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_live && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted) setState(() {});
      });
      return;
    }
    if (!_live) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final started = widget.startedAt;
    final ms =
        widget.fixedMs ??
        (started == null
            ? null
            : DateTime.now().difference(started).inMilliseconds);
    if (ms == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        formatTurnDuration(Duration(milliseconds: ms)),
        style: TextStyle(
          fontSize: 12,
          height: 1.3,
          color: context.colors.inactive,
        ),
      ),
    );
  }
}
