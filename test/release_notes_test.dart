import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/update/release_notes.dart';

void main() {
  group('parseReleaseNotes', () {
    test('按发布流程约定取出更新内容列表', () {
      const body = '''
## 更新内容

- 记账时可记录位置，点一下获取当前地点
- 设置里可打开「记账时自动记录位置」，仅对今天的新建账单生效
''';
      expect(parseReleaseNotes(body), [
        '记账时可记录位置，点一下获取当前地点',
        '设置里可打开「记账时自动记录位置」，仅对今天的新建账单生效',
      ]);
    });

    test('空 body 得到空列表，浮层不应崩溃', () {
      expect(parseReleaseNotes(null), isEmpty);
      expect(parseReleaseNotes(''), isEmpty);
      expect(parseReleaseNotes('   \n'), isEmpty);
    });

    test('只有标题没有条目时为空', () {
      expect(parseReleaseNotes('## 更新内容\n\n'), isEmpty);
    });

    test('标题后面出现下一个标题时截断', () {
      const body = '''
## 更新内容

- 第一条

## 安装

请自行下载 APK
''';
      expect(parseReleaseNotes(body), ['第一条']);
    });

    test('没有约定标题时仍尽量取出列表', () {
      const body = '''
- 记账时可记录位置
- 地点可改成店名
''';
      expect(parseReleaseNotes(body), ['记账时可记录位置', '地点可改成店名']);
    });

    test('去掉行内 markdown，浮层按纯文本展示', () {
      const body = '''
## 更新内容

- 打开 **自动记录位置**
- 详见 [说明](https://example.com)
- 分类名用 `餐饮`
''';
      expect(parseReleaseNotes(body), [
        '打开 自动记录位置',
        '详见 说明',
        '分类名用 餐饮',
      ]);
    });

    test('没有列表时按非空行展示，兼容旧 Release', () {
      expect(parseReleaseNotes('修了启动时偶发闪退'), ['修了启动时偶发闪退']);
    });

    test('行首的功能、修复、优化被收成类型，正文不再带前缀', () {
      const body = '''
## 更新内容

- 功能 记账时可记录位置
- 修复 统计页金额不再折行
- 优化 预置风格改成适中密度
- 安装包暂时从 GitHub 下载
''';
      final items = parseReleaseNoteItems(body);
      expect(items.map((item) => item.kind).toList(), [
        ReleaseNoteKind.feature,
        ReleaseNoteKind.fix,
        ReleaseNoteKind.improvement,
        null,
      ]);
      expect(items.map((item) => item.text).toList(), [
        '记账时可记录位置',
        '统计页金额不再折行',
        '预置风格改成适中密度',
        '安装包暂时从 GitHub 下载',
      ]);
      expect(parseReleaseNotes(body), [
        '记账时可记录位置',
        '统计页金额不再折行',
        '预置风格改成适中密度',
        '安装包暂时从 GitHub 下载',
      ]);
    });

    test('修复了启动闪退不算类型前缀，整句留下', () {
      expect(
        parseReleaseNoteItems('## 更新内容\n\n- 修复了启动时偶发闪退').single.kind,
        isNull,
      );
      expect(
        parseReleaseNotes('## 更新内容\n\n- 修复了启动时偶发闪退'),
        ['修复了启动时偶发闪退'],
      );
    });
  });
}
