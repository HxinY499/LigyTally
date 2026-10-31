import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_ai_elements/flutter_ai_elements.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:forui/forui.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_widgets.dart';

const _maxImages = 4;
const _maxBytes = 300 * 1024;

/// 选图、压成 JPEG，再交给输入框暂存。
///
/// 会话存在 SharedPreferences 里，原图的 base64 会把这条记录撑爆，
/// 所以这里压到 1024 边、单张不超过 300KB。
Future<List<FilePart>> pickChatImages(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final colors = sheetContext.colors;
      return SafeArea(
        child: Material(
          color: colors.surface,
          borderRadius: sheetContext.radii.sheetTop,
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(FLucideIcons.camera, color: colors.ink),
                title: const Text('拍照'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(FLucideIcons.images, color: colors.ink),
                title: const Text('从相册选择'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (source == null || !context.mounted) return const [];

  final picker = ImagePicker();
  final List<XFile> picked;
  if (source == ImageSource.camera) {
    final shot = await picker.pickImage(source: source, imageQuality: 90);
    picked = [?shot];
  } else {
    picked = await picker.pickMultiImage(imageQuality: 90, limit: _maxImages);
  }
  if (!context.mounted || picked.isEmpty) return const [];

  final files = picked.take(_maxImages).toList();
  if (picked.length > files.length) {
    showAppToast(context, message: '一次最多 $_maxImages 张');
  }

  final parts = <FilePart>[];
  for (final file in files) {
    final bytes = await _compress(file);
    if (!context.mounted) return parts;
    if (bytes == null) {
      showAppToast(context, message: '有一张图片处理失败', level: AppToastLevel.error);
      continue;
    }
    if (bytes.length > _maxBytes) {
      showAppToast(context, message: '有一张图片仍然太大，没有添加');
      continue;
    }
    parts.add(
      FilePart(
        mediaType: 'image/jpeg',
        bytes: bytes,
        name: _jpegName(file.name),
      ),
    );
  }
  return parts;
}

Future<Uint8List?> _compress(XFile file) async {
  var bytes = await FlutterImageCompress.compressWithFile(
    file.path,
    minWidth: 1024,
    minHeight: 1024,
    quality: 60,
    format: CompressFormat.jpeg,
    keepExif: false,
  );
  if (bytes != null && bytes.length > _maxBytes) {
    bytes = await FlutterImageCompress.compressWithFile(
      file.path,
      minWidth: 768,
      minHeight: 768,
      quality: 40,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
  }
  if (bytes == null || bytes.isEmpty) return null;
  return bytes;
}

String _jpegName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'image.jpg';
  final dot = trimmed.lastIndexOf('.');
  final stem = dot <= 0 ? trimmed : trimmed.substring(0, dot);
  return '$stem.jpg';
}
