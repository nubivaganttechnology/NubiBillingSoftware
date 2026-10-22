import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../models/expense_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';

class ExpenseRepository {
  ExpenseRepository(this.firestore);
  final FirestoreDataService firestore;

  static const List<String> defaultCategories = [
    'Rent & Lease',
    'Salaries & Wages',
    'Electricity & Utilities',
    'Freight & Delivery',
    'Repairs & Maintenance',
    'Tea & Refreshments',
    'Packaging & Materials',
    'Office & Stationery',
    'Marketing & Ads',
    'Taxes & Bank Fees',
    'Miscellaneous',
  ];

  static const List<String> paymentModes = [
    'CASH',
    'UPI',
    'BANK_TRANSFER',
    'CHEQUE',
    'CARD',
  ];

  Future<List<ExpenseModel>> getExpenses({
    required String tenantId,
    required String businessId,
    String? outletId,
    DateTime? startDate,
    DateTime? endDate,
    String? category,
    String? paymentMode,
    required String token,
  }) async {
    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.expenses,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
      ],
      idToken: token,
    );

    final results = <ExpenseModel>[];
    for (final doc in docs) {
      final fields = FirestoreRestService.decodeFields(doc['fields']);
      final id = (doc['name'] as String? ?? '').split('/').last;
      final expense = ExpenseModel.fromData(id, fields);

      // In-memory filters for dates, outlet, category, and payment mode
      if (outletId != null &&
          outletId.isNotEmpty &&
          expense.outletId != null &&
          expense.outletId != outletId) {
        continue;
      }
      if (category != null && category.isNotEmpty && category != 'ALL') {
        if (expense.category != category) continue;
      }
      if (paymentMode != null && paymentMode.isNotEmpty && paymentMode != 'ALL') {
        if (expense.paymentMode != paymentMode) continue;
      }
      if (startDate != null && expense.expenseDate.isBefore(startDate)) {
        continue;
      }
      if (endDate != null && expense.expenseDate.isAfter(endDate)) {
        continue;
      }
      results.add(expense);
    }

    results.sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
    return results;
  }

  Future<ExpenseModel> createExpense({
    required String tenantId,
    required String businessId,
    String? outletId,
    required String title,
    required String category,
    required int amountPaise,
    required DateTime expenseDate,
    String paymentMode = 'CASH',
    String? payeeName,
    String? referenceNumber,
    String? notes,
    String? createdBy,
    required String token,
  }) async {
    final id = IdGenerator.create('EXP');
    final expense = ExpenseModel(
      expenseId: id,
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      title: title.trim(),
      category: category.trim(),
      amountPaise: amountPaise,
      expenseDate: expenseDate,
      paymentMode: paymentMode,
      payeeName: payeeName?.trim(),
      referenceNumber: referenceNumber?.trim(),
      notes: notes?.trim(),
      createdAt: DateTime.now(),
      createdBy: createdBy,
    );

    await firestore.createDocument(
      FirebaseConstants.expenses,
      id,
      expense.toMap(),
      idToken: token,
    );

    return expense;
  }

  Future<void> voidExpense({
    required String expenseId,
    required String token,
  }) async {
    final current = await firestore.getDocument(
      FirebaseConstants.expenses,
      expenseId,
      idToken: token,
    );
    final fields = FirestoreRestService.decodeFields(current['fields']);
    if (fields['salaryPeriodId'] != null || fields['recognitionBasis'] == 'ACCRUAL') {
      throw const AppException(
        'Salary accruals must be corrected through the salary period audit trail.',
      );
    }
    await firestore.updateDocument(
      FirebaseConstants.expenses,
      expenseId,
      {
        'status': 'VOID',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      idToken: token,
    );
  }
}
