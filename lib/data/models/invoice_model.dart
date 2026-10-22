import '../../domain/billing/billing_models.dart';

class FinalizeBillRequest {
  const FinalizeBillRequest({
    required this.requestId,
    required this.tenantId,
    required this.businessId,
    required this.outletId,
    required this.businessShortCode,
    required this.cashierUid,
    required this.createdAt,
    required this.lines,
    required this.taxMode,
    required this.taxStructure,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.customerStateCode,
    required this.customerGstin,
    required this.cashPaise,
    required this.upiPaise,
    required this.advancePaise,
    required this.duePaise,
    required this.dueDate,
    this.paymentMode,
  });

  final String requestId, tenantId, businessId, outletId, businessShortCode;
  final String cashierUid;
  final DateTime createdAt;
  final List<BillLineInput> lines;
  final BillingTaxMode taxMode;
  final TaxStructure taxStructure;
  final String? customerId,
      customerName,
      customerPhone,
      customerStateCode,
      customerGstin;
  final int cashPaise, upiPaise, advancePaise, duePaise;
  final DateTime? dueDate;
  final PaymentMode? paymentMode;
}

class FinalizeBillResult {
  const FinalizeBillResult({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.existing,
  });

  final String invoiceId;
  final String invoiceNumber;
  final bool existing;
}
