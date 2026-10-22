class ExpenseModel {
  const ExpenseModel({
    required this.expenseId,
    required this.tenantId,
    required this.businessId,
    this.outletId,
    required this.title,
    required this.category,
    required this.amountPaise,
    required this.expenseDate,
    this.paymentMode = 'CASH',
    this.payeeName,
    this.referenceNumber,
    this.notes,
    this.status = 'ACTIVE',
    required this.createdAt,
    this.createdBy,
  });

  final String expenseId;
  final String tenantId;
  final String businessId;
  final String? outletId;
  final String title;
  final String category;
  final int amountPaise;
  final DateTime expenseDate;
  final String paymentMode;
  final String? payeeName;
  final String? referenceNumber;
  final String? notes;
  final String status;
  final DateTime createdAt;
  final String? createdBy;

  double get amountRupees => amountPaise / 100.0;
  bool get isActive => status == 'ACTIVE';

  factory ExpenseModel.fromData(String id, Map<String, dynamic> data) =>
      ExpenseModel(
        expenseId: data['expenseId'] as String? ?? id,
        tenantId: data['tenantId'] as String? ?? '',
        businessId: data['businessId'] as String? ?? '',
        outletId: data['outletId'] as String?,
        title: data['title'] as String? ?? '',
        category: data['category'] as String? ?? 'Miscellaneous',
        amountPaise: (data['amountPaise'] as num?)?.toInt() ?? 0,
        expenseDate: data['expenseDate'] is DateTime
            ? data['expenseDate'] as DateTime
            : DateTime.tryParse(data['expenseDate']?.toString() ?? '') ??
                DateTime.now(),
        paymentMode: data['paymentMode'] as String? ?? 'CASH',
        payeeName: data['payeeName'] as String?,
        referenceNumber: data['referenceNumber'] as String?,
        notes: data['notes'] as String?,
        status: data['status'] as String? ?? 'ACTIVE',
        createdAt: data['createdAt'] is DateTime
            ? data['createdAt'] as DateTime
            : DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
                DateTime.now(),
        createdBy: data['createdBy'] as String?,
      );

  Map<String, dynamic> toMap() => {
    'expenseId': expenseId,
    'tenantId': tenantId,
    'businessId': businessId,
    if (outletId != null && outletId!.isNotEmpty) 'outletId': outletId,
    'title': title,
    'category': category,
    'amountPaise': amountPaise,
    'expenseDate': expenseDate.toIso8601String(),
    'paymentMode': paymentMode,
    if (payeeName != null && payeeName!.isNotEmpty) 'payeeName': payeeName,
    if (referenceNumber != null && referenceNumber!.isNotEmpty)
      'referenceNumber': referenceNumber,
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
    if (createdBy != null && createdBy!.isNotEmpty) 'createdBy': createdBy,
  };
}
