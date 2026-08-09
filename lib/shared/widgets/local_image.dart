import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../core/media/image_storage.dart';

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
    return FutureBuilder<File>(
      future: storage.resolve(relativePath),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) {
          return const ColoredBox(
            color: Color(0xFFE7ECE9),
            child: Center(child: Icon(FLucideIcons.image)),
          );
        }
        return Image.file(
          file,
          fit: fit,
          errorBuilder: (_, _, _) {
            return const ColoredBox(
              color: Color(0xFFE7ECE9),
              child: Center(child: Icon(FLucideIcons.imageOff)),
            );
          },
        );
      },
    );
  }
}
