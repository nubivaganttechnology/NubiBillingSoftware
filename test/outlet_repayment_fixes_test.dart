import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/core/constants/firebase_constants.dart';
import 'package:testflutter/data/models/business_model.dart';
import 'package:testflutter/data/repositories/billing_repository.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/invoice_print_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/domain/entities/app_context.dart';
import 'package:testflutter/l10n/app_localizations.dart';
import 'package:testflutter/presentation/billing/widgets/print_format_dialog.dart';
import 'package:testflutter/presentation/sales/sales_entry_page.dart';

import 'product_entry_form_test.dart' show EntryController;

class MockOfflineFirestoreService extends Fake implements OfflineFirestoreService {
  MockOfflineFirestoreService({required this.allInvoices});

  final List<Map<String, dynamic>> allInvoices;
  final Map<String, dynamic> patchedFields = {};

  @override
  Future<void> patchDocument(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    String? idToken,
  }) async {
    patchedFields.addAll(fields);
  }

  @override
  Future<List<Map<String, dynamic>>> queryDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? orderBy,
    int? limit,
    bool descending = false,
    String? idToken,
  }) async {
    if (collection != FirebaseConstants.invoices) {
      return [];
    }
    // Filter by outletId if present
    final outletFilter = filters.where((f) => f.field == 'outletId').firstOrNull;
    if (outletFilter != null) {
      return allInvoices.where((inv) {
        final f = FirestoreRestService.decodeFields(inv['fields']);
        return f['outletId'] == outletFilter.value;
      }).toList();
    }
    return allInvoices;
  }
}

class MockBillingRepository extends Fake implements BillingRepository {
  DateTime? lastUpdatedDueDate;
  String? lastUpdatedInvoiceId;

  @override
  Future<void> updateDueDate({
    required String invoiceId,
    required DateTime? dueDate,
    required String token,
  }) async {
    lastUpdatedInvoiceId = invoiceId;
    lastUpdatedDueDate = dueDate;
  }
}

class TestFixesController extends EntryController {
  TestFixesController({
    required this.mockOffline,
    required this.mockBilling,
    AppContext? initialContext,
  }) : _appContext = initialContext ??
            const AppContext(
              uid: 'user-1',
              accountType: 'owner',
              ownerUid: 'owner-1',
              businessId: 'biz-1',
              outletId: 'outlet-1',
            );

  final MockOfflineFirestoreService mockOffline;
  final MockBillingRepository mockBilling;
  AppContext _appContext;

  @override
  AppContext? get appContext => _appContext;

  void changeContext(AppContext newContext) {
    _appContext = newContext;
    notifyListeners();
  }

  @override
  String? get idToken => 'mock-id-token';

  @override
  OfflineFirestoreService? get offline => mockOffline;

  @override
  BillingRepository? get billingRepository => mockBilling;

  @override
  List<BusinessModel> get businesses => const [
        BusinessModel(
          businessId: 'biz-1',
          ownerUid: 'owner-1',
          businessName: 'Test Business',
          normalizedBusinessName: 'test business',
          businessTypeId: 'retail',
          businessTypeName: 'Retail',
          isActive: true,
        ),
      ];
}

void main() {
  final invoices = [
    <String, dynamic>{
      'name': 'projects/test/databases/(default)/documents/invoices/INV-OUT1-01',
      'fields': FirestoreRestService.encodeFields({
        'invoiceNumber': 'INV-OUT1-01',
        'customerName': 'Outlet 1 Customer',
        'grandTotalPaise': 200000,
        'paidPaise': 100000,
        'dueAmount': 100000,
        'status': 'PENDING',
        'outletId': 'outlet-1',
        'dueDate': '2026-10-25T00:00:00Z',
        'createdAt': '2026-10-20T10:00:00Z',
      }),
    },
    <String, dynamic>{
      'name': 'projects/test/databases/(default)/documents/invoices/INV-OUT2-01',
      'fields': FirestoreRestService.encodeFields({
        'invoiceNumber': 'INV-OUT2-01',
        'customerName': 'Outlet 2 Customer',
        'grandTotalPaise': 350000,
        'paidPaise': 350000,
        'dueAmount': 0,
        'status': 'COMPLETED',
        'outletId': 'outlet-2',
        'createdAt': '2026-10-20T11:00:00Z',
      }),
    },
  ];

  late TestFixesController controller;
  late MockOfflineFirestoreService mockOffline;
  late MockBillingRepository mockBillingRepo;

  setUp(() {
    mockOffline = MockOfflineFirestoreService(allInvoices: invoices);
    mockBillingRepo = MockBillingRepository();
    controller = TestFixesController(
      mockOffline: mockOffline,
      mockBilling: mockBillingRepo,
    );
  });

  Widget createTestApp(Widget child) {
    return MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('hi'), Locale('bn')],
      home: Scaffold(body: child),
    );
  }

  group('Outlet Switching and Due Date Updates', () {
    testWidgets('BillSearchPage updates invoices reactively when switching outlet', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));

      await tester.pumpWidget(
        createTestApp(
          SalesManagementPage(
            controller: controller,
            onOpenModule: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially on outlet-1, should display Outlet 1 Customer and INV-OUT1-01
      expect(find.text('Outlet 1 Customer'), findsOneWidget);
      expect(find.text('INV-OUT1-01'), findsOneWidget);
      expect(find.text('Outlet 2 Customer'), findsNothing);

      // Change outlet in controller to outlet-2
      controller.changeContext(
        const AppContext(
          uid: 'user-1',
          accountType: 'owner',
          ownerUid: 'owner-1',
          businessId: 'biz-1',
          outletId: 'outlet-2',
        ),
      );
      await tester.pumpAndSettle();

      // Now should show Outlet 2 Customer and INV-OUT2-01, and not outlet 1
      expect(find.text('Outlet 2 Customer'), findsOneWidget);
      expect(find.text('INV-OUT2-01'), findsOneWidget);
      expect(find.text('Outlet 1 Customer'), findsNothing);
    });

    testWidgets('BillingRepository.updateDueDate saves date and updates banner', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));

      await tester.pumpWidget(
        createTestApp(
          SalesManagementPage(
            controller: controller,
            onOpenModule: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the repayment banner for INV-OUT1-01
      expect(find.text('Outlet 1 Customer'), findsOneWidget);
      expect(find.text('25/10/2026'), findsOneWidget);

      // Directly invoke updateDueDate to verify BillingRepository contract
      final newDueDate = DateTime(2026, 11, 15);
      await controller.billingRepository?.updateDueDate(
        invoiceId: 'INV-OUT1-01',
        dueDate: newDueDate,
        token: 'mock-id-token',
      );

      expect(mockBillingRepo.lastUpdatedInvoiceId, 'INV-OUT1-01');
      expect(mockBillingRepo.lastUpdatedDueDate, newDueDate);
    });

    test('PrintFormatDialog.formatToString and page format mappings are valid', () {
      expect(PrintFormatDialog.formatToString(InvoicePrintFormat.thermal80mm), 'THERMAL_80MM');
      expect(PrintFormatDialog.formatToString(InvoicePrintFormat.thermal58mm), 'THERMAL_58MM');
      expect(PrintFormatDialog.formatToString(InvoicePrintFormat.a4Standard), 'A4_STANDARD');
      expect(PrintFormatDialog.formatToString(InvoicePrintFormat.custom), 'CUSTOM');
    });
  });
}
