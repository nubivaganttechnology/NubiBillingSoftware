class CustomerValidators {
  const CustomerValidators._();

  static String normalizePhone(String value) =>
      value.replaceAll(RegExp(r'\D'), '');

  static bool isValidPhone(String value) => RegExp(
    r'^\d{10}$',
  ).hasMatch(normalizePhone(value));

  static String? stateCodeFromGstin(String? value) {
    final gstin = value?.trim().toUpperCase();
    if (gstin == null || gstin.isEmpty) return null;
    if (!RegExp(r'^\d{2}[A-Z0-9]{13}$').hasMatch(gstin)) return null;
    return gstin.substring(0, 2);
  }

  static bool isValidGstin(String? value) {
    final gstin = value?.trim().toUpperCase();
    if (gstin == null || gstin.isEmpty) return true;
    if (!RegExp(r'^\d{2}[A-Z0-9]{13}$').hasMatch(gstin)) return false;
    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    var factor = 2;
    var sum = 0;
    for (var index = gstin.length - 2; index >= 0; index--) {
      final code = chars.indexOf(gstin[index]);
      final product = code * factor;
      sum += (product ~/ 36) + (product % 36);
      factor = factor == 2 ? 1 : 2;
    }
    final check = (36 - (sum % 36)) % 36;
    return chars[check] == gstin[gstin.length - 1];
  }
}
