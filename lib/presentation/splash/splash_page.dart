import 'package:flutter/material.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});
  @override
  Widget build(BuildContext c) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [_Brand(), SizedBox(height: 30), CircularProgressIndicator()],
    ),
  );
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext c) => Column(
    children: [
      Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: Theme.of(c).colorScheme.primary,
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Icon(
          Icons.storefront_rounded,
          color: Colors.white,
          size: 38,
        ),
      ),
      const SizedBox(height: 18),
      Text(
        'NubiBill',
        style: Theme.of(c).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      Text(
        'BUSINESS MANAGEMENT',
        style: Theme.of(c).textTheme.labelSmall
            ?.copyWith(letterSpacing: 2, color: Colors.black54),
      ),
    ],
  );
}
