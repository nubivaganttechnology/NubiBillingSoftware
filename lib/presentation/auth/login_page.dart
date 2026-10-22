import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/config/environment_config.dart';
import '../app_controller.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(), _password = TextEditingController();
  bool _visible = false, _remember = false, _submitted = false;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _emailValidator(String? v) {
    final x = v?.trim() ?? '';
    if (x.isEmpty) {
      return 'Enter your email address';
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(x)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _submitted = true);
    await widget.controller.signIn(
      _email.text.trim(),
      _password.text,
      remember: _remember,
    );
    if (mounted) setState(() => _submitted = false);
  }

  Future<void> _showRuntimeDiagnostics() async {
    final diagnostics = await widget.controller.runtimeDiagnostics();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Runtime diagnostics'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(diagnostics),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              widget.controller.retryCatalogueSynchronization();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.sync),
            label: const Text('Retry catalogue sync'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final wide = MediaQuery.sizeOf(c).width > 760;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 980 : 440),
          child: Card(
            color: Colors.white,
            elevation: 1,
            clipBehavior: Clip.antiAlias,
            borderOnForeground: false,
            child: wide
                ? Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 600,
                          color: const Color(0xFF132B45),
                          padding: const EdgeInsets.all(48),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.storefront_rounded,
                                color: Color(0xFFC18B35),
                                size: 54,
                              ),
                              const SizedBox(height: 36),
                              Text(
                                'Every business, one clear view.',
                                style: Theme.of(c).textTheme.headlineMedium
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Secure access to the businesses and outlets that keep you moving.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(48),
                          child: _formContent(c),
                        ),
                      ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.all(30),
                    child: _formContent(c),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _formContent(BuildContext c) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.storefront_rounded,
          size: 42,
          color: Color(0xFFC18B35),
        ),
        const SizedBox(height: 14),
        Text(
          'Welcome Back',
          textAlign: TextAlign.center,
          style: Theme.of(c).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Sign in to NubiBill ERP',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 30),
        TextFormField(
          controller: _email,
          enableInteractiveSelection: true,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(
            labelText: 'Email address',
            prefixIcon: Icon(Icons.mail_outline),
          ),
          validator: _emailValidator,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _password,
          enableInteractiveSelection: true,
          obscureText: !_visible,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          onFieldSubmitted: (_) => _login(),
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _visible ? 'Hide password' : 'Show password',
              onPressed: () => setState(() => _visible = !_visible),
              icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
            ),
          ),
          validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _remember,
                  onChanged: (v) => setState(() => _remember = v ?? false),
                ),
                const Text('Remember me'),
              ],
            ),
            TextButton(
              onPressed: () => showDialog<void>(
                context: c,
                builder: (context) => AlertDialog(
                  title: const Text('Forgot password?'),
                  content: const Text(
                    'Please contact your administrator to reset your password.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Forgot password?'),
            ),
          ],
        ),
        if (widget.controller.error.isNotEmpty) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              widget.controller.error,
              style: TextStyle(color: Theme.of(c).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _submitted ? null : _login,
          child: _submitted
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Login'),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            'Version ${EnvironmentConfig.appVersion}',
            style: const TextStyle(fontSize: 12, color: Colors.black38),
          ),
        ),
        if (kDebugMode)
          Center(
            child: TextButton.icon(
              onPressed: _showRuntimeDiagnostics,
              icon: const Icon(Icons.info_outline, size: 16),
              label: const Text('Runtime diagnostics'),
            ),
          ),
      ],
    ),
  );
}
