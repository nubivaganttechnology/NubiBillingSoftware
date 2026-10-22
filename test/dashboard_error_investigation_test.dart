import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/repositories/dashboard_repository.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/domain/entities/app_context.dart';

class _FakeFirestoreService implements FirestoreDataService {
  @override
  Future<Map<String, dynamic>> aggregateDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? sumField,
    String? idToken,
  }) async {
    return {'count': 1, 'total': 450.0};
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
    if (collection == 'invoices') {
      return [
        {
          'name': 'invoices/REQ_1791557977238964',
          'fields': {
            'invoiceNumber': {'stringValue': 'SUMANE-26-00001'},
            'createdAt': {'stringValue': '2026-10-09T14:59:37.238964Z'},
            'grandTotalPaise': {'integerValue': '45000'},
            'status': {'stringValue': 'PAID'},
          },
        },
      ];
    }
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('DashboardRepository.load succeeds with string createdAt and grandTotalPaise', () async {
    final repo = DashboardRepository(_FakeFirestoreService());
    const context = AppContext(
      uid: 'C6btLkx5SyZvUQOzOeUUd7XxsFh2',
      ownerUid: 'C6btLkx5SyZvUQOzOeUUd7XxsFh2',
      businessId: 'BUS-001',
      outletId: 'OUT-001',
      accountType: 'owner',
      permissions: [],
    );

    final summary = await repo.load(
      context,
      'token',
      includeSales: true,
      includePurchases: true,
      includeProducts: true,
      includeCustomers: true,
    );

    expect(summary, isNotNull);
    expect(summary.recentSales, hasLength(1));
    final sale = summary.recentSales.single;
    expect(sale.invoiceNumber, 'SUMANE-26-00001');
    expect(sale.amount, 450.0);
    expect(sale.paymentStatus, 'PAID');
    expect(sale.createdAt, DateTime.parse('2026-10-09T14:59:37.238964Z'));
  });
}
