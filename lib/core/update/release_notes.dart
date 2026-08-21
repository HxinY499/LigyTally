/// 把发布说明的 body 解析成更新浮层里要展示的条目。
///
/// 约定格式写在仓库根目录 `发布流程.md`。解析器按那个契约取
/// `## 更新内容` 下面的 `- ` 列表；格式不对时尽量把还能读的行
/// 展示出来，而不是让浮层空白。
List<String> parseReleaseNotes(String? body) {
  if (body == null) return const [];
  final trimmed = body.trim();
  if (trimmed.isEmpty) return const [];

  final section = _sectionUnderHeading(trimmed) ?? trimmed;
  final bullets = _bullets(section);
  if (bullets.isNotEmpty) return bullets;

  return section
      .split(RegExp(r'\r?\n'))
      .map(_stripInlineMarkdown)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !_isHeading(line))
      .toList(growable: false);
}

String? _sectionUnderHeading(String body) {
  final lines = body.split(RegExp(r'\r?\n'));
  var start = -1;
  for (var i = 0; i < lines.length; i++) {
    if (RegExp(r'^#{1,3}\s*更新内容\s*$').hasMatch(lines[i].trim())) {
      start = i + 1;
      break;
    }
  }
  if (start < 0) return null;

  final buf = <String>[];
  for (var i = start; i < lines.length; i++) {
    if (_isHeading(lines[i].trim())) break;
    buf.add(lines[i]);
  }
  final section = buf.join('\n').trim();
  return section.isEmpty ? null : section;
}

List<String> _bullets(String section) {
  final items = <String>[];
  for (final raw in section.split(RegExp(r'\r?\n'))) {
    final match = RegExp(r'^\s*(?:[-*]|\d+[.)])\s+(.+)$').firstMatch(raw);
    if (match == null) continue;
    final text = _stripInlineMarkdown(match.group(1)!).trim();
    if (text.isNotEmpty) items.add(text);
  }
  return items;
}

bool _isHeading(String line) => RegExp(r'^#{1,6}\s+\S').hasMatch(line);

/// 去掉发布说明里偶尔带上的行内标记，浮层按纯文本展示。
String _stripInlineMarkdown(String input) {
  var text = input;
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (match) => match.group(1)!,
  );
  text = text.replaceAllMapped(
    RegExp(r'\*\*(.+?)\*\*|__(.+?)__'),
    (match) => match.group(1) ?? match.group(2)!,
  );
  text = text.replaceAllMapped(
    RegExp(r'`([^`]+)`'),
    (match) => match.group(1)!,
  );
  text = text.replaceAllMapped(
    RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)'),
    (match) => match.group(1)!,
  );
  return text;
}
