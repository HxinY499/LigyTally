import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../core/media/image_storage.dart';
import '../../core/theme/app_theme.dart';

class LocalImage extends StatelessWidget {
  const LocalImage({
    super.key,
    required this.storage,
    required this.relativePath,
    this.fit = BoxFit.cover,
  });

  final ImageStorage storage;
  final String relativePath;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FutureBuilder<File>(
      future: storage.resolve(relativePath),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) {
          return ColoredBox(
            color: colors.fill,
            child: const Center(child: Icon(FLucideIcons.image)),
          );
        }
        return Image.file(
          file,
          fit: fit,
          errorBuilder: (_, _, _) {
            return ColoredBox(
              color: colors.fill,
              child: const Center(child: Icon(FLucideIcons.imageOff)),
            );
          },
        );
      },
    );
  }
}
