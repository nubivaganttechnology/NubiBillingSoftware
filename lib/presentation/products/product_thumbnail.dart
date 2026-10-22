import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Bounded, clipped product image. Network URLs, local files and bundled assets
/// are supported; anything null, empty, malformed or failing to load shows the
/// same placeholder so rows keep a constant height.
class ProductThumbnail extends StatelessWidget {
  const ProductThumbnail({
    super.key,
    required this.url,
    required this.name,
    this.editor = false,
  });
  final String? url;
  final String name;
  final bool editor;

  static const double _size = 52;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = editor ? 180.0 : _size;
    final height = editor ? 160.0 : _size;
    final placeholder = Container(
      key: const ValueKey('product-image-placeholder'),
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: editor
          ? const Icon(Icons.image_outlined, size: 48)
          : Text(
              name.trim().isEmpty
                  ? '?'
                  : name.trim().characters.first.toUpperCase(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
    );
    final value = (url ?? '').trim();
    Widget image = placeholder;
    if (value.isNotEmpty) {
      final uri = Uri.tryParse(value);
      if (uri != null &&
          {'http', 'https'}.contains(uri.scheme) &&
          uri.host.isNotEmpty) {
        image = Image.network(
          value,
          fit: BoxFit.contain,
          width: width,
          height: height,
          errorBuilder: (_, _, _) => placeholder,
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : editor
              ? const Center(child: CircularProgressIndicator())
              : placeholder,
        );
      } else if (value.startsWith('assets/')) {
        image = Image.asset(
          value,
          fit: BoxFit.contain,
          width: width,
          height: height,
          errorBuilder: (_, _, _) => placeholder,
        );
      } else if (!kIsWeb &&
          (uri?.scheme == 'file' ||
              value.startsWith('/') ||
              RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value))) {
        final path = uri != null && uri.scheme == 'file'
            ? uri.toFilePath()
            : value;
        image = Image.file(
          File(path),
          fit: BoxFit.contain,
          width: width,
          height: height,
          errorBuilder: (_, _, _) => placeholder,
        );
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        key: const ValueKey('product-image-box'),
        width: width,
        height: height,
        child: image,
      ),
    );
  }
}
