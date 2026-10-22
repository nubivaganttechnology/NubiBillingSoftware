/// Formats stock balances stored in thousandths of the variant's base unit.
///
/// For example, 10000 is displayed as 10 and 76063 as 76.063, matching the
/// Products table's existing stock presentation.
String formatStockQuantity(num thousandths) {
  final value = thousandths / 1000;
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}
