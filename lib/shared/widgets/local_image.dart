import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../core/media/image_storage.dart';
import '../../core/theme/app_theme.dart';

class LocalImage extends StatefulWidget {
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
  State<LocalImage> createState() => _LocalImageState();
}

class _LocalImageState extends State<LocalImage> {
  late Future<File?> _file;

  @override
  void initState() {
    super.initState();
    _file = _resolve();
  }

  @override
  void didUpdateWidget(LocalImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relativePath != widget.relativePath ||
        oldWidget.storage != widget.storage) {
      _file = _resolve();
    }
  }

  Future<File?> _resolve() async {
    final file = await widget.storage.resolve(widget.relativePath);
    return await file.exists() ? file : null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FutureBuilder<File?>(
      future: _file,
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
          fit: widget.fit,
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
