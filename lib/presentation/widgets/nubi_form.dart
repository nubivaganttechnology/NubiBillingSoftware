import 'package:flutter/material.dart';

/// Shared form language. Uses the application's existing color scheme.
class NubiFormTheme extends StatelessWidget {
  const NubiFormTheme({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
    );
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: theme.colorScheme.surface,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          constraints: const BoxConstraints(minHeight: 56),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
          ),
          labelStyle: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      child: child,
    );
  }
}

class NubiFormColumn extends StatelessWidget {
  const NubiFormColumn({super.key, required this.children, this.gap = 18});
  final List<Widget> children;
  final double gap;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) SizedBox(height: gap),
        children[i],
      ],
    ],
  );
}

/// Marks controls such as chip groups and descriptions as full width.
class NubiWideField extends StatelessWidget {
  const NubiWideField({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

class NubiFieldGrid extends StatelessWidget {
  const NubiFieldGrid({
    super.key,
    required this.children,
    this.breakpoint = 620,
  });
  final List<Widget> children;
  final double breakpoint;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final two = bounds.maxWidth >= breakpoint;
      return Wrap(
        spacing: 20,
        runSpacing: 20,
        children: [
          for (final child in children)
            SizedBox(
              width: two && child is! NubiWideField
                  ? (bounds.maxWidth - 20) / 2
                  : bounds.maxWidth,
              child: child,
            ),
        ],
      );
    },
  );
}

class NubiFormSection extends StatelessWidget {
  const NubiFormSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title, subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: EdgeInsets.all(bounds.maxWidth < 600 ? 16 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              child,
            ],
          ),
        ),
      ),
    ),
  );
}

class NubiVariantCard extends StatelessWidget {
  const NubiVariantCard({
    super.key,
    required this.title,
    required this.child,
    required this.onDuplicate,
    this.onRemove,
  });
  final String title;
  final Widget child;
  final VoidCallback onDuplicate;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 24),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: NubiFormColumn(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Duplicate variant',
              onPressed: onDuplicate,
              icon: const Icon(Icons.copy_outlined, size: 20),
            ),
            if (onRemove != null)
              IconButton(
                tooltip: 'Remove unsaved variant',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
          ],
        ),
        child,
      ],
    ),
  );
}

class NubiImagePicker extends StatelessWidget {
  const NubiImagePicker({
    super.key,
    required this.preview,
    required this.hasImage,
    required this.onPaste,
    required this.onRemove,
  });
  final Widget preview;
  final bool hasImage;
  final VoidCallback onPaste, onRemove;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final actions = NubiFormColumn(
        gap: 12,
        children: [
          Text(
            hasImage ? 'Product preview' : 'No product image',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            hasImage
                ? 'You can replace or remove this image at any time.'
                : 'Add an image to make the product easier to identify.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const Tooltip(
                message: 'Image upload is currently unavailable.',
                child: OutlinedButton(
                  onPressed: null,
                  child: Text('Choose Image'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onPaste,
                icon: const Icon(Icons.link, size: 18),
                label: Text(hasImage ? 'Replace' : 'Paste URL'),
              ),
              const Tooltip(
                message: 'Image search is currently unavailable.',
                child: OutlinedButton(
                  onPressed: null,
                  child: Text('Find Image'),
                ),
              ),
              if (hasImage)
                TextButton(onPressed: onRemove, child: const Text('Remove')),
            ],
          ),
        ],
      );
      final image = SizedBox(width: 180, height: 160, child: preview);
      return bounds.maxWidth >= 620
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                image,
                const SizedBox(width: 28),
                Expanded(child: actions),
              ],
            )
          : NubiFormColumn(
              children: [
                Align(alignment: Alignment.centerLeft, child: image),
                actions,
              ],
            );
    },
  );
}
