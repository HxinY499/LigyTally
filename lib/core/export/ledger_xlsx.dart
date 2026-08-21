import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';

import '../media/image_storage.dart';

/// 一笔账单要写进 Excel 的一行。字段都是可跨 isolate 发送的。
typedef LedgerXlsxRow = ({
  String kind,
  String amount,
  String category,
  String date,
  String time,
  String location,
  String note,
  int imageCount,
  List<LedgerXlsxImage?> images,
});

typedef LedgerXlsxImage = ({Uint8List bytes, int width, int height});

/// 表格里图片预览的最长边（像素）。原图字节仍整份嵌进去，格子里只缩到能看清。
const _kPreview = 80;

/// 把账单编成 .xlsx 字节。调用方应放在 [Isolate.run] 里跑——编表和 zip
/// 都是 CPU 活，放主 isolate 会把设置页的转圈卡住。
Uint8List encodeLedgerXlsx(List<LedgerXlsxRow> rows) {
  final excel = Excel.createExcel();
  final defaultName = excel.getDefaultSheet() ?? 'Sheet1';
  if (defaultName != '账单') {
    excel.rename(defaultName, '账单');
  }
  final sheet = excel['账单'];
  const headers = [
    '类型',
    '金额',
    '分类',
    '日期',
    '时间',
    '地点',
    '备注',
    '图片数量',
  ];
  for (var col = 0; col < headers.length; col++) {
    _text(sheet, col, 0, headers[col]);
  }
  for (var i = 0; i < kMaxTransactionImages; i++) {
    _text(sheet, headers.length + i, 0, '图片${i + 1}');
    sheet.setColumnWidth(headers.length + i, 12);
  }

  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    final excelRow = r + 1;
    _text(sheet, 0, excelRow, row.kind);
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: excelRow),
      DoubleCellValue(double.parse(row.amount)),
    );
    _text(sheet, 2, excelRow, row.category);
    _text(sheet, 3, excelRow, row.date);
    _text(sheet, 4, excelRow, row.time);
    _text(sheet, 5, excelRow, row.location);
    _text(sheet, 6, excelRow, row.note);
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: excelRow),
      IntCellValue(row.imageCount),
    );
    var hasImage = false;
    for (var i = 0; i < kMaxTransactionImages; i++) {
      final image = i < row.images.length ? row.images[i] : null;
      if (image == null) continue;
      hasImage = true;
      final (width, height) = _previewSize(image.width, image.height);
      sheet.insertImage(
        image.bytes,
        anchor: CellIndex.indexByColumnRow(
          columnIndex: headers.length + i,
          rowIndex: excelRow,
        ),
        width: width,
        height: height,
      );
    }
    if (hasImage) {
      // Excel 行高是磅。80px @ 96dpi ≈ 60pt，略留一点上下空隙。
      sheet.setRowHeight(excelRow, 64);
    }
  }

  final bytes = excel.encode();
  if (bytes == null) {
    throw StateError('导出表格失败');
  }
  return Uint8List.fromList(bytes);
}

void _text(Sheet sheet, int col, int row, String value) {
  sheet.updateCell(
    CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    TextCellValue(value),
  );
}

(int, int) _previewSize(int width, int height) {
  if (width <= 0 || height <= 0) return (_kPreview, _kPreview);
  if (width >= height) {
    return (_kPreview, (_kPreview * height / width).round().clamp(1, _kPreview));
  }
  return ((_kPreview * width / height).round().clamp(1, _kPreview), _kPreview);
}
