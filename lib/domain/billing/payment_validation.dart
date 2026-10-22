import 'billing_models.dart';

class PaymentSplit {
  const PaymentSplit({
    required this.cashPaise,
    required this.upiPaise,
    required this.advancePaise,
    required this.duePaise,
  });

  final int cashPaise;
  final int upiPaise;
  final int advancePaise;
  final int duePaise;
}

class PaymentValidation {
  const PaymentValidation._();

  static PaymentSplit validate({
    required int grandTotalPaise,
    required int cashPaise,
    required int upiPaise,
    required int advancePaise,
    required int duePaise,
    required bool customerAttached,
    required PaymentMode mode,
  }) {
    final values = [grandTotalPaise, cashPaise, upiPaise, advancePaise, duePaise];
    if (values.any((value) => value < 0)) {
      throw ArgumentError('Payment values cannot be negative.');
    }
    if (!customerAttached && (advancePaise > 0 || duePaise > 0 || mode == PaymentMode.udhaar)) {
      throw ArgumentError('A customer is required for advance or Udhaar.');
    }
    if (!customerAttached && cashPaise + upiPaise != grandTotalPaise) {
      throw ArgumentError('Walk-in bills must be paid fully by cash or UPI.');
    }
    if (cashPaise + upiPaise + advancePaise + duePaise != grandTotalPaise) {
      throw ArgumentError('Cash + UPI + advance + due must equal the bill total.');
    }
    return PaymentSplit(
      cashPaise: cashPaise,
      upiPaise: upiPaise,
      advancePaise: advancePaise,
      duePaise: duePaise,
    );
  }
}
