class PermissionIdMatcher {
  PermissionIdMatcher._();

  static const _moduleAliases = <String, String>{
    'product': 'products',
    'customer': 'customers',
    'supplier': 'suppliers',
  };

  static String normalize(String value) {
    var key = value.trim().toLowerCase().replaceAll('-', '_');

    for (final action in const ['view', 'manage']) {
      final prefix = '${action}_';
      if (key.startsWith(prefix)) {
        final remainder = _normalizeModulePrefix(key.substring(prefix.length));
        if (remainder != key.substring(prefix.length)) {
          return '$prefix$remainder';
        }
      }
    }

    key = _normalizeModulePrefix(key);
    return key;
  }

  static bool matches(String first, String second) =>
      normalize(first) == normalize(second);

  static String _normalizeModulePrefix(String value) {
    for (final entry in _moduleAliases.entries) {
      final alias = entry.key;
      if (value == alias ||
          value.startsWith('$alias.') ||
          value.startsWith('${alias}_')) {
        return '${entry.value}${value.substring(alias.length)}';
      }
    }
    return value;
  }
}
