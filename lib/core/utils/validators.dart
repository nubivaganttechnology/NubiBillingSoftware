class AppValidators {
  AppValidators._();

  static String normalizeBusinessName(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String normalizeEmail(String value) => value.trim().toLowerCase();

  static String? businessName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty || name.replaceAll(RegExp(r'\s'), '').length < 2) {
      return 'Enter a valid business name.';
    }
    if (name.length > 120 || name.contains('/')) {
      return 'Business name must be 120 characters or fewer and cannot contain /.';
    }
    return null;
  }

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter a business email.';
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
        ? null
        : 'Enter a valid email address.';
  }

  static String normalizeIndianPhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final local = digits.length == 12 && digits.startsWith('91')
        ? digits.substring(2)
        : digits.length == 11 && digits.startsWith('0')
        ? digits.substring(1)
        : digits;
    return '+91$local';
  }

  static String? indianPhone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    final local = digits.length == 12 && digits.startsWith('91')
        ? digits.substring(2)
        : digits.length == 11 && digits.startsWith('0')
        ? digits.substring(1)
        : digits;
    return RegExp(r'^[6-9][0-9]{9}$').hasMatch(local)
        ? null
        : 'Enter a valid 10-digit Indian mobile number.';
  }

  static String normalizeGstin(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toUpperCase();

  static String? gstin(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$')
            .hasMatch(normalizeGstin(value))
        ? null
        : 'Enter a valid 15-character GSTIN using letters and numbers (for example, 27ABCDE1234F1Z5).';
  }

  static String? required(String? value, String label) =>
      value == null || value.trim().isEmpty ? 'Enter $label.' : null;
}
