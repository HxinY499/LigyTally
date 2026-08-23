/// 更新条目的类型。写在 `- ` 后面、正文前面，和正文用一个空格分开。
///
/// 对不上这三类的行不要硬套，不加前缀，浮层仍画原来的点。
enum ReleaseNoteKind {
  feature('功能'),
  fix('修复'),
  improvement('优化');

  const ReleaseNoteKind(this.label);

  final String label;

  static ReleaseNoteKind? tryParse(String label) {
    for (final kind in values) {
      if (kind.label == label) return kind;
    }
    return null;
  }
}

/// 一条更新说明：类型可选，正文已经去掉前缀。
class ReleaseNoteItem {
  const ReleaseNoteItem(this.text, {this.kind});

  final String text;
  final ReleaseNoteKind? kind;
}

/// 把发布说明的 body 解析成更新浮层里要展示的条目。
///
/// 约定格式写在仓库根目录 `发布流程.md`。解析器按那个契约取
/// `## 更新内容` 下面的 `- ` 列表；格式不对时尽量把还能读的行
/// 展示出来，而不是让浮层空白。
List<String> parseReleaseNotes(String? body) => [
  for (final item in parseReleaseNoteItems(body)) item.text,
];

/// 带类型的条目。浮层用这个，纯文本调用方继续用 [parseReleaseNotes]。
List<ReleaseNoteItem> parseReleaseNoteItems(String? body) {
  if (body == null) return const [];
  final trimmed = body.trim();
  if (trimmed.isEmpty) return const [];

  final section = _sectionUnderHeading(trimmed) ?? trimmed;
  final bullets = _bullets(section);
  if (bullets.isNotEmpty) return bullets;

  return [
    for (final line in section.split(RegExp(r'\r?\n')))
      if (_itemFromLine(line) case final item?) item,
  ];
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

List<ReleaseNoteItem> _bullets(String section) {
  final items = <ReleaseNoteItem>[];
  for (final raw in section.split(RegExp(r'\r?\n'))) {
    final match = RegExp(r'^\s*(?:[-*]|\d+[.)])\s+(.+)$').firstMatch(raw);
    if (match == null) continue;
    final item = _itemFromText(_stripInlineMarkdown(match.group(1)!).trim());
    if (item != null) items.add(item);
  }
  return items;
}

ReleaseNoteItem? _itemFromLine(String raw) {
  final text = _stripInlineMarkdown(raw).trim();
  if (text.isEmpty || _isHeading(text)) return null;
  return _itemFromText(text);
}

/// `- 功能 记账时可记录位置` → 类型 + 去掉前缀的正文。
///
/// 只认单独成词的「功能 / 修复 / 优化」。`修复了启动闪退` 这种不算前缀，
/// 整句原样展示，避免把普通句子吞掉第一个词。
ReleaseNoteItem? _itemFromText(String text) {
  if (text.isEmpty) return null;
  final match = RegExp(r'^(功能|修复|优化)\s+(.+)$').firstMatch(text);
  if (match == null) return ReleaseNoteItem(text);
  return ReleaseNoteItem(
    match.group(2)!,
    kind: ReleaseNoteKind.tryParse(match.group(1)!),
  );
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
