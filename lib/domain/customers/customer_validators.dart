class CustomerValidators {
  const CustomerValidators._();

  /// Official 2-digit Indian GST state code to state name mapping.
  static const Map<String, String> gstStateCodes = {
    '01': 'Jammu and Kashmir',
    '02': 'Himachal Pradesh',
    '03': 'Punjab',
    '04': 'Chandigarh',
    '05': 'Uttarakhand',
    '06': 'Haryana',
    '07': 'Delhi',
    '08': 'Rajasthan',
    '09': 'Uttar Pradesh',
    '10': 'Bihar',
    '11': 'Sikkim',
    '12': 'Arunachal Pradesh',
    '13': 'Nagaland',
    '14': 'Manipur',
    '15': 'Mizoram',
    '16': 'Tripura',
    '17': 'Meghalaya',
    '18': 'Assam',
    '19': 'West Bengal',
    '20': 'Jharkhand',
    '21': 'Odisha',
    '22': 'Chhattisgarh',
    '23': 'Madhya Pradesh',
    '24': 'Gujarat',
    '25': 'Daman and Diu',
    '26': 'Dadra and Nagar Haveli and Daman and Diu',
    '27': 'Maharashtra',
    '28': 'Andhra Pradesh (Old)',
    '29': 'Karnataka',
    '30': 'Goa',
    '31': 'Lakshadweep',
    '32': 'Kerala',
    '33': 'Tamil Nadu',
    '34': 'Puducherry',
    '35': 'Andaman and Nicobar Islands',
    '36': 'Telangana',
    '37': 'Andhra Pradesh',
    '38': 'Ladakh',
    '97': 'Other Territory',
    '99': 'Centre Jurisdiction',
  };

  static String normalizePhone(String value) =>
      value.replaceAll(RegExp(r'\D'), '');

  static bool isValidPhone(String value) =>
      RegExp(r'^\d{10}$').hasMatch(normalizePhone(value));

  /// Strips all whitespace and normalizes GSTIN to uppercase.
  static String normalizeGstin(String? value) =>
      value?.replaceAll(RegExp(r'\s+'), '').toUpperCase() ?? '';

  /// Checks whether a given state code is a valid Indian GST state code.
  static bool isValidStateCode(String? code) =>
      code != null && gstStateCodes.containsKey(code);

  /// Resolves the official state name for a GST state code.
  static String? stateNameFromCode(String? code) =>
      code == null ? null : gstStateCodes[code];

  /// Extracts the 2-digit state code from a GSTIN if it matches valid state codes.
  static String? stateCodeFromGstin(String? value) {
    final gstin = normalizeGstin(value);
    if (gstin.length < 2) return null;
    final code = gstin.substring(0, 2);
    return isValidStateCode(code) ? code : null;
  }

  /// Validates the 15-character GSTIN structure and official state code.
  static bool isValidGstinStructure(String? value) {
    final gstin = normalizeGstin(value);
    if (gstin.length != 15) return false;
    final structureRegex =
        RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');
    if (!structureRegex.hasMatch(gstin)) return false;
    final stateCode = gstin.substring(0, 2);
    return isValidStateCode(stateCode);
  }

  /// Calculates the official Luhn mod-36 checksum for the 15th character.
  static bool isValidGstinChecksum(String? value) {
    final gstin = normalizeGstin(value);
    if (gstin.length != 15) return false;
    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    var factor = 2;
    var sum = 0;
    for (var index = gstin.length - 2; index >= 0; index--) {
      final code = chars.indexOf(gstin[index]);
      if (code < 0) return false;
      final product = code * factor;
      sum += (product ~/ 36) + (product % 36);
      factor = factor == 2 ? 1 : 2;
    }
    final check = (36 - (sum % 36)) % 36;
    return chars[check] == gstin[gstin.length - 1];
  }

  /// Validates a GSTIN. If null or empty, returns true (optional for unregistered).
  /// If non-empty, requires valid structure, state code, and checksum.
  static bool isValidGstin(String? value) {
    final gstin = normalizeGstin(value);
    if (gstin.isEmpty) return true;
    if (!isValidGstinStructure(gstin)) return false;
    return isValidGstinChecksum(gstin);
  }

  /// Validates GSTIN for a customer registering for GST.
  /// Returns a human-friendly validation error message or null if valid.
  static String? validateGstinForRegistration(String? value) {
    final gstin = normalizeGstin(value);
    if (gstin.isEmpty) {
      return 'GSTIN is required for GST-registered customers.';
    }
    if (gstin.length != 15) {
      return 'GSTIN must be exactly 15 characters (currently ${gstin.length}).';
    }
    final stateCode = gstin.substring(0, 2);
    if (!isValidStateCode(stateCode)) {
      return 'Invalid GST state code "$stateCode". Expected valid code (01-38, 97).';
    }
    final structureRegex =
        RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');
    if (!structureRegex.hasMatch(gstin)) {
      return 'Invalid GSTIN structure. Expected format: 22AAAAA0000A1Z5.';
    }
    if (!isValidGstinChecksum(gstin)) {
      return 'Invalid GSTIN checksum character. Please check for typos.';
    }
    return null;
  }
}
