import 'billing_models.dart';

class BillCalculator {
  const BillCalculator();

  CalculatedBill calculate({
    required List<BillLineInput> lines,
    required BillingTaxMode taxMode,
    required TaxStructure taxStructure,
  }) {
    final calculated = <CalculatedBillLine>[];
    for (final input in lines) {
      if (input.quantity <= 0) {
        throw ArgumentError.value(input.quantity, 'quantity');
      }
      if (input.unitPricePaise < 0 || input.discountPaise < 0) {
        throw ArgumentError('Money values cannot be negative.');
      }
      final gross = input.quantity * input.unitPricePaise;
      final discount = input.discountPaise.clamp(0, gross);
      final net = gross - discount;
      final rate = taxMode == BillingTaxMode.gst ? input.gstRateBps : 0;
      final taxable = input.priceIncludesTax
          ? _roundDivide(net * 10000, 10000 + rate)
          : net;
      final tax = input.priceIncludesTax
          ? net - taxable
          : _roundDivide(taxable * rate, 10000);
      final cgst = taxStructure == TaxStructure.intraState ? tax ~/ 2 : 0;
      final sgst = taxStructure == TaxStructure.intraState ? tax - cgst : 0;
      final igst = taxStructure == TaxStructure.interState ? tax : 0;
      calculated.add(
        CalculatedBillLine(
          input: input,
          grossPaise: gross,
          taxablePaise: taxable,
          taxPaise: tax,
          lineTotalPaise: taxable + tax,
          cgstPaise: cgst,
          sgstPaise: sgst,
          igstPaise: igst,
        ),
      );
    }
    final subtotal = calculated.fold<int>(0, (sum, line) => sum + line.grossPaise);
    final discount = lines.fold<int>(0, (sum, line) {
      final gross = line.quantity * line.unitPricePaise;
      return sum + line.discountPaise.clamp(0, gross);
    });
    final taxable = calculated.fold<int>(
      0,
      (sum, line) => sum + line.taxablePaise,
    );
    final cgst = calculated.fold<int>(0, (sum, line) => sum + line.cgstPaise);
    final sgst = calculated.fold<int>(0, (sum, line) => sum + line.sgstPaise);
    final igst = calculated.fold<int>(0, (sum, line) => sum + line.igstPaise);
    final tax = cgst + sgst + igst;
    final beforeRound = taxable + tax;
    final rounded = ((beforeRound + 50) ~/ 100) * 100;
    return CalculatedBill(
      lines: calculated,
      subtotalPaise: subtotal,
      totalDiscountPaise: discount,
      taxableTotalPaise: taxable,
      cgstPaise: cgst,
      sgstPaise: sgst,
      igstPaise: igst,
      taxTotalPaise: tax,
      roundOffPaise: rounded - beforeRound,
      grandTotalPaise: rounded,
    );
  }

  int _roundDivide(int numerator, int denominator) {
    if (denominator <= 0) throw ArgumentError.value(denominator, 'denominator');
    return (numerator + denominator ~/ 2) ~/ denominator;
  }
}
