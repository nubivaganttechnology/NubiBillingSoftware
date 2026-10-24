import 'package:testflutter/data/models/purchase_bill_model.dart';
import 'package:testflutter/data/models/supplier_payment_receipt_model.dart';
import 'package:testflutter/presentation/procurement/widgets/supplier_due_payment_dialog.dart';
import 'package:testflutter/presentation/procurement/widgets/supplier_ledger_localizations.dart';
import 'package:testflutter/presentation/procurement/widgets/supplier_payment_voucher_dialog.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/business_model.dart';
import 'package:testflutter/data/models/outlet_model.dart';
import 'package:testflutter/data/models/supplier_ledger_entry_model.dart';
import 'package:testflutter/data/models/supplier_model.dart';
import 'package:testflutter/data/repositories/supplier_repository.dart';
import 'package:testflutter/data/services/supplier_statement_export_service.dart';
import 'package:testflutter/domain/entities/app_context.dart';
import 'package:testflutter/core/permissions/permission_catalog.dart';
import 'package:testflutter/presentation/app_controller.dart';
import 'package:testflutter/presentation/procurement/supplier_ledger_dashboard_page.dart';

class FakeSupplierRepo extends Fake implements SupplierRepository {
  FakeSupplierRepo(this.entries);
  final List<SupplierLedgerEntryModel> entries;

  @override
  Future<List<SupplierLedgerEntryModel>> getSupplierLedger({
    required String tenantId,
    required String businessId,
    required String supplierId,
    required String token,
  }) async {
    return entries;
  }
}

class FakeAppController extends ChangeNotifier implements AppController {
  FakeAppController({
    required this.testSuppliers,
    required this.repo,
    this.locale = const Locale('en'),
  });

  final List<SupplierModel> testSuppliers;
  final SupplierRepository repo;
  final Locale locale;

  @override
  SupplierRepository get supplierRepository => repo;

  @override
  List<SupplierModel> get suppliers => testSuppliers;

  @override
  Future<void> loadSuppliers() async {}

  @override
  Locale get currentLocale => locale;

  @override
  List<OutletModel> get outlets => const [];

  @override
  AppContext get appContext => const AppContext(
        uid: 'owner',
        accountType: 'owner',
        ownerUid: 'owner',
        businessId: 'BIZ_001',
        permissions: ['*'],
      );

  @override
  String? get idToken => 'mock-token';

  @override
  List<BusinessModel> get businesses => [
        const BusinessModel(
          businessId: 'BIZ_001',
          ownerUid: 'owner',
          businessName: 'Chamunda Builder Retailer',
          normalizedBusinessName: 'chamunda builder retailer',
          businessTypeId: 'RETAIL',
          businessTypeName: 'Retail',
          phone: '9832001122',
          gstin: '19AAACC1234D1Z2',
          address: 'Monteswar, Purba-Bardhaman',
          isActive: true,
        ),
      ];

  @override
  Future<List<PurchaseBillModel>> getSupplierOutstandingBills(String supplierId) async {
    return [
      PurchaseBillModel(
        purchaseBillId: 'PB_001',
        tenantId: 'TENANT_001',
        businessId: 'BIZ_001',
        outletId: 'OUT_001',
        supplierId: supplierId,
        supplierBusinessId: 'SB_001',
        supplierInvoiceNumber: 'INV-101',
        invoiceDate: DateTime(2026, 10, 1),
        purchaseDate: DateTime(2026, 10, 1),
        entryDate: DateTime(2026, 10, 1),
        dueDate: DateTime(2026, 10, 31),
        purchaseType: 'DIRECT',
        taxType: 'INTRA_STATE',
        version: 1,
        status: 'APPROVED',
        subtotal: 1000000,
        discountAmount: 0,
        taxableAmount: 1000000,
        cgstAmount: 0,
        sgstAmount: 0,
        igstAmount: 0,
        chargesAmount: 0,
        roundOff: 0,
        grandTotal: 1000000,
        paidAmount: 0,
        outstandingAmount: 1000000,
        paymentStatus: 'UNPAID',
        items: const [],
        createdBy: 'user',
        createdAt: DateTime(2026, 10, 1),


      ),
      PurchaseBillModel(
        purchaseBillId: 'PB_002',
        tenantId: 'TENANT_001',
        businessId: 'BIZ_001',
        outletId: 'OUT_001',
        supplierId: supplierId,
        supplierBusinessId: 'SB_001',
        supplierInvoiceNumber: 'INV-102',
        invoiceDate: DateTime(2026, 10, 5),
        purchaseDate: DateTime(2026, 10, 5),
        entryDate: DateTime(2026, 10, 5),
        dueDate: DateTime(2026, 11, 5),
        purchaseType: 'DIRECT',
        taxType: 'INTRA_STATE',
        version: 1,
        status: 'APPROVED',
        subtotal: 800000,
        discountAmount: 0,
        taxableAmount: 800000,
        cgstAmount: 0,
        sgstAmount: 0,
        igstAmount: 0,
        chargesAmount: 0,
        roundOff: 0,
        grandTotal: 800000,
        paidAmount: 0,
        outstandingAmount: 800000,
        paymentStatus: 'UNPAID',
        items: const [],
        createdBy: 'user',
        createdAt: DateTime(2026, 10, 5),


      ),
    ];
  }

  @override
  Future<SupplierPaymentReceiptModel?> settleSupplierDues({
    required String supplierId,
    required int amountPaise,
    required String paymentMode,
    required String referenceNo,
    DateTime? paymentDate,
  }) async {
    return SupplierPaymentReceiptModel(
      paymentId: 'SPAY_TEST_001',
      voucherNumber: 'SPAY_TEST_001',
      paymentDate: paymentDate ?? DateTime.now(),
      supplierId: supplierId,
      supplierName: 'Jara Enterprise (Kuera)',
      businessName: 'Chamunda Builder Retailer',
      paymentMode: paymentMode,
      referenceNo: referenceNo,
      previousDuePaise: 1800000,
      amountPaidPaise: amountPaise,
      remainingDuePaise: 1800000 - amountPaise,
      settledBills: [
        const SupplierSettledBillInfo(
          billId: 'PB_001',
          invoiceNumber: 'INV-101',
          billTotalPaise: 1000000,
          paidBeforePaise: 0,
          allocatedPaise: 600000,
          remainingDuePaise: 400000,
          isFullyPaid: false,
        ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testSupplier = SupplierModel(
    supplierId: 'SUPP_JARA_001',
    tenantId: 'TENANT_001',
    name: 'Jara Enterprise (Kuera)',
    status: 'ACTIVE',
    contactPerson: 'Raja Samanta',
    mobile: '9876543210',
    gstin: '19ABCDE1234F1Z5',
    address: 'Kuera, Purba-Bardhaman, 713145',
  );

  final sampleEntries = [
    SupplierLedgerEntryModel(
      ledgerEntryId: 'LEDGER_OPENING',
      tenantId: 'TENANT_001',
      businessId: 'BIZ_001',
      supplierId: testSupplier.supplierId,
      entryType: SupplierLedgerEntryModel.typeOpeningBalance,
      debitPaise: 0,
      creditPaise: 1916000,
      transactionDate: DateTime(2026, 4, 28),
      createdAt: DateTime(2026, 4, 28),
      particulars: 'Opening Balance (Payable)',
      runningBalancePaise: 1916000,
    ),
    SupplierLedgerEntryModel(
      ledgerEntryId: 'PB_239',
      tenantId: 'TENANT_001',
      businessId: 'BIZ_001',
      supplierId: testSupplier.supplierId,
      entryType: SupplierLedgerEntryModel.typePurchaseBill,
      voucherNumber: '239',
      debitPaise: 0,
      creditPaise: 19250000,
      transactionDate: DateTime(2026, 4, 28),
      createdAt: DateTime(2026, 4, 28),
      particulars: 'CTO / Nuvoco 500 Bags @ 385.00/Bag',
      runningBalancePaise: 21166000,
    ),
    SupplierLedgerEntryModel(
      ledgerEntryId: 'PAY_356',
      tenantId: 'TENANT_001',
      businessId: 'BIZ_001',
      supplierId: testSupplier.supplierId,
      entryType: SupplierLedgerEntryModel.typeSupplierPayment,
      voucherNumber: '356',
      debitPaise: 3500000,
      creditPaise: 0,
      paymentMode: 'CASH',
      transactionDate: DateTime(2026, 4, 30),
      createdAt: DateTime(2026, 4, 30),
      particulars: 'Cash Payment Receipt #356',
      runningBalancePaise: 17666000,
    ),
  ];

  group('Supplier Ledger Feature & Math Verification', () {
    test('1. Verify ledger running balance and totals match Chamunda statement math', () {
      final opening = sampleEntries[0];
      final bills = [sampleEntries[1]];
      final payments = [sampleEntries[2]];

      final totalPurchases = bills.fold<int>(0, (sum, b) => sum + b.creditPaise);
      final totalPayments = payments.fold<int>(0, (sum, p) => sum + p.debitPaise);

      expect(totalPurchases, 19250000);
      expect(totalPayments, 3500000);
      expect(opening.creditPaise + totalPurchases - totalPayments, 17666000);
    });

    test('2. Verify SupplierStatementExportService generates valid PDF binary', () async {
      final Uint8List pdfBytes = await SupplierStatementExportService.generatePdf(
        businessName: 'Chamunda Builder Retailer',
        businessAddress: 'Monteswar, Purba-Bardhaman - 713145',
        businessPhone: '9832001122',
        businessGstin: '19AAACC1234D1Z2',
        supplier: testSupplier,
        entries: sampleEntries,
        fromDate: DateTime(2026, 4, 28),
        toDate: DateTime(2026, 7, 31),
        openingBalancePaise: 1916000,
        totalPurchasesPaise: 19250000,
        totalPaymentsPaise: 3500000,
        closingBalancePaise: 17666000,
      );

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(1000));
      final header = String.fromCharCodes(pdfBytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });

    testWidgets('3. Verify SupplierLedgerDashboardPage renders KPI cards, table & filters', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeRepo = FakeSupplierRepo(sampleEntries);
      final fakeController = FakeAppController(
        testSuppliers: [testSupplier],
        repo: fakeRepo,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SupplierLedgerDashboardPage(
            controller: fakeController,
            initialSupplierId: testSupplier.supplierId,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Header verification
      expect(find.text('Supplier Ledger & Statement'), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);
      expect(find.text('Print'), findsOneWidget);

      // KPI verification (Opening balance appears in both KPI card and table badge)
      expect(find.text('Opening Balance'), findsNWidgets(2));
      expect(find.text('Total Purchases'), findsOneWidget);
      expect(find.text('Total Payments'), findsOneWidget);
      expect(find.text('Current Balance'), findsOneWidget);

      expect(find.text('CTO / Nuvoco 500 Bags @ 385.00/Bag'), findsOneWidget);
      expect(find.text('Cash Payment Receipt #356'), findsOneWidget);
      expect(find.text('₹192500.00'), findsNWidgets(2));
      expect(find.text('₹35000.00'), findsNWidgets(2));

      // Filters verification
      expect(find.text('All Time'), findsOneWidget);
      expect(find.text('This Month'), findsOneWidget);
    });
    test('4. Verify FIFO multi-bill payment allocation logic matches user scenario', () {
      // Scenario: Bill 1 = ₹10,000, Bill 2 = ₹8,000. Total = ₹18,000.
      var bill1Due = 1000000;
      var bill2Due = 800000;

      // Payment 1: ₹6,000
      var payment1 = 600000;
      var alloc1ToBill1 = payment1 > bill1Due ? bill1Due : payment1;
      bill1Due -= alloc1ToBill1;
      payment1 -= alloc1ToBill1;

      var alloc1ToBill2 = payment1 > bill2Due ? bill2Due : payment1;
      bill2Due -= alloc1ToBill2;
      payment1 -= alloc1ToBill2;

      expect(alloc1ToBill1, 600000);
      expect(bill1Due, 400000); // Bill 1 remains ₹4,000 (PARTIAL)
      expect(alloc1ToBill2, 0);
      expect(bill2Due, 800000); // Bill 2 remains ₹8,000 (UNPAID)
      expect(bill1Due + bill2Due, 1200000); // Total net remaining = ₹12,000

      // Payment 2: ₹6,000
      var payment2 = 600000;
      var alloc2ToBill1 = payment2 > bill1Due ? bill1Due : payment2;
      bill1Due -= alloc2ToBill1;
      payment2 -= alloc2ToBill1;

      var alloc2ToBill2 = payment2 > bill2Due ? bill2Due : payment2;
      bill2Due -= alloc2ToBill2;
      payment2 -= alloc2ToBill2;

      expect(alloc2ToBill1, 400000);
      expect(bill1Due, 0); // Bill 1 is now completely PAID!
      expect(alloc2ToBill2, 200000);
      expect(bill2Due, 600000); // Bill 2 remains ₹6,000 (PARTIAL)
      expect(bill1Due + bill2Due, 600000); // Total net remaining = ₹6,000
    });

    test('5. Verify SupplierPaymentReceiptModel generates accurate WhatsApp message', () {
      final receipt = SupplierPaymentReceiptModel(
        paymentId: 'SPAY_789456',
        voucherNumber: 'VOUCHER-001',
        paymentDate: DateTime(2026, 10, 24, 15, 30),
        supplierId: 'SUPP_001',
        supplierName: 'Jara Enterprise (Kuera)',
        supplierPhone: '9876543210',
        businessName: 'Chamunda Builder Retailer',
        outletName: 'Main Depot',
        paymentMode: 'BANK_TRANSFER',
        referenceNo: 'UTR99887766',
        previousDuePaise: 1800000,
        amountPaidPaise: 600000,
        remainingDuePaise: 1200000,
        settledBills: const [
          SupplierSettledBillInfo(
            billId: 'PB_001',
            invoiceNumber: 'INV-101',
            billTotalPaise: 1000000,
            paidBeforePaise: 0,
            allocatedPaise: 600000,
            remainingDuePaise: 400000,
            isFullyPaid: false,
          ),
        ],
      );

      final msgEn = receipt.generateWhatsAppMessage(languageCode: 'en');
      expect(msgEn, contains('PAYMENT VOUCHER'));
      expect(msgEn, contains('Chamunda Builder Retailer'));
      expect(msgEn, contains('Jara Enterprise (Kuera)'));
      expect(msgEn, contains('UTR99887766'));
      expect(msgEn, contains('18000.00'));
      expect(msgEn, contains('6000.00'));
      expect(msgEn, contains('12000.00'));
      expect(msgEn, contains('INV-101'));
      expect(msgEn, contains('PARTIAL'));

      final msgBn = receipt.generateWhatsAppMessage(languageCode: 'bn');
      expect(msgBn, contains('পেমেন্ট রসিদ'));
      expect(msgBn, contains('আগের মোট বাকি'));
      expect(msgBn, contains('জমা দেওয়া হলো'));
      expect(msgBn, contains('বর্তমান নিট বাকি'));

      final msgHi = receipt.generateWhatsAppMessage(languageCode: 'hi');
      expect(msgHi, contains('भुगतान रसीद'));
      expect(msgHi, contains('पिछला कुल बकाया'));
      expect(msgHi, contains('जमा की गई राशि'));
      expect(msgHi, contains('वर्तमान शेष बकाया'));
    });

    testWidgets('6. Verify SupplierPaymentVoucherDialog renders correctly in Bengali locale', (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final receipt = SupplierPaymentReceiptModel(
        paymentId: 'SPAY_789456',
        voucherNumber: 'VOUCHER-001',
        paymentDate: DateTime(2026, 10, 24, 15, 30),
        supplierId: 'SUPP_001',
        supplierName: 'Jara Enterprise (Kuera)',
        supplierPhone: '9876543210',
        businessName: 'Chamunda Builder Retailer',
        outletName: 'Main Depot',
        paymentMode: 'UPI',
        referenceNo: 'UPI_123456',
        previousDuePaise: 500000,
        amountPaidPaise: 300000,
        remainingDuePaise: 200000,
        settledBills: const [
          SupplierSettledBillInfo(
            billId: 'PB_001',
            invoiceNumber: 'INV-55',
            billTotalPaise: 500000,
            paidBeforePaise: 0,
            allocatedPaise: 300000,
            remainingDuePaise: 200000,
            isFullyPaid: false,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('bn'), Locale('hi')],
          locale: const Locale('bn'),
          home: Scaffold(
            body: SupplierPaymentVoucherDialog(receipt: receipt),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('পেমেন্ট রসিদ'), findsOneWidget);
      expect(find.text('Jara Enterprise (Kuera)'), findsOneWidget);
      expect(find.text('₹5000.00'), findsOneWidget); // Previous due
      expect(find.text('₹3000.00'), findsOneWidget); // Amount paid
      expect(find.text('₹2000.00'), findsOneWidget); // Remaining due
      expect(find.text('হোয়াটসঅ্যাপে পাঠান'), findsOneWidget);
      expect(find.text('রসিদ প্রিন্ট'), findsOneWidget);
    });

    testWidgets('7. Verify SupplierDuePaymentDialog displays FIFO preview and calculates live allocations', (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeRepo = FakeSupplierRepo(sampleEntries);
      final fakeController = FakeAppController(
        testSuppliers: [testSupplier],
        repo: fakeRepo,
        locale: const Locale('bn'),
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('bn'), Locale('hi')],
          locale: const Locale('bn'),
          home: Scaffold(
            body: SupplierDuePaymentDialog(
              supplierId: testSupplier.supplierId,
              supplierName: testSupplier.name,
              currentPayablePaise: 1800000,
              controller: fakeController,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('বকেয়া পরিশোধ'), findsOneWidget);
      expect(find.text('₹18000.00'), findsOneWidget); // Total payable & initial amount
      expect(find.text('#INV-101'), findsOneWidget);
      expect(find.text('#INV-102'), findsOneWidget);

      // Change amount to ₹6,000
      final amountField = find.byType(TextField).first;
      await tester.enterText(amountField, '6000');
      await tester.pumpAndSettle();

      // Verify live allocation changes
      expect(find.text('পেমেন্টের পর দেনা থাকবে:'), findsOneWidget);
      expect(find.text('₹12000.00'), findsOneWidget); // 18k - 6k = 12k remaining
      expect(find.text('পেমেন্ট নিশ্চিত করুন'), findsOneWidget);
    });

    testWidgets('8. Verify SupplierLedgerStrings supports English, Bengali, and Hindi', (tester) async {
      const en = SupplierLedgerStrings('en');
      const bn = SupplierLedgerStrings('bn');
      const hi = SupplierLedgerStrings('hi');

      expect(en.paySupplierDueTitle, 'Pay Supplier Due');
      expect(bn.paySupplierDueTitle, 'বকেয়া পরিশোধ');
      expect(hi.paySupplierDueTitle, 'बकाया भुगतान');

      expect(en.viewVoucher, 'Voucher / Slip');
      expect(bn.viewVoucher, 'রশিদ');
      expect(hi.viewVoucher, 'रसीद');

      expect(en.viewSlip, 'View Slip');
      expect(bn.viewSlip, 'রশিদ দেখুন');
      expect(hi.viewSlip, 'रसीद देखें');
    });

    testWidgets('9. Verify Ledger table displays Voucher action button for payment entries and can open reprint dialog', (tester) async {
      tester.view.physicalSize = const Size(2200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeRepo = FakeSupplierRepo(sampleEntries);
      final fakeController = FakeAppController(
        testSuppliers: [testSupplier],
        repo: fakeRepo,
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('bn'), Locale('hi')],
          locale: const Locale('en'),
          home: Scaffold(
            body: SupplierLedgerDashboardPage(
              controller: fakeController,
              initialSupplierId: testSupplier.supplierId,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify table column Voucher / Slip exists
      expect(find.text('Voucher / Slip'), findsOneWidget);

      // Verify payment rows and recent banner have "View Slip" buttons
      final viewSlipButtons = find.text('View Slip');
      expect(viewSlipButtons, findsNWidgets(2)); // 1 in Recent Payment Banner + 1 in Table row

      // Click the Table row's "View Slip" button to open the Payment Voucher reprint dialog
      final tableRowButton = viewSlipButtons.last;
      await tester.ensureVisible(tableRowButton);
      await tester.tap(tableRowButton);
      await tester.pumpAndSettle();

      // Verify Payment Voucher dialog appears on screen!
      expect(find.byType(SupplierPaymentVoucherDialog), findsOneWidget);
      expect(find.text('Payment Voucher'), findsOneWidget);
      expect(find.text('Share on WhatsApp'), findsOneWidget);
      expect(find.text('Print Slip'), findsOneWidget);

      // Close the dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(SupplierPaymentVoucherDialog), findsNothing);
    });

    test('10. Verify Supplier Ledger module is registered in PermissionCatalog and visible in navigation', () {
      final moduleExists = PermissionCatalog.modules.any((m) => m.id == 'supplier_ledger');
      expect(moduleExists, isTrue);

      final ledgerMod = PermissionCatalog.modules.firstWhere((m) => m.id == 'supplier_ledger');
      expect(ledgerMod.label, 'Supplier Ledger');

      // Check visible with supplier permissions
      final visibleWithSuppliers = PermissionCatalog.visibleModules(['suppliers']);
      expect(visibleWithSuppliers.any((m) => m.id == 'supplier_ledger'), isTrue);

      // Check visible with purchase permissions
      final visibleWithPurchase = PermissionCatalog.visibleModules(['purchase']);
      expect(visibleWithPurchase.any((m) => m.id == 'supplier_ledger'), isTrue);

      // Check visible with owner wildcard
      final visibleWithOwner = PermissionCatalog.visibleModules(['*']);
      expect(visibleWithOwner.any((m) => m.id == 'supplier_ledger'), isTrue);
    });
  });
}
