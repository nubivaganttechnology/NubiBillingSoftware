enum BillingTaxMode { gst, nonGst }

enum TaxStructure { intraState, interState }

enum PaymentMode { cash, upi, split, udhaar }

class BillLineInput {
  const BillLineInput({
    required this.variantId,
    required this.sku,
    required this.name,
    required this.hsn,
    required this.quantity,
    required this.unitPricePaise,
    required this.gstRateBps,
    required this.priceIncludesTax,
    this.discountPaise = 0,
    this.batchId,
    this.unit = 'UNIT',
    this.conversionFactor = 1,
    this.trackStock = true,
  });

  final String variantId;
  final String sku;
  final String name;
  final String hsn;
  final int quantity;
  final int unitPricePaise;
  final int gstRateBps;
  final bool priceIncludesTax;
  final String? batchId;
  final int discountPaise;
  final String unit;
  final int conversionFactor;
  final bool trackStock;

  int get quantityBase => quantity * conversionFactor;
}

class CalculatedBillLine {
  const CalculatedBillLine({
    required this.input,
    required this.grossPaise,
    required this.taxablePaise,
    required this.taxPaise,
    required this.lineTotalPaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
  });

  final BillLineInput input;
  final int grossPaise;
  final int taxablePaise;
  final int taxPaise;
  final int lineTotalPaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
}

class CalculatedBill {
  const CalculatedBill({
    required this.lines,
    required this.subtotalPaise,
    required this.totalDiscountPaise,
    required this.taxableTotalPaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    required this.taxTotalPaise,
    required this.roundOffPaise,
    required this.grandTotalPaise,
  });

  final List<CalculatedBillLine> lines;
  final int subtotalPaise;
  final int totalDiscountPaise;
  final int taxableTotalPaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int taxTotalPaise;
  final int roundOffPaise;
  final int grandTotalPaise;
}
