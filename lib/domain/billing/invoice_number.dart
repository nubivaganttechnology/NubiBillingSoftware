class InvoiceNumber {
  const InvoiceNumber._();

  /// The FY label is the year in which April falls: April 2026 starts FY "26".
  static String financialYearLabel(DateTime date) {
    final year = date.month >= 4 ? date.year : date.year - 1;
    return (year % 100).toString().padLeft(2, '0');
  }

  static String format({
    required String businessShortCode,
    required DateTime date,
    required int sequence,
  }) {
    final code = businessShortCode.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(code)) {
      throw ArgumentError.value(businessShortCode, 'businessShortCode');
    }
    if (sequence < 1 || sequence > 99999) {
      throw ArgumentError.value(sequence, 'sequence');
    }
    final value = '$code-${financialYearLabel(date)}-${sequence.toString().padLeft(5, '0')}';
    if (value.length > 16) throw ArgumentError('Invoice number exceeds 16 characters.');
    return value;
  }
}
