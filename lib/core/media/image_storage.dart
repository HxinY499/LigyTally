import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StoredImage {
  const StoredImage({
    required this.imagePath,
    required this.thumbnailPath,
    required this.width,
    required this.height,
    required this.sizeBytes,
  });

  final String imagePath;
  final String thumbnailPath;
  final int width;
  final int height;
  final int sizeBytes;
}

class ImageStorage {
  Future<Directory> _root() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'media'));
    await root.create(recursive: true);
    return root;
  }

  Future<StoredImage> store({
    required XFile source,
    required String transactionId,
    required String imageId,
  }) async {
    final root = await _root();
    final directory = Directory(p.join(root.path, transactionId));
    await directory.create(recursive: true);

    final imageFile = File(p.join(directory.path, '$imageId.jpg'));
    final thumbnailFile = File(p.join(directory.path, '${imageId}_thumb.jpg'));
    final compressed = await FlutterImageCompress.compressAndGetFile(
      source.path,
      imageFile.path,
      minWidth: 2048,
      minHeight: 2048,
      quality: 85,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    if (compressed == null) {
      throw StateError('图片压缩失败');
    }

    final thumbnail = await FlutterImageCompress.compressAndGetFile(
      compressed.path,
      thumbnailFile.path,
      minWidth: 320,
      minHeight: 320,
      quality: 76,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    if (thumbnail == null) {
      await imageFile.delete();
      throw StateError('缩略图生成失败');
    }

    final bytes = await imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final support = await getApplicationSupportDirectory();
    final result = StoredImage(
      imagePath: p.relative(imageFile.path, from: support.path),
      thumbnailPath: p.relative(thumbnailFile.path, from: support.path),
      width: frame.image.width,
      height: frame.image.height,
      sizeBytes: await imageFile.length(),
    );
    frame.image.dispose();
    codec.dispose();
    return result;
  }

  Future<File> resolve(String relativePath) async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, relativePath));
  }

  Future<void> deleteFile(String relativePath) async {
    final file = await resolve(relativePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> deleteTransactionDirectory(String transactionId) async {
    final root = await _root();
    final directory = Directory(p.join(root.path, transactionId));
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
