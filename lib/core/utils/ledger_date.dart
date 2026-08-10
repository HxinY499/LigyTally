import 'package:intl/intl.dart';

class LedgerDateRange {
  const LedgerDateRange(this.start, this.endExclusive);

  final DateTime start;
  final DateTime endExclusive;

  int get dayCount => endExclusive.difference(start).inDays;
}

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String dateKey(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

DateTime dateFromKey(String value) => DateTime.parse(value);

LedgerDateRange dayRange(DateTime anchor) {
  final start = dateOnly(anchor);
  return LedgerDateRange(start, start.add(const Duration(days: 1)));
}

LedgerDateRange weekRange(DateTime anchor) {
  final day = dateOnly(anchor);
  final start = day.subtract(Duration(days: day.weekday - DateTime.monday));
  return LedgerDateRange(start, start.add(const Duration(days: 7)));
}

LedgerDateRange monthRange(DateTime anchor) {
  final start = DateTime(anchor.year, anchor.month);
  return LedgerDateRange(start, DateTime(anchor.year, anchor.month + 1));
}

LedgerDateRange yearRange(DateTime anchor) {
  final start = DateTime(anchor.year);
  return LedgerDateRange(start, DateTime(anchor.year + 1));
}

String formatMonth(DateTime value) => '${value.year} 年 ${value.month} 月';

String formatDay(DateTime value) => '${value.month} 月 ${value.day} 日';

String formatWeekday(DateTime value) {
  const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  return '周${weekdays[value.weekday - 1]}';
}

String formatClock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String formatMoney(int cents, {bool signed = false, bool grouped = true}) {
  final sign = cents < 0 ? '-' : (signed && cents > 0 ? '+' : '');
  final absolute = cents.abs();
  final yuan = absolute ~/ 100;
  final fraction = absolute % 100;
  final yuanText = grouped ? _groupInt(yuan) : yuan.toString();
  return '$sign¥$yuanText.${fraction.toString().padLeft(2, '0')}';
}

/// 千分位分组：`19042` → `19,042`。仅处理非负整数字符串。
String _groupInt(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  final length = raw.length;
  for (var i = 0; i < length; i++) {
    if (i > 0 && (length - i) % 3 == 0) buffer.write(',');
    buffer.write(raw[i]);
  }
  return buffer.toString();
}
